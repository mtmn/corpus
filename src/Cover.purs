module Cover
  ( CoverSource
  , sanitizeKey
  , fetchLastfmCoverUrl
  , fetchDiscogsCoverUrl
  , coverSources
  , serveCover
  ) where

import Prelude

import Config (UserConfig, s3ConfigFromUser)
import S3 (existsInS3, getS3Url, uploadToS3)
import Data.Array ((!!))
import Data.Either (Either(..))
import Data.Foldable (foldM)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String.CaseInsensitive (CaseInsensitiveString(..))
import Data.String.Regex (replace, parseFlags)
import Data.String.Regex.Unsafe (unsafeRegex)
import Effect (Effect)
import Effect.Aff (Aff, forkAff, try)
import Effect.Class (liftEffect)
import Effect.Exception as Exception
import Fetch (fetch, Method(GET))
import Fetch.Argonaut.Json (fromJson)
import Foreign.Object as Object
import Data.Argonaut.Core (toArray, toObject, toString)
import Image (convertToAvif)
import JSURI (encodeURIComponent)
import Log as Log
import Metrics as Metrics
import Node.Buffer (fromArrayBuffer)
import Node.HTTP.OutgoingMessage (setHeader, toWriteable)
import Node.HTTP.ServerResponse (setStatusCode, toOutgoingMessage)
import Node.HTTP.Types (ServerResponse)
import Node.Stream (end)
import Web.URL (URL)
import Web.URL as URL
import Web.URL.URLSearchParams as URLSearchParams

type Response = ServerResponse

type CoverSource =
  { name :: String
  , s3Key :: String
  , findUrl :: Aff (Maybe String)
  }

sanitizeKey :: String -> String
sanitizeKey = replace re1 "_" >>> replace re2 "_"
  where
  re1 = unsafeRegex "[^a-z0-9.-]" (parseFlags "gi")
  re2 = unsafeRegex "_{2,}" (parseFlags "g")

getQueryParam :: String -> URL -> Maybe String
getQueryParam key url = URLSearchParams.get key (URL.searchParams url)

fetchLastfmCoverUrl :: UserConfig -> String -> String -> Aff (Maybe String)
fetchLastfmCoverUrl cfg artist release = case cfg.lastfmApiKey of
  Nothing ->
    pure Nothing
  Just k -> do
    let
      searchUrl = "https://ws.audioscrobbler.com/2.0/?method=album.getinfo&artist="
        <> (fromMaybe "" $ encodeURIComponent artist)
        <> "&album="
        <> (fromMaybe "" $ encodeURIComponent release)
        <> "&format=json&api_key="
        <> k
    Log.info $ "Searching Last.fm for: " <> artist <> " - " <> release
    result <- try $ fetch searchUrl { method: GET }
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
    result <- try $ fetch searchUrl { method: GET, headers: { "User-Agent": "corpus/1.0 (+https://github.com/mtmn/corpus)", "Authorization": "Discogs token=" <> t } }
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

coverSources :: String -> String -> String -> Maybe String -> UserConfig -> Array CoverSource
coverSources mbid artist release mVariant cfg =
  let
    safeArtist = sanitizeKey artist
    safeRelease = sanitizeKey release
    variant = fromMaybe "front-500" mVariant
    caaSource =
      if mbid == "" then []
      else
        [ { name: "caa"
          , s3Key: "covers/caa/" <> sanitizeKey mbid <> (if variant == "front-500" then "" else "-" <> variant) <> ".avif"
          , findUrl: pure $ Just $ "https://coverartarchive.org/release/" <> mbid <> "/" <> variant
          }
        ]
  in
    caaSource <>
      [ { name: "lastfm"
        , s3Key: "covers/lastfm/" <> safeArtist <> "-" <> safeRelease <> ".avif"
        , findUrl:
            if artist == "" || release == "" then pure Nothing
            else fetchLastfmCoverUrl cfg artist release
        }
      , { name: "discogs"
        , s3Key: "covers/discogs/" <> safeArtist <> "-" <> safeRelease <> ".avif"
        , findUrl:
            if artist == "" || release == "" then pure Nothing
            else fetchDiscogsCoverUrl cfg artist release
        }
      ]

serveCover :: (Response -> Effect Unit) -> UserConfig -> String -> URL -> Response -> Aff Unit
serveCover serveNotFound cfg slug url res = do
  let
    mbid = fromMaybe "" (getQueryParam "mbid" url)
    artist = fromMaybe "" (getQueryParam "artist" url)
    release = fromMaybe "" (getQueryParam "release" url)
    variant = getQueryParam "variant" url
    s3cfg = s3ConfigFromUser cfg

  served <- foldM (trySource s3cfg) false (coverSources mbid artist release variant cfg)
  unless served $ liftEffect $ serveNotFound res

  where
  trySource _ true _ = pure true
  trySource s3cfg false { name, s3Key, findUrl } = do
    cached <- checkS3 s3cfg s3Key
    if cached then do
      Log.info $ "Serving " <> name <> " cover from S3: " <> s3Key
      liftEffect $ Metrics.incCoverRequest slug name "s3_hit"
      liftEffect $ serveS3Redirect s3cfg s3Key res
      pure true
    else do
      mUrl <- findUrl
      case mUrl of
        Nothing ->
          pure false
        Just urlStr -> do
          redirectAndCache s3cfg urlStr s3Key res
          liftEffect $ Metrics.incCoverRequest slug name "fetch"
          pure true

  checkS3 s3cfg s3Key
    | not cfg.coverCacheEnabled = pure false
    | otherwise = do
        result <- try $ existsInS3 s3cfg s3Key
        pure $ case result of
          Right b -> b
          Left _ -> false

  serveS3Redirect s3cfg s3Key response = do
    setStatusCode 302 response
    setHeader "Location" (getS3Url s3cfg s3Key) (toOutgoingMessage response)
    end (toWriteable (toOutgoingMessage response))

  -- Redirect the client immediately to the upstream URL, then fetch+convert+cache in background.
  -- This avoids blocking the response on AVIF conversion (which can take hundreds of ms).
  redirectAndCache s3cfg urlStr s3Key response = do
    liftEffect $ do
      setStatusCode 302 response
      setHeader "Location" urlStr (toOutgoingMessage response)
      setHeader "Cache-Control" "public, max-age=3600" (toOutgoingMessage response)
      end (toWriteable (toOutgoingMessage response))
    when cfg.coverCacheEnabled $ void $ forkAff do
      let headers = { "User-Agent": "corpus/1.0 (+https://github.com/mtmn/corpus)" }
      fetchResult <- try $ fetch urlStr { method: GET, headers }
      case fetchResult of
        Right fr | fr.status == 200 -> do
          let
            contentType = Map.lookup (CaseInsensitiveString "content-type") fr.headers
            isAvif = case contentType of
              Just ct | ct == "image/avif" -> true
              _ -> false
          Log.info $ "Caching image: " <> urlStr
          ab <- fr.arrayBuffer
          avifAb <- if isAvif then pure ab else convertToAvif ab
          avifBuf <- liftEffect $ fromArrayBuffer avifAb
          uploadResult <- try $ uploadToS3 s3cfg s3Key avifBuf "image/avif"
          case uploadResult of
            Right _ -> Log.info $ "Cached to S3: " <> s3Key
            Left err -> Log.error $ "S3 upload FAILED for " <> s3Key <> ": " <> Exception.message err
        Right fr ->
          Log.warn $ "Background fetch failed for " <> urlStr <> " with status " <> show fr.status
        Left err ->
          Log.error $ "Background fetch error for " <> urlStr <> ": " <> Exception.message err
