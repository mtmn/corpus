module Cover
  ( CoverSource
  , sanitizeKey
  , cacheJobKey
  , tryStartCacheFill
  , finishCacheFill
  , fetchLastfmCoverUrl
  , fetchDiscogsCoverUrl
  , coverSources
  , serveCover
  ) where

import Prelude

import Config (UserConfig, s3ConfigFromUser)
import Control.Alt ((<|>))
import Data.Argonaut.Core (toArray, toBoolean, toObject, toString)
import Data.Array (find, (!!))
import Data.Either (Either(..), hush)
import Data.Foldable (foldM, for_)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.String.CaseInsensitive (CaseInsensitiveString(..))
import Data.String.Regex (Regex, parseFlags, regex, replace)
import Effect (Effect)
import Effect.Aff (Aff, forkAff, try)
import Effect.Class (liftEffect)
import Effect.Exception as Exception
import Fetch (Method(GET), fetch)
import Fetch.Argonaut.Json (fromJson)
import Foreign.Object as Object
import Http (apiTimeout, imageTimeout, withTimeout)
import Image (arrayBufferByteLength, convertToAvif)
import JSURI (encodeURIComponent)
import Log as Log
import Metrics as Metrics
import Node.Buffer (fromArrayBuffer)
import Node.HTTP.OutgoingMessage (setHeader, toWriteable)
import Node.HTTP.ServerResponse (setStatusCode, toOutgoingMessage)
import Node.HTTP.Types (ServerResponse)
import Node.Stream (end)
import S3 (existsInS3, getPresignedUrl, uploadToS3)
import Web.URL (URL)
import Web.URL as URL
import Web.URL.URLSearchParams as URLSearchParams

foreign import tryStartCacheFillImpl :: String -> Effect Boolean
foreign import finishCacheFillImpl :: String -> Effect Unit

-- | Claim a cache-fill job when it is not already running or capacity is free.
tryStartCacheFill :: String -> Effect Boolean
tryStartCacheFill = tryStartCacheFillImpl

-- | Release a previously claimed cache-fill job.
finishCacheFill :: String -> Effect Unit
finishCacheFill = finishCacheFillImpl

type Response = ServerResponse

-- | A lookup source and cache key for one candidate cover image.
type CoverSource =
  { name :: String
  , s3Key :: String
  , findUrl :: Aff (Maybe String)
  }

-- | Normalize a source value for use in an S3 key.
sanitizeKey :: String -> String
sanitizeKey = safeReplace sanitizeKeyRe1 "_" >>> safeReplace sanitizeKeyRe2 "_"

safeReplace :: Maybe Regex -> String -> String -> String
safeReplace mRe replacement s = case mRe of
  Nothing -> s
  Just re -> replace re replacement s

sanitizeKeyRe1 :: Maybe Regex
sanitizeKeyRe1 = hush $ regex "[^a-z0-9.-]" (parseFlags "gi")

sanitizeKeyRe2 :: Maybe Regex
sanitizeKeyRe2 = hush $ regex "_{2,}" (parseFlags "g")

-- | Build a process-local key for one bucket/object cache-fill job.
cacheJobKey :: String -> String -> String
cacheJobKey bucket s3Key = bucket <> ":" <> s3Key

maxCoverBytes :: Number
maxCoverBytes = 10_000_000.0

getQueryParam :: String -> URL -> Maybe String
getQueryParam key url = URLSearchParams.get key (URL.searchParams url)

fetchCaaCoverUrl :: String -> Aff (Maybe String)
fetchCaaCoverUrl mbid = do
  let url = "https://coverartarchive.org/release/" <> mbid
  let headers = { "User-Agent": "corpus/1.0 (+https://sr.ht/~mtmn/corpus)" }
  result <- try $ withTimeout apiTimeout "Cover Art Archive lookup" $ fetch url
    { method: GET, headers }
  case result of
    Right fr | fr.status == 200 -> do
      json <- fromJson fr.json
      pure $ do
        obj <- toObject json
        images <- Object.lookup "images" obj >>= toArray
        let
          isFront img = fromMaybe false $ toObject img >>= Object.lookup "front"
            >>= toBoolean
          isBack img = fromMaybe false $ toObject img >>= Object.lookup "back"
            >>= toBoolean
          getThumb key img = do
            thumbs <- toObject img >>= Object.lookup "thumbnails" >>= toObject
            Object.lookup key thumbs >>= toString
          pickFromImage img =
            getThumb "500" img <|> getThumb "large" img <|> getThumb "250" img
              <|> getThumb "small" img
        (find isFront images >>= pickFromImage)
          <|> (find isBack images >>= pickFromImage)
          <|> (images !! 0 >>= pickFromImage)
    _ ->
      pure Nothing

-- | Find a Last.fm album cover URL when the service is configured.
fetchLastfmCoverUrl :: UserConfig -> String -> String -> Aff (Maybe String)
fetchLastfmCoverUrl cfg artist release = case cfg.lastfmApiKey of
  Nothing ->
    pure Nothing
  Just k -> do
    let
      searchUrl =
        "https://ws.audioscrobbler.com/2.0/?method=album.getinfo&artist="
          <> (fromMaybe "" $ encodeURIComponent artist)
          <> "&album="
          <> (fromMaybe "" $ encodeURIComponent release)
          <> "&format=json&api_key="
          <> k
    Log.info $ "Searching Last.fm for: " <> artist <> " - " <> release
    let headers = { "User-Agent": "corpus/1.0 (+https://sr.ht/~mtmn/corpus)" }
    result <- try $ withTimeout apiTimeout "Last.fm cover lookup" $ fetch
      searchUrl
      { method: GET, headers }
    case result of
      Right fr | fr.status == 200 -> do
        json <- fromJson fr.json
        pure $ do
          obj <- toObject json
          album <- Object.lookup "album" obj >>= toObject
          images <- Object.lookup "image" album >>= toArray
          imgObj <- images !! 2 >>= toObject
          u <- Object.lookup "#text" imgObj >>= toString
          if u == "" then Nothing else Just u
      _ ->
        pure Nothing

-- | Find a Discogs release cover URL when the service is configured.
fetchDiscogsCoverUrl :: UserConfig -> String -> String -> Aff (Maybe String)
fetchDiscogsCoverUrl cfg artist release = case cfg.discogsToken of
  Nothing ->
    pure Nothing
  Just t -> do
    let
      queryStr = artist <> " " <> release
      searchUrl = "https://api.discogs.com/database/search?q="
        <> (fromMaybe "" $ encodeURIComponent queryStr)
        <> "&type=release&per_page=1"
    Log.info $ "Searching Discogs for: " <> queryStr
    result <- try $ withTimeout apiTimeout "Discogs cover lookup" $ fetch
      searchUrl
      { method: GET
      , headers:
          { "User-Agent": "corpus/1.0 (+https://sr.ht/~mtmn/corpus)"
          , "Authorization": "Discogs token=" <> t
          }
      }
    case result of
      Right fr | fr.status == 200 -> do
        json <- fromJson fr.json
        pure $ do
          obj <- toObject json
          results <- Object.lookup "results" obj >>= toArray
          firstResult <- results !! 0 >>= toObject
          Object.lookup "cover_image" firstResult >>= toString
      _ ->
        pure Nothing

-- | List cover sources in cache and fallback order for a release.
coverSources :: String -> String -> String -> UserConfig -> Array CoverSource
coverSources mbid artist release cfg =
  let
    safeArtist = sanitizeKey artist
    safeRelease = sanitizeKey release
    caaSource =
      if mbid == "" then []
      else
        [ { name: "caa"
          , s3Key: "covers/caa/" <> sanitizeKey mbid <> ".avif"
          , findUrl: fetchCaaCoverUrl mbid
          }
        ]
  in
    caaSource <>
      [ { name: "discogs"
        , s3Key: "covers/discogs/" <> safeArtist <> "-" <> safeRelease <>
            ".avif"
        , findUrl:
            if artist == "" || release == "" then pure Nothing
            else fetchDiscogsCoverUrl cfg artist release
        }
      , { name: "lastfm"
        , s3Key: "covers/lastfm/" <> safeArtist <> "-" <> safeRelease <> ".avif"
        , findUrl:
            if artist == "" || release == "" then pure Nothing
            else fetchLastfmCoverUrl cfg artist release
        }
      ]

-- | Serve a cached cover or redirect to an upstream source and populate S3.
serveCover
  :: (Response -> Effect Unit)
  -> UserConfig
  -> String
  -> URL
  -> Response
  -> Aff Unit
serveCover serveNotFound cfg slug url res = do
  let
    mbid = fromMaybe "" (getQueryParam "mbid" url)
    artist = fromMaybe "" (getQueryParam "artist" url)
    release = fromMaybe "" (getQueryParam "release" url)
    s3cfg = s3ConfigFromUser cfg
    cacheEnabled = cfg.coverCacheEnabled && isJust s3cfg.bucket

  served <- foldM (trySource s3cfg cacheEnabled) false
    (coverSources mbid artist release cfg)
  unless served $ liftEffect $ serveNotFound res

  where
  trySource _ _ true _ = pure true
  trySource s3cfg canCache false { name, s3Key, findUrl } = do
    cached <- checkS3 canCache s3cfg s3Key
    if cached then do
      Log.info $ "Serving " <> name <> " cover from cache: " <> s3Key
      liftEffect $ Metrics.incCoverRequest slug name "s3_hit"
      presigned <- try $ getPresignedUrl s3cfg s3Key
      case presigned of
        Right presignedUrl -> do
          serveRedirect presignedUrl Nothing res
          pure true
        Left err -> do
          Log.warn $ "Failed to sign cached cover " <> s3Key <> ": " <>
            Exception.message err
          tryUpstream false
    else do
      tryUpstream canCache

    where
    tryUpstream shouldCache = do
      found <- try findUrl
      case found of
        Left err -> do
          Log.warn $ "Cover lookup failed for " <> name <> ": " <>
            Exception.message err
          pure false
        Right Nothing ->
          pure false
        Right (Just urlStr) -> do
          serveRedirect urlStr (Just "public, max-age=3600") res
          liftEffect $ Metrics.incCoverRequest slug name "fetch"
          when shouldCache $ startCacheFill s3cfg urlStr s3Key
          pure true

  checkS3 canCache s3cfg s3Key
    | not canCache = pure false
    | otherwise = do
        result <- try $ existsInS3 s3cfg s3Key
        pure $ case result of
          Right b -> b
          Left _ -> false

  serveRedirect redirectUrl mCacheControl response =
    liftEffect $ do
      setStatusCode 302 response
      setHeader "Location" redirectUrl (toOutgoingMessage response)
      for_ mCacheControl \cacheControl ->
        setHeader "Cache-Control" cacheControl (toOutgoingMessage response)
      end (toWriteable (toOutgoingMessage response))

  -- Only one request may populate a given S3 object at a time. Concurrent
  -- misses still redirect immediately; later requests use the cached object.
  startCacheFill s3cfg urlStr s3Key = do
    let jobKey = cacheJobKey (fromMaybe "" s3cfg.bucket) s3Key
    started <- liftEffect $ tryStartCacheFill jobKey
    when started $ void $ forkAff do
      _ <- try do
        let
          headers = { "User-Agent": "corpus/1.0 (+https://sr.ht/~mtmn/corpus)" }
        fetchResult <- try $ withTimeout imageTimeout "Cover image request" $
          fetch urlStr { method: GET, headers }
        case fetchResult of
          Right fr | fr.status == 200 -> do
            let
              contentType = Map.lookup (CaseInsensitiveString "content-type")
                fr.headers
              isAvif = case contentType of
                Just ct | ct == "image/avif" -> true
                _ -> false
            Log.info $ "Caching image: " <> urlStr
            bodyResult <- try $ withTimeout imageTimeout "Cover image download"
              fr.arrayBuffer
            case bodyResult of
              Left err -> Log.error $ "Cover image download failed for "
                <> urlStr
                <> ": "
                <> Exception.message err
              Right ab -> do
                bytes <- liftEffect $ arrayBufferByteLength ab
                if bytes > maxCoverBytes then
                  Log.warn $ "Skipping oversized cover (" <> show bytes
                    <> " bytes): "
                    <> urlStr
                else do
                  avifAb <- if isAvif then pure ab else convertToAvif ab
                  avifBuf <- liftEffect $ fromArrayBuffer avifAb
                  uploadResult <- try $ uploadToS3 s3cfg s3Key avifBuf
                    "image/avif"
                  case uploadResult of
                    Right _ -> Log.info $ "Uploaded " <> s3Key
                    Left err -> Log.error $ "Failed to upload " <> s3Key <> ": "
                      <> Exception.message err
          Right fr ->
            Log.warn $ "Background fetch failed for " <> urlStr
              <> " with status "
              <> show fr.status
          Left err ->
            Log.error $ "Background fetch error for " <> urlStr <> ": " <>
              Exception.message err
      liftEffect $ finishCacheFill jobKey
