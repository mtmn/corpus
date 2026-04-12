module Main where

import Prelude

import Effect (Effect)
import Effect.Class (liftEffect)
import Log as Log
import Node.HTTP (createServer)
import Node.HTTPS as HTTPS
import Node.HTTP.Server as Server
import Node.EventEmitter (on_, EventHandle(..))
import Effect.Uncurried (mkEffectFn1)
import Node.HTTP.ClientRequest as Client
import Node.HTTP.IncomingMessage as IM
import Node.HTTP.Types (ServerResponse, IncomingMessage, IMServer)
import Node.HTTP.ServerResponse (setStatusCode, toOutgoingMessage)
import Node.HTTP.OutgoingMessage (setHeader, toWriteable)
import Node.Stream (end, write, writeString)
import Node.Stream.Aff (readableToStringUtf8)
import Node.Encoding (Encoding(UTF8))
import Node.Net.Server (listenTcp, listeningH)
import Node.Buffer (fromArrayBuffer)
import Data.Either (Either(..))
import Effect.Exception as Exception
import Effect.Aff (Aff, launchAff_, makeAff, nonCanceler, try, delay, forkAff)
import Effect.Ref as Ref
import Effect.Ref (Ref)
import Unsafe.Coerce (unsafeCoerce)
import Node.FS.Aff as FSA
import Node.Process (getEnv)
import Fetch (fetch, Method(GET), lookup)
import Fetch.Argonaut.Json (fromJson)
import Data.Maybe (Maybe(..), fromMaybe)
import JSURI (encodeURIComponent)
import Foreign.Object as Object
import Data.Argonaut (decodeJson, encodeJson, parseJson)
import Data.Argonaut.Core (toObject, toArray, toString, stringify)
import Data.Array ((!!), length, uncons)
import Data.Tuple (Tuple(..))
import Data.Foldable (for_)
import Db (Connection, connect, initDb, upsertScrobble, getScrobbles, checkExists, run, initReleaseMetadata, getUnenrichedMbids, getEmptyGenreMbids, getArtistReleaseByMbid, upsertReleaseMetadata, touchGenreCheckedAt, getStats, ping)
import Types (Listen(..), ListenBrainzResponse(..), Payload(..), TrackMetadata(..))
import Control.Monad.Rec.Class (forever)
import Data.Time.Duration (Milliseconds(..))
import Data.Int (fromString)
import Data.String (Pattern(..))
import Data.String.Common (split) as String
import Data.String.Regex (replace, parseFlags)
import Data.String.Regex.Unsafe (unsafeRegex)
import S3 (existsInS3, uploadToS3, getS3Url)
import Web.URL (URL)
import Web.URL as URL
import Web.URL.URLSearchParams as URLSearchParams

-- Types
type Request = IncomingMessage IMServer
type Response = ServerResponse

listenBrainzUrl :: String -> String
listenBrainzUrl username = "https://api.listenbrainz.org/1/user/" <> username <> "/listens"

fetchListenBrainzData :: String -> Int -> Aff String
fetchListenBrainzData username count = makeAff \callback -> do
  let url = listenBrainzUrl username <> "?count=" <> show count
  req <- HTTPS.get url

  req # on_ Client.responseH \res -> do
    launchAff_ do
      body <- readableToStringUtf8 (IM.toReadable res)
      liftEffect $ callback (Right body)

  let errorH = EventHandle "error" mkEffectFn1
  on_ errorH
    ( \err -> do
        Log.error $ "ListenBrainz fetch error: " <> Exception.message err
        callback (Left err)
    )
    (unsafeCoerce req)

  pure nonCanceler

fetchListenBrainzDataBefore :: String -> Int -> Aff String
fetchListenBrainzDataBefore username maxTs = makeAff \callback -> do
  let url = listenBrainzUrl username <> "?count=100&max_ts=" <> show maxTs
  req <- HTTPS.get url

  req # on_ Client.responseH \res -> do
    launchAff_ do
      body <- readableToStringUtf8 (IM.toReadable res)
      liftEffect $ callback (Right body)

  let errorH = EventHandle "error" mkEffectFn1
  on_ errorH
    ( \err -> do
        Log.error $ "ListenBrainz fetch error: " <> Exception.message err
        callback (Left err)
    )
    (unsafeCoerce req)

  pure nonCanceler

syncData :: Connection -> String -> Ref Boolean -> Aff Unit
syncData _ username _ | username == "" = pure unit
syncData conn username isSyncing = do
  forever do
    liftEffect $ Ref.write true isSyncing
    void $ performFullSync
    liftEffect $ Ref.write false isSyncing
    delay (Milliseconds 60000.0)

  where
  performFullSync = do
    result <- try $ fetchListenBrainzData username 100
    case result of
      Right body -> do
        case parseJson body >>= decodeJson of
          Left err -> Log.error $ "Sync parse error: " <> show err
          Right (ListenBrainzResponse { payload: Payload { listens } }) -> do
            run conn "BEGIN TRANSACTION" []
            Tuple added (Tuple minTs hitExisting) <- processListens listens
            run conn "COMMIT" []
            if hitExisting || length listens == 0 then do
              when (added > 0) $ Log.info $ "Sync complete. Added " <> show added <> " new scrobbles."
            else do
              total <- paginateUntilDone minTs added
              Log.info $ "Sync complete. Added " <> show total <> " new scrobbles."
      Left err -> Log.error $ "Sync fetch error: " <> Exception.message err

  paginateUntilDone minTs acc = case minTs of
    Nothing -> pure acc
    Just ts -> do
      result <- try $ fetchListenBrainzDataBefore username ts
      case result of
        Right body -> do
          case parseJson body >>= decodeJson of
            Left err -> do
              Log.error $ "Sync parse error: " <> show err
              pure acc
            Right (ListenBrainzResponse { payload: Payload { listens } }) -> do
              run conn "BEGIN TRANSACTION" []
              Tuple added (Tuple newMinTs hitExisting) <- processListens listens
              run conn "COMMIT" []
              if hitExisting || length listens == 0 then do
                pure (acc + added)
              else do
                paginateUntilDone newMinTs (acc + added)
        Left err -> do
          Log.error $ "Sync fetch error: " <> Exception.message err
          pure acc

  processListens listens = do
    syncRecursive 0 Nothing listens

  syncRecursive acc minTs listens = case uncons listens of
    Nothing -> pure $ Tuple acc (Tuple minTs false)
    Just { head: l@(Listen { listenedAt: Just ts, trackMetadata: (TrackMetadata _) }), tail } -> do
      exists <- checkExists conn ts
      if exists then do
        pure $ Tuple acc (Tuple minTs true)
      else do
        upsertScrobble conn l
        syncRecursive (acc + 1) (Just ts) tail
    Just { head: _, tail } -> do
      Log.warn "Skipping scrobble without timestamp"
      syncRecursive acc minTs tail

indexHtml :: String
indexHtml =
  """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>scrobbler</title>
    <link rel="icon" type="image/x-icon" href="/favicon.ico">
    <link rel="icon" type="image/png" href="/favicon.png">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Intel+One+Mono:wght@300;400;500;700&display=swap" rel="stylesheet">
    <style>
        body {
            font-family: 'Intel One Mono', 'Courier New', 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            background: #000000;
            color: #ffffff;
            margin: 0;
            padding: 20px;
            line-height: 1.6;
        }

        ::selection {
            background: #50447f;
            color: #ffffff;
        }
        
        .container {
            max-width: 800px;
            margin: 0 auto;
        }
        
        h1 {
            color: #ffffff;
            margin-bottom: 20px;
            font-size: 24px;
            border-bottom: 2px solid #50447f;
            display: inline-block;
            padding-bottom: 5px;
        }
        
        ul {
            list-style: none;
            padding: 0;
            margin: 0 0 20px 0;
        }
        
        li {
            background: #521e40;
            border: 1px solid #50447f;
            border-radius: 4px;
            padding: 15px;
            margin-bottom: 10px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            box-shadow: 4px 4px 0px #50447f;
        }
        
        li.success {
            background: #521e40;
            border-color: #50447f;
        }
        
        .track-info {
            flex: 1;
        }
        
        .track-name {
            font-weight: bold;
            font-size: 16px;
            color: #ffffff;
        }
        
        .track-artist {
            font-size: 14px;
            color: #a0c0d0;
            margin-top: 1px;
        }
        
        .track-time {
            font-size: 12px;
            color: #9fbfe7;
            margin-top: 2px;
        }

        .album-link {
            color: #9fbfe7;
            text-decoration: underline;
        }

        .album-link:hover {
            color: #ffffff;
        }
        
        .status {
            color: #b9d0aa;
            font-weight: bold;
        }

        .track-cover {
            width: 60px;
            height: 60px;
            border-radius: 4px;
            object-fit: cover;
            background: rgba(255, 255, 255, 0.05);
            transition: transform 0.2s ease-in-out;
            cursor: pointer;
        }
        
        .track-cover.zoomed {
            transform: scale(5.0);
            z-index: 10;
            position: relative;
            box-shadow: 0 8px 16px rgba(0, 0, 0, 0.5);
        }
        
        .loading {
            padding: 20px;
            color: #9fbfe7;
            text-align: center;
        }
        
        .error {
            padding: 20px;
            color: #eca28f;
            text-align: center;
        }
        
        .small {
            font-size: 12px;
            color: #9fbfe7;
            margin-top: 20px;
        }
        
        .small a {
            color: #a0c0d0;
            text-decoration: none;
        }
        
        .small a:hover {
            color: #ffffff;
            text-decoration: underline;
        }
        
        .refresh-btn {
            background: none;
            border: none;
            color: #a0c0d0;
            cursor: pointer;
            font-size: 12px;
            text-decoration: underline;
        }
        
        .refresh-btn:hover {
            color: #ffffff;
        }
        
        .playing-indicator {
            display: inline-block;
            width: 8px;
            height: 8px;
            background: #b9d0aa;
            border-radius: 50%;
            margin-right: 8px;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.3; }
            100% { opacity: 1; }
        }

        .pagination {
            display: flex;
            justify-content: center;
            gap: 20px;
            margin-top: 20px;
        }

        .page-btn {
            background: #521e40;
            border: 1px solid #50447f;
            color: #ffffff;
            padding: 8px 16px;
            border-radius: 4px;
            cursor: pointer;
            font-family: inherit;
            box-shadow: 2px 2px 0px #50447f;
        }

        .page-btn:hover {
            background: #50447f;
        }

        .page-btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }

        .page-indicator {
            display: flex;
            align-items: center;
            font-size: 14px;
            color: #9fbfe7;
        }

        .tabs {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
        }

        .tab-btn {
            background: none;
            border: 1px solid #50447f;
            color: #9fbfe7;
            padding: 6px 14px;
            border-radius: 4px;
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
            text-decoration: none;
            display: inline-block;
        }

        .tab-btn.active {
            background: #521e40;
            color: #ffffff;
            box-shadow: 2px 2px 0px #50447f;
        }

        .tab-btn:hover {
            color: #ffffff;
        }

        .stats-section {
            margin-bottom: 30px;
        }

        .stats-section h2 {
            font-size: 11px;
            color: #9fbfe7;
            text-transform: uppercase;
            letter-spacing: 3px;
            margin: 0 0 10px 0;
            border-bottom: 1px solid #50447f;
            padding-bottom: 5px;
        }

        .stat-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 5px 8px;
            margin-bottom: 3px;
            position: relative;
            border-radius: 2px;
            overflow: hidden;
            font-size: 13px;
        }

        .stat-bar {
            position: absolute;
            left: 0;
            top: 0;
            height: 100%;
            background: #521e40;
            border-right: 1px solid #50447f;
            z-index: 0;
        }

        .stat-name {
            position: relative;
            z-index: 1;
            color: #ffffff;
            flex: 1;
            padding-right: 10px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .stat-count {
            position: relative;
            z-index: 1;
            color: #9fbfe7;
            font-size: 12px;
            flex-shrink: 0;
        }

        .stats-empty {
            color: #9fbfe7;
            font-size: 13px;
            padding: 10px 0;
        }

        .cover-wrapper {
            display: flex;
            flex-direction: column;
            align-items: center;
            margin-left: 15px;
            gap: 4px;
            flex-shrink: 0;
            position: relative;
        }

        .genre-tag {
            position: absolute;
            top: 100%;
            left: 50%;
            transform: translateX(-50%);
            font-size: 10px;
            color: #9fbfe7;
            text-align: center;
            max-width: 60px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            opacity: 0.8;
        }

        .genre-tag:hover {
            max-width: none;
            overflow: visible;
            text-overflow: clip;
            background: #521e40;
            border: 1px solid #50447f;
            border-radius: 4px;
            padding: 2px 6px;
            z-index: 100;
            opacity: 1;
        }

        .stat-row {
            cursor: pointer;
        }

        .stat-row:hover .stat-name {
            color: #a0c0d0;
        }

        .filter-banner {
            display: flex;
            align-items: center;
            gap: 10px;
            background: #521e40;
            border: 1px solid #50447f;
            border-radius: 4px;
            padding: 8px 12px;
            margin-bottom: 12px;
            font-size: 13px;
            color: #9fbfe7;
        }

        .filter-label {
            flex: 1;
        }

        .filter-label strong {
            color: #ffffff;
        }

        .filter-clear {
            background: none;
            border: 1px solid #50447f;
            color: #9fbfe7;
            padding: 2px 8px;
            border-radius: 3px;
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
        }

        .filter-clear:hover {
            color: #ffffff;
            border-color: #ffffff;
        }

        .show-all-btn {
            background: none;
            border: none;
            color: #9fbfe7;
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
            padding: 4px 0;
            text-decoration: underline;
        }

        .show-all-btn:hover {
            color: #ffffff;
        }
    </style>
</head>
<body>
    <div id="app"></div>
    <script src="/client.js"></script>
</body>
</html>"""

-- Request handler
handleRequest :: Connection -> Ref Boolean -> Request -> Response -> Effect Unit
handleRequest db isSyncing req res = do
  let method = IM.method req
  let rawUrl = IM.url req
  case URL.fromRelative rawUrl "http://localhost" of
    Nothing -> serveNotFound res
    Just url -> do
      let path = URL.pathname url
      Log.info $ method <> " " <> rawUrl

      case path of
        "/" -> serveIndex res
        "/healthz" -> serveHealthz db isSyncing res
        "/proxy" -> serveProxy db isSyncing url res
        "/cover" -> serveCover isSyncing url res
        "/stats" -> serveStats db isSyncing res
        "/client.js" -> serveClientJs res
        "/favicon.ico" -> serveAsset "image/x-icon" "assets/favicon.ico" res
        "/favicon.png" -> serveAsset "image/png" "assets/favicon.png" res
        _ -> do
          Log.warn $ "Path not found: " <> path
          serveNotFound res

serveIndex :: Response -> Effect Unit
serveIndex res = do
  setHeader "Content-Type" "text/html" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  setStatusCode 200 res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 indexHtml
  end w

serveClientJs :: Response -> Effect Unit
serveClientJs res = do
  setHeader "Content-Type" "application/javascript" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  launchAff_ do
    result <- try $ FSA.readTextFile UTF8 "client.js"
    liftEffect $ case result of
      Right content -> do
        setStatusCode 200 res
        let w = toWriteable (toOutgoingMessage res)
        void $ writeString w UTF8 content
        end w
      Left err -> do
        Log.error $ "Failed to read client.js: " <> Exception.message err
        serveNotFound res

getQueryParam :: String -> URL -> Maybe String
getQueryParam name url = URLSearchParams.get name (URL.searchParams url)

sanitizeKey :: String -> String
sanitizeKey str =
  let
    re1 = unsafeRegex "[^a-z0-9.-]" (parseFlags "gi")
    re2 = unsafeRegex "_{2,}" (parseFlags "g")
  in
    replace re2 "_" (replace re1 "_" str)

serveCover :: Ref Boolean -> URL -> Response -> Effect Unit
serveCover isSyncing url res = do
  launchAff_ do
    yieldToSync isSyncing
    let mbid = fromMaybe "" (getQueryParam "mbid" url)
    let artistStr = fromMaybe "" (getQueryParam "artist" url)
    let releaseStr = fromMaybe "" (getQueryParam "release" url)

    -- Strategy:
    -- 1. If MBID exists, try CAA (S3 first, then Fetch)
    -- 2. If CAA fails or no MBID, try Last.fm (S3 first, then Fetch)
    -- 3. If Last.fm fails, try Discogs (S3 first, then Fetch)

    if mbid /= "" then do
      let safeMbid = sanitizeKey mbid
      let s3Key = "covers/caa/" <> safeMbid <> ".jpg"
      cached <- checkS3 s3Key
      if cached then do
        Log.info $ "Serving CAA cover from S3: " <> s3Key
        serveS3 s3Key res
      else do
        Log.info $ "Fetching CAA cover: " <> mbid
        let caaUrl = "https://coverartarchive.org/release/" <> mbid <> "/front-250"
        success <- tryProxyAndCache caaUrl s3Key res
        unless success $ do
          Log.info $ "CAA cover not found for " <> mbid <> ", falling back to Last.fm"
          tryLastfm artistStr releaseStr res
    else do
      Log.info $ "No MBID provided, trying Last.fm for: " <> artistStr <> " - " <> releaseStr
      tryLastfm artistStr releaseStr res

  where
  checkS3 s3Key = do
    result <- try $ existsInS3 s3Key
    pure $ case result of
      Right b -> b
      Left _ -> false

  serveS3 s3Key response = liftEffect $ do
    setStatusCode 302 response
    setHeader "Location" (getS3Url s3Key) (toOutgoingMessage response)
    end (toWriteable (toOutgoingMessage response))

  tryProxyAndCache urlStr s3Key response = do
    fetchResult <- try $ fetch urlStr { method: GET }
    case fetchResult of
      Right fr | fr.status == 200 -> do
        Log.info $ "Proxying and caching image: " <> urlStr
        let contentType = fromMaybe "image/jpeg" $ lookup "content-type" fr.headers
        buf <- fr.arrayBuffer
        liftEffect $ do
          setStatusCode fr.status response
          setHeader "Content-Type" contentType (toOutgoingMessage response)
          setHeader "Cache-Control" "public, max-age=86400" (toOutgoingMessage response)
          let writer = toWriteable (toOutgoingMessage response)
          nativeBuf <- fromArrayBuffer buf
          void $ write writer nativeBuf
          end writer

        -- Cache to S3 in background
        void $ forkAff $ do
          uploadResult <- try $ uploadToS3 s3Key (unsafeCoerce buf) contentType
          case uploadResult of
            Right _ -> Log.info $ "Cached to S3: " <> s3Key
            Left err -> Log.error $ "S3 upload failed: " <> Exception.message err
        pure true
      _ -> pure false

  tryLastfm artist release response
    | artist == "" || release == "" = do
        Log.warn $ "Missing artist or release for Last.fm fallback"
        liftEffect $ serveNotFound response
    | otherwise = do
        let safeArtist = sanitizeKey artist
        let safeRelease = sanitizeKey release
        let s3Key = "covers/lastfm/" <> safeArtist <> "-" <> safeRelease <> ".jpg"
        cached <- checkS3 s3Key
        if cached then do
          Log.info $ "Serving Last.fm cover from S3: " <> s3Key
          serveS3 s3Key response
        else do
          env <- liftEffect getEnv
          case Object.lookup "LASTFM_API_KEY" env of
            Nothing -> do
              Log.warn "LASTFM_API_KEY missing, falling back to Discogs"
              tryDiscogs artist release response
            Just k -> do
              let searchUrl = "https://ws.audioscrobbler.com/2.0/?method=album.getinfo&api_key=" <> k <> "&artist=" <> (fromMaybe "" $ encodeURIComponent artist) <> "&album=" <> (fromMaybe "" $ encodeURIComponent release) <> "&format=json"
              Log.info $ "Searching Last.fm for: " <> artist <> " - " <> release
              result <- try $ fetch searchUrl { method: GET }
              case result of
                Right fetchRes | fetchRes.status == 200 -> do
                  json <- fromJson fetchRes.json
                  let
                    coverUrl = do
                      obj <- toObject json
                      album <- Object.lookup "album" obj >>= toObject
                      images <- Object.lookup "image" album >>= toArray
                      imageObj <- images !! 2 >>= toObject
                      u <- Object.lookup "#text" imageObj >>= toString
                      if u == "" then Nothing else Just u
                  case coverUrl of
                    Just urlStr -> do
                      Log.info $ "Found Last.fm cover: " <> urlStr
                      success <- tryProxyAndCache urlStr s3Key response
                      unless success $ do
                        Log.info "Last.fm image proxy failed, falling back to Discogs"
                        tryDiscogs artist release response
                    Nothing -> do
                      Log.info "No cover found on Last.fm, falling back to Discogs"
                      tryDiscogs artist release response
                _ -> do
                  Log.info "Last.fm API request failed, falling back to Discogs"
                  tryDiscogs artist release response

  tryDiscogs artist release response = do
    let safeArtist = sanitizeKey artist
    let safeRelease = sanitizeKey release
    let s3Key = "covers/discogs/" <> safeArtist <> "-" <> safeRelease <> ".jpg"
    cached <- checkS3 s3Key
    if cached then do
      Log.info $ "Serving Discogs cover from S3: " <> s3Key
      serveS3 s3Key response
    else do
      env <- liftEffect getEnv
      case Object.lookup "DISCOGS_TOKEN" env of
        Nothing -> do
          Log.warn "DISCOGS_TOKEN missing, cannot fallback further"
          liftEffect $ serveNotFound response
        Just t -> do
          let queryStr = artist <> " " <> release
          let searchUrl = "https://api.discogs.com/database/search?q=" <> (fromMaybe "" $ encodeURIComponent queryStr) <> "&type=release&per_page=1&token=" <> t
          Log.info $ "Searching Discogs for: " <> queryStr
          result <- try $ fetch searchUrl { method: GET, headers: { "User-Agent": "ScrobblerPureScript/1.0" } }
          case result of
            Right fetchRes | fetchRes.status == 200 -> do
              json <- fromJson fetchRes.json
              let
                coverUrl = do
                  obj <- toObject json
                  results <- Object.lookup "results" obj >>= toArray
                  firstResult <- results !! 0 >>= toObject
                  Object.lookup "cover_image" firstResult >>= toString
              case coverUrl of
                Just urlStr -> do
                  Log.info $ "Found Discogs cover: " <> urlStr
                  success <- tryProxyAndCache urlStr s3Key response
                  unless success $ do
                    Log.info "Discogs image proxy failed"
                    liftEffect $ serveNotFound response
                Nothing -> do
                  Log.info "No cover found on Discogs"
                  liftEffect $ serveNotFound response
            _ -> do
              Log.info "Discogs API request failed"
              liftEffect $ serveNotFound response

serveProxy :: Connection -> Ref Boolean -> URL -> Response -> Effect Unit
serveProxy db isSyncing url res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Methods" "GET, POST, OPTIONS" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Headers" "*" (toOutgoingMessage res)

  launchAff_ do
    yieldToSync isSyncing
    let limit = fromMaybe 25 (getQueryParam "limit" url >>= fromString)
    let offset = fromMaybe 0 (getQueryParam "offset" url >>= fromString)
    let
      mFilter = do
        field <- getQueryParam "filterField" url
        value <- getQueryParam "filterValue" url
        pure { field, value }

    listens <- getScrobbles db limit offset mFilter
    let responseBody = stringify $ encodeJson { payload: { listens: listens } }

    liftEffect $ do
      setStatusCode 200 res
      let w = toWriteable (toOutgoingMessage res)
      void $ writeString w UTF8 responseBody
      end w

serveAsset :: String -> String -> Response -> Effect Unit
serveAsset contentType path res = do
  setHeader "Content-Type" contentType (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  launchAff_ do
    result <- try $ FSA.readFile path
    liftEffect $ case result of
      Right buf -> do
        setStatusCode 200 res
        let w = toWriteable (toOutgoingMessage res)
        void $ write w buf
        end w
      Left _ -> serveNotFound res

serveHealthz :: Connection -> Ref Boolean -> Response -> Effect Unit
serveHealthz db isSyncing res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  launchAff_ do
    yieldToSync isSyncing
    result <- try $ ping db
    liftEffect $ do
      let w = toWriteable (toOutgoingMessage res)
      case result of
        Right _ -> do
          setStatusCode 200 res
          void $ writeString w UTF8 """{"status":"ok"}"""
        Left err -> do
          setStatusCode 503 res
          void $ writeString w UTF8 $ """{"status":"error","message":""" <> show (Exception.message err) <> "}"
      end w

serveNotFound :: Response -> Effect Unit
serveNotFound res = do
  setHeader "Content-Type" "text/plain" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  setStatusCode 404 res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 "Not Found"
  end w

serveStats :: Connection -> Ref Boolean -> Response -> Effect Unit
serveStats db isSyncing res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  launchAff_ do
    yieldToSync isSyncing
    stats <- getStats db
    let responseBody = stringify $ encodeJson stats
    liftEffect $ do
      setStatusCode 200 res
      let w = toWriteable (toOutgoingMessage res)
      void $ writeString w UTF8 responseBody
      end w

type MbData = { genre :: Maybe String, label :: Maybe String, year :: Maybe Int }

fetchMusicBrainzRelease :: String -> Aff (Maybe MbData)
fetchMusicBrainzRelease mbid = do
  let url = "https://musicbrainz.org/ws/2/release/" <> mbid <> "?inc=genres+labels+release-groups&fmt=json"
  result <- try $ fetch url { method: GET, headers: { "User-Agent": "Scorpus/1.0 +https://codeberg.org/mtmn/scorpus" } }
  case result of
    Left err -> do
      Log.error $ "MusicBrainz fetch error for " <> mbid <> ": " <> Exception.message err
      pure Nothing
    Right fr | fr.status == 200 -> do
      jsonResult <- try $ fromJson fr.json
      case jsonResult of
        Left err -> do
          Log.error $ "MusicBrainz JSON parse error for " <> mbid <> ": " <> Exception.message err
          pure $ Just { genre: Nothing, label: Nothing, year: Nothing }
        Right json -> do
          let
            genre = do
              obj <- toObject json
              genres <- Object.lookup "genres" obj >>= toArray
              firstGenre <- genres !! 0 >>= toObject
              Object.lookup "name" firstGenre >>= toString
            label = do
              obj <- toObject json
              labelInfo <- Object.lookup "label-info" obj >>= toArray
              firstLabel <- labelInfo !! 0 >>= toObject
              labelObj <- Object.lookup "label" firstLabel >>= toObject
              Object.lookup "name" labelObj >>= toString
            year = do
              obj <- toObject json
              rg <- Object.lookup "release-group" obj >>= toObject
              dateStr <- Object.lookup "first-release-date" rg >>= toString
              case uncons (String.split (Pattern "-") dateStr) of
                Just { head } -> fromString head
                Nothing -> Nothing
          Log.info $ "Enriched " <> mbid <> ": genre=" <> show genre <> " label=" <> show label <> " year=" <> show year

          -- Warn if all fields are empty
          when (genre == Nothing && label == Nothing && year == Nothing)
            $ Log.warn
            $ "All fields empty for " <> mbid <> " - possible parsing issue or missing data"

          pure $ Just { genre, label, year }
    Right fr | fr.status == 404 -> do
      Log.info $ "MusicBrainz 404 for " <> mbid
      pure $ Just { genre: Nothing, label: Nothing, year: Nothing }
    Right fr -> do
      Log.warn $ "MusicBrainz " <> show fr.status <> " for " <> mbid <> ", will retry"
      pure Nothing

fetchLastfmGenre :: String -> String -> Aff (Maybe String)
fetchLastfmGenre artist release = do
  env <- liftEffect getEnv
  case Object.lookup "LASTFM_API_KEY" env of
    Nothing -> do
      Log.warn "LASTFM_API_KEY missing for genre fallback"
      pure Nothing
    Just k -> do
      let searchUrl = "https://ws.audioscrobbler.com/2.0/?method=album.getinfo&api_key=" <> k <> "&artist=" <> (fromMaybe "" $ encodeURIComponent artist) <> "&album=" <> (fromMaybe "" $ encodeURIComponent release) <> "&format=json"
      Log.info $ "Fetching Last.fm genre for: " <> artist <> " - " <> release
      result <- try $ fetch searchUrl { method: GET }
      case result of
        Right fetchRes | fetchRes.status == 200 -> do
          jsonResult <- try $ fromJson fetchRes.json
          case jsonResult of
            Left err -> do
              Log.error $ "Last.fm genre JSON error: " <> Exception.message err
              pure Nothing
            Right json -> do
              let
                genre = do
                  obj <- toObject json
                  album <- Object.lookup "album" obj >>= toObject
                  tags <- Object.lookup "tags" album >>= toObject
                  tagArray <- Object.lookup "tag" tags >>= toArray
                  firstTag <- tagArray !! 0 >>= toObject
                  Object.lookup "name" firstTag >>= toString
              pure genre
        _ -> do
          Log.warn "Last.fm genre API request failed"
          pure Nothing

fetchDiscogsGenre :: String -> String -> Aff (Maybe String)
fetchDiscogsGenre artist release = do
  env <- liftEffect getEnv
  case Object.lookup "DISCOGS_TOKEN" env of
    Nothing -> do
      Log.warn "DISCOGS_TOKEN missing for genre fallback"
      pure Nothing
    Just t -> do
      let queryStr = artist <> " " <> release
      let searchUrl = "https://api.discogs.com/database/search?q=" <> (fromMaybe "" $ encodeURIComponent queryStr) <> "&type=release&per_page=1&token=" <> t
      Log.info $ "Fetching Discogs genre for: " <> queryStr
      result <- try $ fetch searchUrl { method: GET, headers: { "User-Agent": "ScrobblerPureScript/1.0" } }
      case result of
        Right fetchRes | fetchRes.status == 200 -> do
          jsonResult <- try $ fromJson fetchRes.json
          case jsonResult of
            Left err -> do
              Log.error $ "Discogs genre JSON error: " <> Exception.message err
              pure Nothing
            Right json -> do
              let
                genre = do
                  obj <- toObject json
                  results <- Object.lookup "results" obj >>= toArray
                  firstResult <- results !! 0 >>= toObject
                  genres <- Object.lookup "genres" firstResult >>= toArray
                  genres !! 0 >>= toString
              pure genre
        _ -> do
          Log.warn "Discogs genre API request failed"
          pure Nothing

yieldToSync :: Ref Boolean -> Aff Unit
yieldToSync isSyncing = do
  syncing <- liftEffect $ Ref.read isSyncing
  when syncing $ delay (Milliseconds 200.0) *> yieldToSync isSyncing

enrichMetadata :: Connection -> Ref Boolean -> Aff Unit
enrichMetadata conn isSyncing = forever do
  yieldToSync isSyncing
  -- Get both unenriched and empty genre MBIDs
  unenrichedMbids <- getUnenrichedMbids conn 10
  emptyGenreMbids <- getEmptyGenreMbids conn 10
  let allMbids = unenrichedMbids <> emptyGenreMbids

  if length allMbids == 0 then
    delay (Milliseconds 60000.0)
  else do
    Log.info $ "Processing " <> show (length unenrichedMbids) <> " unenriched + " <> show (length emptyGenreMbids) <> " empty genre releases"
    for_ allMbids \mbid -> do
      yieldToSync isSyncing
      delay (Milliseconds 1100.0)
      result <- try $ fetchMusicBrainzRelease mbid
      case result of
        Left err -> Log.error $ "Enrichment error: " <> Exception.message err
        Right Nothing -> pure unit
        Right (Just mbdata) -> do
          -- If genre is empty, try fallback sources
          if mbdata.genre == Nothing then do
            artistRelease <- getArtistReleaseByMbid conn mbid
            case artistRelease of
              Just { artist, release } -> do
                -- Try Last.fm first
                lastfmGenre <- fetchLastfmGenre artist release
                finalGenre <- case lastfmGenre of
                  Just _ -> pure lastfmGenre
                  Nothing -> do
                    -- Try Discogs as final fallback
                    fetchDiscogsGenre artist release

                -- Update with the best genre we found
                let finalMbdata = mbdata { genre = finalGenre }
                upsertReleaseMetadata conn mbid finalMbdata.genre finalMbdata.label finalMbdata.year

                case finalGenre of
                  Just genre -> Log.info $ "Added fallback genre from " <> (if lastfmGenre /= Nothing then "Last.fm" else "Discogs") <> " for " <> mbid <> ": " <> genre
                  Nothing -> do
                    Log.info $ "No genre found in any source for " <> mbid
                    touchGenreCheckedAt conn mbid
              Nothing -> do
                Log.warn $ "No artist/release info found for MBID " <> mbid <> ", cannot use fallback sources"
                upsertReleaseMetadata conn mbid mbdata.genre mbdata.label mbdata.year
                touchGenreCheckedAt conn mbid
          else do
            -- Genre found in MusicBrainz, just save as usual
            upsertReleaseMetadata conn mbid mbdata.genre mbdata.label mbdata.year

startServer :: Int -> String -> String -> Effect Unit
startServer port dbFile username = launchAff_ do
  conn <- connect dbFile
  initDb conn
  initReleaseMetadata conn
  isSyncing <- liftEffect $ Ref.new false
  void $ forkAff $ syncData conn username isSyncing
  void $ forkAff $ enrichMetadata conn isSyncing

  liftEffect $ do
    server <- createServer
    server # on_ Server.requestH (handleRequest conn isSyncing)
    let netServer = Server.toNetServer server

    netServer # on_ listeningH do
      Log.info $ "Server is running on port " <> show port

    listenTcp netServer { host: "127.0.0.1", port, backlog: 128 }

foreign import dotenvConfig :: Effect Unit

main :: Effect Unit
main = do
  dotenvConfig
  env <- getEnv
  let port = fromMaybe 8000 (Object.lookup "PORT" env >>= fromString)
  let dbFile = fromMaybe "scorpus.db" (Object.lookup "DATABASE_FILE" env)
  let username = fromMaybe "" (Object.lookup "LISTENBRAINZ_USER" env)
  when (username == "") $ Log.warn "LISTENBRAINZ_USER is not set — syncing will be disabled"
  startServer port dbFile username
