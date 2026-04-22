module Main where

import Prelude

import Config (AppConfig, UserConfig, UserEntry, loadConfig, s3ConfigFromUser)
import Effect (Effect)
import Node.EventEmitter (on_, EventHandle(..))
import Effect.Class (liftEffect)
import Log as Log
import Metrics as Metrics
import Node.HTTP (createServer)
import Node.HTTPS as HTTPS
import Node.HTTP.Server as Server
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

import Data.Either (Either(..))

import Effect.Exception as Exception
import Effect.Aff (Aff, launchAff_, makeAff, nonCanceler, try, delay, forkAff, joinFiber, killFiber, Fiber)
import Effect.Aff.AVar (AVar)
import Effect.Aff.AVar as Avar
import Unsafe.Coerce (unsafeCoerce)
import Node.FS.Aff as FSA
import Fetch (fetch, Method(GET))
import Fetch.Argonaut.Json (fromJson)

import Data.Maybe (Maybe(..), fromMaybe)
import JSURI (encodeURIComponent)
import Foreign.Object as Object
import Data.Argonaut (decodeJson, encodeJson, parseJson)
import Data.Argonaut.Core (Json, toObject, toArray, toString, stringify)
import Data.Array (find, length, mapMaybe, null)
import Data.Tuple (Tuple(..))
import Data.Foldable (for_, foldM, traverse_)
import Cover (serveCover)
import Cosine (serveSimilar)
import Metadata (enrichMetadata)
import Data.Traversable (traverse)
import Db (Connection, FilterField(..), backupDb, checkExists, connect, getOldestTs, getScrobbles, getStats, initDb, initReleaseMetadata, ping, upsertScrobble, withTransaction)
import Types (Listen(..), ListenBrainzResponse(..), MbidMapping(..), Payload(..), TrackMetadata(..))
import Control.Monad.Rec.Class (forever)
import Data.Time.Duration (Milliseconds(..))
import Data.Int (fromString, toNumber)
import Data.String (Pattern(..), stripPrefix)
import Node.Process (lookupEnv)

import Data.String.Regex (replace, parseFlags)
import Data.String.Regex.Unsafe (unsafeRegex)
import Effect.Aff.Retry (RetryStatus(..), exponentialBackoff, limitRetries, recovering)
import Web.URL (URL)
import Web.URL as URL
import Web.URL.URLSearchParams as URLSearchParams
import Templates (indexHtml)

-- Types
type Request = IncomingMessage IMServer

type Response = ServerResponse

type UserContext =
  { conn :: Connection
  , writeLock :: AVar Unit
  , config :: UserConfig
  , slug :: String
  , displayName :: String
  , enrichMetadataFiber :: Maybe (Fiber Unit)
  , backupFiber :: Maybe (Fiber Unit)
  }

listenBrainzUrl :: String -> String
listenBrainzUrl username = "https://api.listenbrainz.org/1/user/" <> username <> "/listens"

fetchListenBrainzUrl :: String -> Aff String
fetchListenBrainzUrl url = withRetry "ListenBrainz fetch" $ makeAff \callback -> do
  req <- HTTPS.get url

  req # on_ Client.responseH \res -> do
    launchAff_ do
      result <- try $ readableToStringUtf8 (IM.toReadable res)
      liftEffect $ case result of
        Left err ->
          callback (Left err)
        Right body ->
          if IM.statusCode res == 200 then
            callback (Right body)
          else
            callback (Left $ Exception.error $ "ListenBrainz API returned status " <> show (IM.statusCode res))

  let errorH = EventHandle "error" mkEffectFn1
  on_ errorH (\err -> callback (Left err)) (unsafeCoerce req)

  pure nonCanceler

withRetry :: forall a. String -> Aff a -> Aff a
withRetry label action = recovering policy [ \_ _ -> pure true ] \(RetryStatus status) -> do
  when (status.iterNumber > 0)
    $ Log.warn
    $ label <> " failed, retry attempt " <> show status.iterNumber
  action
  where
  policy = exponentialBackoff (Milliseconds 1000.0) <> limitRetries 5

fetchLastfmPage :: String -> String -> Int -> Maybe Int -> Aff { tracks :: Array Json, totalPages :: Int }
fetchLastfmPage apiKey lfmUser page mTo = withRetry "Last.fm fetch" do
  let
    toParam = case mTo of
      Just ts -> "&to=" <> show ts
      Nothing -> ""
    -- Build the base URL without the key so it is safe to log or include in errors.
    -- Last.fm does not support header-based auth, so the key must be a query param.
    baseUrl = "https://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&user="
      <> (fromMaybe lfmUser $ encodeURIComponent lfmUser)
      <> "&format=json&limit=200&page="
      <> show page
      <> toParam
    url = baseUrl <> "&api_key=" <> apiKey
  fr <- fetch url { method: GET }
  if fr.status == 200 then do
    json <- fromJson fr.json
    let
      parsed = do
        obj <- toObject json
        rt <- Object.lookup "recenttracks" obj >>= toObject
        tracks <- Object.lookup "track" rt >>= toArray
        attr <- Object.lookup "@attr" rt >>= toObject
        totalPagesStr <- Object.lookup "totalPages" attr >>= toString
        totalPages <- fromString totalPagesStr
        pure { tracks, totalPages }
    case parsed of
      Just result -> pure result
      Nothing -> liftEffect $ Exception.error "Last.fm: Failed to parse JSON response" # Exception.throwException
  else do
    liftEffect $ Exception.error ("Last.fm API returned status " <> show fr.status) # Exception.throwException

lastfmTrackToListen :: Json -> Maybe Listen
lastfmTrackToListen json = do
  obj <- toObject json
  trackName <- Object.lookup "name" obj >>= toString
  artistObj <- Object.lookup "artist" obj >>= toObject
  artistName <- Object.lookup "#text" artistObj >>= toString
  albumObj <- Object.lookup "album" obj >>= toObject
  let releaseName = Object.lookup "#text" albumObj >>= toString
  let
    releaseMbid = do
      s <- Object.lookup "mbid" albumObj >>= toString
      if s == "" then Nothing else Just s
  -- nowplaying tracks have no date field — naturally filtered out here
  dateObj <- Object.lookup "date" obj >>= toObject
  utsStr <- Object.lookup "uts" dateObj >>= toString
  ts <- fromString utsStr
  pure $ Listen
    { listenedAt: Just ts
    , trackMetadata: TrackMetadata
        { trackName: Just trackName
        , artistName: Just artistName
        , releaseName: releaseName
        , genre: Nothing
        , label: Nothing
        , mbidMapping: Just $ MbidMapping
            { releaseMbid: releaseMbid
            , caaReleaseMbid: releaseMbid
            }
        }
    }

recordSyncSuccess :: String -> String -> Int -> Aff Unit
recordSyncSuccess slug source n = do
  liftEffect $ Metrics.incSyncRuns slug source "success"
  when (n > 0) $ liftEffect $ Metrics.incSyncScrobbles slug source n
  liftEffect $ Metrics.setSyncLastSuccess slug source

-- One complete paginated pass; used for both initial and recurring syncs.
lbSyncOnce :: Connection -> String -> String -> AVar Unit -> Boolean -> Aff Unit
lbSyncOnce conn username slug writeLock initialSyncEnabled = void performFullSync
  where
  performFullSync = do
    when initialSyncEnabled $ Log.info $ "Starting ListenBrainz sync for " <> username
    result <- try $ fetchListenBrainzUrl (listenBrainzUrl username <> "?count=100")
    case result of
      Right body -> do
        case parseJson body >>= decodeJson of
          Left err -> do
            Log.error $ "Sync parse error: " <> show err
            liftEffect $ Metrics.incSyncRuns slug "listenbrainz" "error"
          Right (ListenBrainzResponse { payload: Payload { listens } }) -> do
            Tuple added (Tuple minTs hitCount) <- withTransaction conn writeLock (processListens listens)
            when (added > 0 || initialSyncEnabled)
              $ Log.info
              $ "ListenBrainz batch: added " <> show added <> ", " <> show hitCount <> " already present."
            let allExist = hitCount == length listens && not (null listens)
            if allExist || null listens then do
              when (added > 0) $ Log.info $ "ListenBrainz sync complete. Added " <> show added <> " new scrobbles."
              recordSuccess added
            else if initialSyncEnabled then do
              total <- paginateUntilDone 2 minTs added
              Log.info $ "ListenBrainz sync complete. Added " <> show total <> " new scrobbles."
              recordSuccess total
            else do
              when (added > 0) $ Log.info $ "ListenBrainz sync complete. Added " <> show added <> " new scrobbles."
              recordSuccess added
      Left err -> do
        Log.error $ "Sync fetch error: " <> Exception.message err
        liftEffect $ Metrics.incSyncRuns slug "listenbrainz" "error"

  paginateUntilDone batchNum minTs acc = case minTs of
    Nothing ->
      pure acc
    Just ts -> do
      Log.info $ "Fetching ListenBrainz batch " <> show batchNum <> " (before " <> show ts <> ")..."
      result <- try $ fetchListenBrainzUrl (listenBrainzUrl username <> "?count=100&max_ts=" <> show ts)
      case result of
        Right body -> do
          case parseJson body >>= decodeJson of
            Left err -> do
              Log.error $ "Sync parse error: " <> show err
              pure acc
            Right (ListenBrainzResponse { payload: Payload { listens } }) -> do
              Tuple added (Tuple newMinTs hitCount) <- withTransaction conn writeLock (processListens listens)
              Log.info $ "ListenBrainz batch " <> show batchNum <> ": added " <> show added <> ", " <> show hitCount <> " already present."
              let allExist = hitCount == length listens && not (null listens)
              if allExist || null listens then do
                pure (acc + added)
              else do
                paginateUntilDone (batchNum + 1) newMinTs (acc + added)
        Left err -> do
          Log.error $ "Sync fetch error: " <> Exception.message err
          pure acc

  recordSuccess = recordSyncSuccess slug "listenbrainz"

  processListens listens = do
    s <- foldM step { added: 0, minTs: Nothing, hitCount: 0 } listens
    pure $ Tuple s.added (Tuple s.minTs s.hitCount)
    where
    step s l@(Listen { listenedAt: Just ts }) = do
      exists <- checkExists conn ts
      if exists then pure s { minTs = Just ts, hitCount = s.hitCount + 1 }
      else do
        upsertScrobble conn l
        pure s { added = s.added + 1, minTs = Just ts }
    step s _ = do
      Log.warn "Skipping scrobble without timestamp"
      pure s

lbSyncLoop :: Connection -> String -> String -> AVar Unit -> Boolean -> Aff Unit
lbSyncLoop conn username slug writeLock initialSyncEnabled = forever do
  delay (Milliseconds 60000.0)
  lbSyncOnce conn username slug writeLock initialSyncEnabled

lfSyncOnce :: Connection -> String -> String -> String -> AVar Unit -> Boolean -> Aff Unit
lfSyncOnce conn apiKey lfmUser slug writeLock initialSyncEnabled = do
  void $ performLastfmSync
  when initialSyncEnabled $ void $ performLastfmBackfill
  where
  performLastfmSync = do
    when initialSyncEnabled $ Log.info $ "Starting Last.fm sync for " <> lfmUser
    { tracks, totalPages } <- fetchLastfmPage apiKey lfmUser 1 Nothing
    Tuple added hitCount <- withTransaction conn writeLock (processLastfmTracks tracks)
    when (added > 0 || initialSyncEnabled)
      $ Log.info
      $ "Last.fm page 1/" <> show totalPages <> ": added " <> show added <> ", " <> show hitCount <> " already present."
    let
      validTracks = mapMaybe lastfmTrackToListen tracks
      allExist = hitCount == length validTracks && not (null validTracks)
    if allExist || totalPages <= 1 then do
      when (added > 0) $ Log.info $ "Last.fm sync complete. Added " <> show added <> " new scrobbles."
      recordSuccess added
    else if initialSyncEnabled then do
      total <- paginateLastfmUntilDone 2 totalPages Nothing added
      Log.info $ "Last.fm sync complete. Added " <> show total <> " new scrobbles."
      recordSuccess total
    else do
      when (added > 0) $ Log.info $ "Last.fm sync complete. Added " <> show added <> " new scrobbles."
      recordSuccess added

  paginateLastfmUntilDone page totalPages mTo acc
    | page > totalPages = pure acc
    | otherwise = do
        when initialSyncEnabled $ Log.info $ "Fetching Last.fm page " <> show page <> "/" <> show totalPages <> "..."
        { tracks } <- fetchLastfmPage apiKey lfmUser page mTo
        Tuple added hitCount <- withTransaction conn writeLock (processLastfmTracks tracks)
        Log.info $ "Last.fm page " <> show page <> "/" <> show totalPages <> ": added " <> show added <> ", " <> show hitCount <> " already present."
        let
          validTracks = mapMaybe lastfmTrackToListen tracks
          allExist = hitCount == length validTracks && not (null validTracks)
        if allExist || null tracks then pure (acc + added)
        else paginateLastfmUntilDone (page + 1) totalPages mTo (acc + added)

  performLastfmBackfill = do
    mOldest <- getOldestTs conn
    for_ mOldest \oldestTs -> do
      when initialSyncEnabled $ Log.info $ "Checking for Last.fm history before " <> show oldestTs <> "..."
      { tracks, totalPages } <- fetchLastfmPage apiKey lfmUser 1 (Just (oldestTs - 1))
      if null tracks then
        when initialSyncEnabled $ Log.info "No older Last.fm history found."
      else do
        Log.info $ "Backfilling " <> show totalPages <> " pages of Last.fm history before " <> show oldestTs
        Tuple added hitCount <- withTransaction conn writeLock (processLastfmTracks tracks)
        Log.info $ "Last.fm backfill page 1/" <> show totalPages <> ": added " <> show added <> ", " <> show hitCount <> " already present."
        total <- paginateLastfmUntilDone 2 totalPages (Just (oldestTs - 1)) added
        Log.info $ "Last.fm backfill complete. Added " <> show total <> " older scrobbles."

  recordSuccess = recordSyncSuccess slug "lastfm"

  processLastfmTracks tracks = do
    s <- foldM step { added: 0, hitCount: 0 } (mapMaybe lastfmTrackToListen tracks)
    pure $ Tuple s.added s.hitCount
    where
    step s l@(Listen { listenedAt: Just ts }) = do
      exists <- checkExists conn ts
      if exists then pure s { hitCount = s.hitCount + 1 }
      else do
        upsertScrobble conn l
        pure s { added = s.added + 1 }
    step s _ = pure s

lfSyncLoop :: Connection -> String -> String -> String -> AVar Unit -> Boolean -> Aff Unit
lfSyncLoop conn apiKey lfmUser slug writeLock initialSyncEnabled = forever do
  delay (Milliseconds 60000.0)
  lfSyncOnce conn apiKey lfmUser slug writeLock initialSyncEnabled

normalizePath :: String -> String
normalizePath path = case stripPrefix (Pattern "/u/") path of
  Just _ -> "/u/:slug"
  Nothing -> path

-- Request handler
-- API endpoints (/proxy, /stats, /cover, /healthz) select the user via ?user=<slug>.
-- Index pages are served at / (root user) and /u/<slug> (named users).
handleRequest :: Boolean -> Array UserContext -> Request -> Response -> Effect Unit
handleRequest metricsEnabled contexts req res = do
  let method = IM.method req
  let rawUrl = IM.url req
  let allUsers = map (\ctx -> { slug: ctx.slug, name: ctx.displayName }) contexts
  case URL.fromRelative rawUrl "http://localhost" of
    Nothing ->
      serveNotFound res
    Just url -> do
      let path = URL.pathname url
      Metrics.wrapRequest method (normalizePath path) Log.info req res do
        launchAff_ $ do
          result <- try $ routeRequest metricsEnabled contexts url path allUsers res
          case result of
            Left err -> do
              Log.error $ "Internal server error: " <> Exception.message err
              liftEffect $ serveInternalError res
            Right _ ->
              pure unit

routeRequest :: Boolean -> Array UserContext -> URL -> String -> Array { slug :: String, name :: String } -> Response -> Aff Unit
routeRequest metricsEnabled contexts url path allUsers res = liftEffect $ case path of
  "/client.js" ->
    serveClientJs res
  "/favicon.png" ->
    serveAsset "image/png" "assets/favicon.png" res
  "/" ->
    serveIndex allUsers "" res
  "/metrics" ->
    if metricsEnabled then serveMetrics res
    else do
      Log.warn "Path not found: /metrics"
      serveNotFound res
  "/proxy" ->
    withUser url \ctx -> serveProxy ctx.conn url res
  "/stats" ->
    withUser url \ctx -> serveStats ctx.conn url res
  "/cover" ->
    withUser url \ctx -> launchAff_ $ serveCover serveNotFound ctx.config ctx.slug url res
  "/similar" ->
    withUser url \ctx -> serveSimilar serveBadRequest serveError ctx.slug ctx.config url res
  "/healthz" ->
    withUser url \ctx -> serveHealthz ctx.conn res
  _ ->
    case stripPrefix (Pattern "/u/") path of
      Just slug ->
        serveIndex allUsers slug res
      Nothing -> do
        Log.warn $ "Path not found: " <> path
        serveNotFound res
  where
  withUser urlParam f =
    let
      slug = fromMaybe "" (getQueryParam "user" urlParam)
    in
      case find (\c -> c.slug == slug) contexts of
        Nothing -> do
          Log.warn $ "Unknown user: " <> show slug
          serveNotFound res
        Just ctx ->
          f ctx

serveIndex :: Array { slug :: String, name :: String } -> String -> Response -> Effect Unit
serveIndex allUsers slug res = do
  setHeader "Content-Type" "text/html" (toOutgoingMessage res)
  setStatusCode 200 res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 (indexHtml slug allUsers)
  end w

serveMetrics :: Response -> Effect Unit
serveMetrics res = do
  launchAff_ do
    contentType <- liftEffect Metrics.getContentType
    metricsText <- Metrics.getMetrics
    liftEffect $ do
      setHeader "Content-Type" contentType (toOutgoingMessage res)
      setStatusCode 200 res
      let w = toWriteable (toOutgoingMessage res)
      void $ writeString w UTF8 metricsText
      end w

serveClientJs :: Response -> Effect Unit
serveClientJs res = do
  setHeader "Content-Type" "application/javascript" (toOutgoingMessage res)
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

parseFilterField :: String -> Maybe FilterField
parseFilterField "artist" = Just FilterArtist
parseFilterField "album" = Just FilterAlbum
parseFilterField "label" = Just FilterLabel
parseFilterField "year" = Just FilterYear
parseFilterField "genre" = Just FilterGenre
parseFilterField "track" = Just FilterTrack
parseFilterField _ = Nothing

serveProxy :: Connection -> URL -> Response -> Effect Unit
serveProxy db url res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)

  launchAff_ do
    let limit = fromMaybe 25 (getQueryParam "limit" url >>= fromString)
    let offset = fromMaybe 0 (getQueryParam "offset" url >>= fromString)
    let
      mFilter = do
        field <- getQueryParam "filterField" url >>= parseFilterField
        value <- getQueryParam "filterValue" url
        pure { field, value }

    let mSearch = getQueryParam "search" url
    listens <- getScrobbles db limit offset mFilter mSearch
    let responseBody = stringify $ encodeJson { payload: { listens: listens } }

    liftEffect $ do
      setStatusCode 200 res
      let w = toWriteable (toOutgoingMessage res)
      void $ writeString w UTF8 responseBody
      end w

serveStats :: Connection -> URL -> Response -> Effect Unit
serveStats db url res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  launchAff_ do
    let period = getQueryParam "period" url
    let section = getQueryParam "section" url
    let safeDate = map (replace (unsafeRegex "[^0-9\\-]" (parseFlags "g")) "")
    let mFrom = safeDate (getQueryParam "from" url)
    let mTo = safeDate (getQueryParam "to" url)
    stats <- getStats db period mFrom mTo section
    let responseBody = stringify $ encodeJson stats
    liftEffect $ do
      setStatusCode 200 res
      let w = toWriteable (toOutgoingMessage res)
      void $ writeString w UTF8 responseBody
      end w

serveAsset :: String -> String -> Response -> Effect Unit
serveAsset contentType path res = do
  setHeader "Content-Type" contentType (toOutgoingMessage res)
  setHeader "Cache-Control" "public, max-age=86400" (toOutgoingMessage res)
  launchAff_ do
    result <- try $ FSA.readFile path
    liftEffect $ case result of
      Right buf -> do
        setStatusCode 200 res
        let w = toWriteable (toOutgoingMessage res)
        void $ write w buf
        end w
      Left _ ->
        serveNotFound res

serveHealthz :: Connection -> Response -> Effect Unit
serveHealthz db res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  launchAff_ do
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
  setStatusCode 404 res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 "Not Found"
  end w

serveInternalError :: Response -> Effect Unit
serveInternalError res = do
  setHeader "Content-Type" "text/plain" (toOutgoingMessage res)
  setStatusCode 500 res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 "Internal Server Error"
  end w

serveBadRequest :: Response -> String -> Effect Unit
serveBadRequest res message = do
  setHeader "Content-Type" "text/plain" (toOutgoingMessage res)
  setStatusCode 400 res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 message
  end w

serveError :: Response -> Int -> String -> String -> Effect Unit
serveError res statusCode statusName message = do
  setHeader "Content-Type" "text/plain" (toOutgoingMessage res)
  setStatusCode statusCode res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 (statusName <> ": " <> message)
  end w

startUser :: UserEntry -> Aff UserContext
startUser { slug, name, config } = do
  Log.info $ "Starting user: " <> if slug == "" then "(root)" else slug
  conn <- connect config.databaseFile
  initDb conn
  initReleaseMetadata conn
  writeLock <- Avar.new unit

  case config.lastfmUser, config.lastfmApiKey of
    Just _, Nothing -> Log.warn $ "lastfmUser set for user '" <> slug <> "' but lastfmApiKey is missing — Last.fm sync disabled"
    _, _ -> pure unit

  -- Fork initial syncs; they run in the background so the HTTP server can
  -- start immediately. A separate fiber waits for them to finish before
  -- starting the recurring loops (preserving the original ordering guarantee).
  lbFiber <- case config.listenbrainzUser of
    Just username -> Just <$> forkAff (lbSyncOnce conn username slug writeLock config.initialSync)
    Nothing -> pure Nothing
  lfFiber <- case config.lastfmUser, config.lastfmApiKey of
    Just lfmUser, Just apiKey -> Just <$> forkAff (lfSyncOnce conn apiKey lfmUser slug writeLock config.initialSync)
    _, _ -> pure Nothing

  -- Wait for initial syncs then start recurring loops — all in background.
  void $ forkAff do
    for_ lbFiber joinFiber
    for_ lfFiber joinFiber
    for_ config.listenbrainzUser \username ->
      void $ forkAff $ lbSyncLoop conn username slug writeLock config.initialSync
    case config.lastfmUser, config.lastfmApiKey of
      Just lfmUser, Just apiKey -> void $ forkAff $ lfSyncLoop conn apiKey lfmUser slug writeLock config.initialSync
      _, _ -> pure unit

  -- Background tasks that don't depend on initial sync completion.
  enrichMetadataFiber <- forkAff $ enrichMetadata conn config slug
  backupFiber <-
    if config.backupEnabled then Just <$> forkAff (backupDb conn config.databaseFile (s3ConfigFromUser config) (toNumber config.backupIntervalHours * 3600000.0) slug)
    else pure Nothing

  let displayName = fromMaybe (if slug == "" then "root" else slug) name
  pure { conn, writeLock, config, slug, displayName, enrichMetadataFiber: Just enrichMetadataFiber, backupFiber }

cleanupUser :: UserContext -> Aff Unit
cleanupUser ctx = do
  Log.info $ "Cleaning up user: " <> if ctx.slug == "" then "(root)" else ctx.slug
  -- Kill background fibers
  case ctx.enrichMetadataFiber of
    Just fiber -> do
      Log.info "Killing enrich metadata fiber"
      void $ try $ killFiber (Exception.error "Server shutting down") fiber
    Nothing -> do
      pure unit
  case ctx.backupFiber of
    Just fiber -> do
      Log.info "Killing backup fiber"
      void $ try $ killFiber (Exception.error "Server shutting down") fiber
    Nothing -> do
      pure unit
  -- Close database connection
  Log.info "Closing database connection"
  void $ try $ ping ctx.conn

foreign import dotenvConfig :: Effect Unit

main :: Effect Unit
main = do
  dotenvConfig
  launchAff_ do
    configFile <- liftEffect $ map (fromMaybe "users.json") $ lookupEnv "CORPUS_USERS_FILE"
    result <- try $ loadConfig configFile
    case result of
      Left err -> do
        Log.error $ "Failed to load " <> configFile <> ": " <> Exception.message err
        liftEffect $ Exception.throwException err
      Right (appConfig :: AppConfig) -> do
        Log.info $ "Loaded " <> show (length appConfig.users) <> " user(s) from users.dhall"
        contexts <- traverse startUser appConfig.users
        liftEffect $ do
          server <- createServer
          server # on_ Server.requestH (handleRequest appConfig.metricsEnabled contexts)
          let netServer = Server.toNetServer server

          netServer # on_ listeningH do
            Log.info $ "Server is running on port " <> show appConfig.port

          listenTcp netServer { host: "127.0.0.1", port: appConfig.port, backlog: 128 }

cleanupAll :: Array UserContext -> Aff Unit
cleanupAll contexts = do
  Log.info "Starting graceful shutdown of all users"
  traverse_ cleanupUser contexts
  Log.info "Graceful shutdown complete"
