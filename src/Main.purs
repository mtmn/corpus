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
import Node.Stream (Writable, end, writeString)
import Node.Stream.Aff (readableToStringUtf8)
import Node.Encoding (Encoding(UTF8))
import Node.Net.Server (listenTcp, listeningH)
import Data.Either (Either(..))
import Effect.Exception as Exception
import Effect.Aff (Aff, launchAff_, makeAff, nonCanceler, try, delay, forkAff)
import Foreign (Foreign)
import Unsafe.Coerce (unsafeCoerce)
import Node.FS.Aff as FSA
import Node.Process (getEnv)
import Fetch (fetch, Method(GET), lookup)
import Fetch.Argonaut.Json (fromJson)
import Data.Maybe (Maybe(..), fromMaybe)
import JSURI (encodeURIComponent)
import Node.URL (URL, new', pathname)
import Foreign.Object as Object
import Data.Argonaut (decodeJson, encodeJson, parseJson)
import Data.Argonaut.Core (toObject, toArray, toString, stringify)
import Data.Array ((!!), length, uncons)
import Data.Nullable (Nullable, toMaybe)
import Data.Tuple (Tuple(..))
import Db (Connection, connect, initDb, upsertScrobble, getScrobbles, checkExists, run)
import Types (Listen(..), ListenBrainzResponse(..), Payload(..), TrackMetadata(..))
import Control.Monad.Rec.Class (forever)
import Data.Time.Duration (Milliseconds(..))
import Data.Int (fromString)
import S3 (existsInS3, uploadToS3, getS3Url)

-- Types
type Request = IncomingMessage IMServer
type Response = ServerResponse

listenBrainzUrl :: String
listenBrainzUrl = "https://api.listenbrainz.org/1/user/mtmn/listens"

fetchListenBrainzData :: Int -> Aff String
fetchListenBrainzData count = makeAff \callback -> do
  let url = listenBrainzUrl <> "?count=" <> show count
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

fetchListenBrainzDataBefore :: Int -> Aff String
fetchListenBrainzDataBefore maxTs = makeAff \callback -> do
  let url = listenBrainzUrl <> "?count=100&max_ts=" <> show maxTs
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

syncData :: Connection -> Aff Unit
syncData conn = do
  forever do
    void $ performFullSync
    delay (Milliseconds 60000.0)

  where
  performFullSync = do
    result <- try $ fetchListenBrainzData 100
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
      result <- try $ fetchListenBrainzDataBefore ts
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
    <title>scorpus</title>
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
            margin-left: 15px;
            border-radius: 4px;
            object-fit: cover;
            background: rgba(255, 255, 255, 0.05);
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
    </style>
</head>
<body>
    <div id="app"></div>
    <script src="/client.js"></script>
</body>
</html>"""

-- Request handler
handleRequest :: Connection -> Request -> Response -> Effect Unit
handleRequest db req res = do
  let method = IM.method req
  let rawUrl = IM.url req
  url <- new' rawUrl "http://localhost"
  path <- pathname url
  Log.info $ method <> " " <> rawUrl

  case path of
    "/" -> serveIndex res
    "/proxy" -> serveProxy db url res
    "/caa-cover" -> serveCaaCover url res
    "/discogs-cover" -> serveDiscogsCover url res
    "/lastfm-cover" -> serveLastfmCover url res
    "/client.js" -> serveClientJs res
    "/favicon.ico" -> serveFavicon res
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

foreign import getQueryParam :: String -> URL -> Effect (Nullable String)
foreign import writeBuffer :: forall r. Writable r -> Foreign -> Effect Unit
foreign import sanitizeKey :: String -> String

serveCaaCover :: URL -> Response -> Effect Unit
serveCaaCover url res = do
  launchAff_ do
    mbidMaybe <- liftEffect $ getQueryParam "mbid" url
    case toMaybe mbidMaybe of
      Nothing -> do
        Log.warn "CAA cover request missing mbid"
        liftEffect $ serveNotFound res
      Just mbid -> do
        let s3Key = "covers/caa/" <> mbid <> ".jpg"
        cachedResult <- try $ existsInS3 s3Key
        let
          cached = case cachedResult of
            Right b -> b
            Left _ -> false

        if cached then do
          Log.info $ "Serving CAA cover from S3: " <> s3Key
          liftEffect $ do
            setStatusCode 302 res
            setHeader "Location" (getS3Url s3Key) (toOutgoingMessage res)
            end (toWriteable (toOutgoingMessage res))
        else do
          let caaUrl = "https://coverartarchive.org/release/" <> mbid <> "/front-250"
          Log.info $ "Fetching CAA cover: " <> mbid
          proxyAndCacheImage caaUrl s3Key res

serveLastfmCover :: URL -> Response -> Effect Unit
serveLastfmCover url res = do
  launchAff_ do
    artistMaybe <- liftEffect $ getQueryParam "artist" url
    releaseMaybe <- liftEffect $ getQueryParam "release" url
    let artistStr = fromMaybe "" (toMaybe artistMaybe)
    let releaseStr = fromMaybe "" (toMaybe releaseMaybe)

    if artistStr == "" || releaseStr == "" then do
      Log.warn $ "Last.fm cover request missing artist or release: artist=" <> artistStr <> ", release=" <> releaseStr
      liftEffect $ serveNotFound res
    else do
      let safeArtist = sanitizeKey artistStr
      let safeRelease = sanitizeKey releaseStr
      let s3Key = "covers/lastfm/" <> safeArtist <> "-" <> safeRelease <> ".jpg"

      cachedResult <- try $ existsInS3 s3Key
      let
        cached = case cachedResult of
          Right b -> b
          Left _ -> false

      if cached then do
        Log.info $ "Serving Last.fm cover from S3: " <> s3Key
        liftEffect $ do
          setStatusCode 302 res
          setHeader "Location" (getS3Url s3Key) (toOutgoingMessage res)
          end (toWriteable (toOutgoingMessage res))
      else do
        env <- liftEffect getEnv
        let apiKey = Object.lookup "LASTFM_API_KEY" env
        case apiKey of
          Nothing -> do
            Log.error "LASTFM_API_KEY not found in env"
            liftEffect $ serveNotFound res
          Just k -> do
            let searchUrl = "https://ws.audioscrobbler.com/2.0/?method=album.getinfo&api_key=" <> k <> "&artist=" <> (fromMaybe "" $ encodeURIComponent artistStr) <> "&album=" <> (fromMaybe "" $ encodeURIComponent releaseStr) <> "&format=json"
            Log.info $ "Last.fm search: " <> artistStr <> " - " <> releaseStr

            result <- try $ fetch searchUrl { method: GET }
            case result of
              Right fetchRes -> do
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
                    proxyAndCacheImage urlStr s3Key res
                  Nothing -> do
                    Log.info $ "No Last.fm cover found for: " <> artistStr <> " - " <> releaseStr
                    liftEffect $ serveNotFound res
              Left err -> do
                Log.error $ "Last.fm API error: " <> Exception.message err
                liftEffect $ serveNotFound res

serveDiscogsCover :: URL -> Response -> Effect Unit
serveDiscogsCover url res = do
  launchAff_ do
    artistMaybe <- liftEffect $ getQueryParam "artist" url
    releaseMaybe <- liftEffect $ getQueryParam "release" url
    let artistStr = fromMaybe "" (toMaybe artistMaybe)
    let releaseStr = fromMaybe "" (toMaybe releaseMaybe)

    if artistStr == "" || releaseStr == "" then do
      Log.warn $ "Discogs cover request missing artist or release: artist=" <> artistStr <> ", release=" <> releaseStr
      liftEffect $ serveNotFound res
    else do
      let safeArtist = sanitizeKey artistStr
      let safeRelease = sanitizeKey releaseStr
      let s3Key = "covers/discogs/" <> safeArtist <> "-" <> safeRelease <> ".jpg"

      cachedResult <- try $ existsInS3 s3Key
      let
        cached = case cachedResult of
          Right b -> b
          Left _ -> false

      if cached then do
        Log.info $ "Serving Discogs cover from S3: " <> s3Key
        liftEffect $ do
          setStatusCode 302 res
          setHeader "Location" (getS3Url s3Key) (toOutgoingMessage res)
          end (toWriteable (toOutgoingMessage res))
      else do
        env <- liftEffect getEnv
        let token = Object.lookup "DISCOGS_TOKEN" env
        case token of
          Nothing -> do
            Log.error "DISCOGS_TOKEN not found in env"
            liftEffect $ serveNotFound res
          Just t -> do
            let queryStr = artistStr <> " " <> releaseStr
            let searchUrl = "https://api.discogs.com/database/search?q=" <> (fromMaybe "" $ encodeURIComponent queryStr) <> "&type=release&per_page=1&token=" <> t
            Log.info $ "Discogs search (broad): " <> queryStr

            result <- try $ fetch searchUrl { method: GET, headers: { "User-Agent": "ScrobblerPureScript/1.0" } }
            case result of
              Right fetchRes -> do
                json <- fromJson fetchRes.json
                let
                  coverUrl = do
                    obj <- toObject json
                    results <- Object.lookup "results" obj >>= toArray
                    firstResult <- results !! 0 >>= toObject
                    cover <- Object.lookup "cover_image" firstResult >>= toString
                    pure cover

                case coverUrl of
                  Just urlStr -> do
                    Log.info $ "Found Discogs cover: " <> urlStr
                    proxyAndCacheImage urlStr s3Key res
                  Nothing -> do
                    Log.info $ "No Discogs cover found for: " <> queryStr
                    liftEffect $ serveNotFound res
              Left err -> do
                Log.error $ "Discogs API error: " <> Exception.message err
                liftEffect $ serveNotFound res

proxyAndCacheImage :: String -> String -> Response -> Aff Unit
proxyAndCacheImage urlStr s3Key res = do
  Log.info $ "Proxying and caching image: " <> urlStr
  makeAff \cb -> do
    launchAff_ do
      fetchResult <- try $ fetch urlStr { method: GET }
      case fetchResult of
        Right fr -> do
          let contentType = fromMaybe "image/jpeg" $ lookup "content-type" fr.headers
          buf <- fr.arrayBuffer
          liftEffect $ do
            setStatusCode fr.status res
            setHeader "Content-Type" contentType (toOutgoingMessage res)
            setHeader "Cache-Control" "public, max-age=86400" (toOutgoingMessage res)
            let writer = toWriteable (toOutgoingMessage res)
            writeBuffer writer (unsafeCoerce buf)
            end writer

          -- Cache to S3
          uploadResult <- try $ uploadToS3 s3Key (unsafeCoerce buf) contentType
          case uploadResult of
            Right _ -> Log.info $ "Cached to S3: " <> s3Key
            Left err -> Log.error $ "S3 upload failed: " <> Exception.message err
          liftEffect $ cb (Right unit)
        Left err -> do
          Log.error $ "Failed to fetch image: " <> Exception.message err
          liftEffect $ serveNotFound res
          liftEffect $ cb (Right unit)
    pure nonCanceler

serveProxy :: Connection -> URL -> Response -> Effect Unit
serveProxy db url res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Methods" "GET, POST, OPTIONS" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Headers" "*" (toOutgoingMessage res)

  launchAff_ do
    limitStr <- liftEffect $ getQueryParam "limit" url
    offsetStr <- liftEffect $ getQueryParam "offset" url

    let limit = fromMaybe 25 (toMaybe limitStr >>= fromString)
    let offset = fromMaybe 0 (toMaybe offsetStr >>= fromString)

    listens <- getScrobbles db limit offset
    let responseBody = stringify $ encodeJson { payload: { listens: listens } }

    liftEffect $ do
      setStatusCode 200 res
      let w = toWriteable (toOutgoingMessage res)
      void $ writeString w UTF8 responseBody
      end w

serveFavicon :: Response -> Effect Unit
serveFavicon res = do
  setHeader "Content-Type" "image/x-icon" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  setStatusCode 200 res
  end (toWriteable (toOutgoingMessage res))

serveNotFound :: Response -> Effect Unit
serveNotFound res = do
  setHeader "Content-Type" "text/plain" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  setStatusCode 404 res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 "Not Found"
  end w

startServer :: Int -> Effect Unit
startServer port = launchAff_ do
  conn <- connect "scorpus.db"
  initDb conn
  void $ forkAff $ syncData conn

  liftEffect $ do
    server <- createServer
    server # on_ Server.requestH (handleRequest conn)
    let netServer = Server.toNetServer server

    netServer # on_ listeningH do
      Log.info $ "Server is running on port " <> show port

    listenTcp netServer { host: "127.0.0.1", port, backlog: 128 }

foreign import dotenvConfig :: Effect Unit

main :: Effect Unit
main = do
  dotenvConfig
  startServer 8000

foreign import split :: String -> String -> Array String
