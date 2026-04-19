module Main where

import Prelude

import Config (AppConfig, UserConfig, UserEntry, loadConfig, s3ConfigFromUser)
import Effect (Effect)
import Effect.Class (liftEffect)
import Log as Log
import Metrics as Metrics
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
import Data.Either (Either(..), hush)
import Control.Monad.Error.Class (throwError)
import Effect.Exception as Exception
import Effect.Aff (Aff, launchAff_, makeAff, nonCanceler, try, delay, forkAff, joinFiber)
import Effect.Aff.AVar (AVar)
import Effect.Aff.AVar as Avar
import Unsafe.Coerce (unsafeCoerce)
import Node.FS.Aff as FSA
import Fetch (fetch, Method(GET), lookup)
import Fetch.Argonaut.Json (fromJson)
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import JSURI (encodeURIComponent)
import Foreign.Object as Object
import Data.Argonaut (decodeJson, encodeJson, parseJson)
import Data.Argonaut.Core (Json, toObject, toArray, toString, stringify)
import Data.Array ((!!), length, null, mapMaybe, find)
import Data.Tuple (Tuple(..))
import Data.Foldable (for_, foldM)
import Data.Traversable (traverse)
import Db (Connection, FilterField(..), connect, initDb, upsertScrobble, getScrobbles, checkExists, getOldestTs, initReleaseMetadata, getUnenrichedMbids, getEmptyGenreMbids, getArtistReleasesByMbids, upsertReleaseMetadata, touchGenreCheckedAt, getStats, ping, backupDb, withTransaction)
import Types (Listen(..), ListenBrainzResponse(..), MbidMapping(..), Payload(..), TrackMetadata(..))
import Control.Monad.Rec.Class (forever)
import Data.Time.Duration (Milliseconds(..))
import Data.Int (fromString, toNumber)
import Data.String (Pattern(..), stripPrefix)
import Node.Process (lookupEnv)
import Data.String.Common (split) as String
import Data.String.Regex (replace, parseFlags)
import Data.String.Regex.Unsafe (unsafeRegex)
import S3 (existsInS3, uploadToS3, getS3Url)
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
        , mbidMapping: Just $ MbidMapping
            { releaseMbid: releaseMbid
            , caaReleaseMbid: releaseMbid
            }
        }
    }

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

  recordSuccess n = do
    liftEffect $ Metrics.incSyncRuns slug "listenbrainz" "success"
    when (n > 0) $ liftEffect $ Metrics.incSyncScrobbles slug "listenbrainz" n
    liftEffect $ Metrics.setSyncLastSuccess slug "listenbrainz"

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

  recordSuccess n = do
    liftEffect $ Metrics.incSyncRuns slug "lastfm" "success"
    when (n > 0) $ liftEffect $ Metrics.incSyncScrobbles slug "lastfm" n
    liftEffect $ Metrics.setSyncLastSuccess slug "lastfm"

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
normalizePath path = case stripPrefix (Pattern "/~") path of
  Just _ -> "/~:slug"
  Nothing -> path

-- Request handler
-- API endpoints (/proxy, /stats, /cover, /healthz) select the user via ?user=<slug>.
-- Index pages are served at / (root user) and /~<slug> (named users).
handleRequest :: Boolean -> Array UserContext -> Request -> Response -> Effect Unit
handleRequest metricsEnabled contexts req res = do
  let method = IM.method req
  let rawUrl = IM.url req
  case URL.fromRelative rawUrl "http://localhost" of
    Nothing ->
      serveNotFound res
    Just url -> do
      let path = URL.pathname url
      Metrics.wrapRequest method (normalizePath path) Log.info req res do
        case path of
          "/client.js" ->
            serveClientJs res
          "/favicon.png" ->
            serveAsset "image/png" "assets/favicon.png" res
          "/" ->
            serveIndex "" res
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
            withUser url \ctx -> serveCover ctx.config ctx.slug url res
          "/similar" ->
            withUser url \ctx -> serveSimilar ctx.slug ctx.config url res
          "/healthz" ->
            withUser url \ctx -> serveHealthz ctx.conn res
          _ ->
            case stripPrefix (Pattern "/~") path of
              Just slug ->
                serveIndex slug res
              Nothing -> do
                Log.warn $ "Path not found: " <> path
                serveNotFound res
  where
  withUser url f =
    let
      slug = fromMaybe "" (getQueryParam "user" url)
    in
      case find (\c -> c.slug == slug) contexts of
        Nothing -> do
          Log.warn $ "Unknown user: " <> show slug
          serveNotFound res
        Just ctx ->
          f ctx

serveIndex :: String -> Response -> Effect Unit
serveIndex slug res = do
  setHeader "Content-Type" "text/html" (toOutgoingMessage res)
  setStatusCode 200 res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 (indexHtml slug)
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
parseFilterField "label" = Just FilterLabel
parseFilterField "year" = Just FilterYear
parseFilterField "genre" = Just FilterGenre
parseFilterField _ = Nothing

sanitizeKey :: String -> String
sanitizeKey = replace re1 "_" >>> replace re2 "_"
  where
  re1 = unsafeRegex "[^a-z0-9.-]" (parseFlags "gi")
  re2 = unsafeRegex "_{2,}" (parseFlags "g")

-- Fetch the Last.fm image URL for an artist/release (no caching, no serving).
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

-- Fetch the Discogs image URL for an artist/release (no caching, no serving).
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
    result <- try $ fetch searchUrl { method: GET, headers: { "User-Agent": "ScrobblerPureScript/1.0", "Authorization": "Discogs token=" <> t } }
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

type CoverSource =
  { name :: String
  , s3Key :: String
  , findUrl :: Aff (Maybe String)
  }

coverSources :: String -> String -> String -> UserConfig -> Array CoverSource
coverSources mbid artist release cfg =
  let
    safeArtist = sanitizeKey artist
    safeRelease = sanitizeKey release
  in
    [ { name: "caa"
      , s3Key: "covers/caa/" <> sanitizeKey mbid <> ".jpg"
      , findUrl:
          if mbid == "" then pure Nothing
          else pure $ Just $ "https://coverartarchive.org/release/" <> mbid <> "/front-250"
      }
    , { name: "lastfm"
      , s3Key: "covers/lastfm/" <> safeArtist <> "-" <> safeRelease <> ".jpg"
      , findUrl:
          if artist == "" || release == "" then pure Nothing
          else fetchLastfmCoverUrl cfg artist release
      }
    , { name: "discogs"
      , s3Key: "covers/discogs/" <> safeArtist <> "-" <> safeRelease <> ".jpg"
      , findUrl:
          if artist == "" || release == "" then pure Nothing
          else fetchDiscogsCoverUrl cfg artist release
      }
    ]

serveCover :: UserConfig -> String -> URL -> Response -> Effect Unit
serveCover cfg slug url res = launchAff_ do
  let
    mbid = fromMaybe "" (getQueryParam "mbid" url)
    artist = fromMaybe "" (getQueryParam "artist" url)
    release = fromMaybe "" (getQueryParam "release" url)
    s3cfg = s3ConfigFromUser cfg

  served <- foldM (trySource s3cfg) false (coverSources mbid artist release cfg)
  unless served $ liftEffect $ serveNotFound res

  where
  trySource _ true _ = pure true
  trySource s3cfg false { name, s3Key, findUrl } = do
    cached <- checkS3 s3cfg s3Key
    if cached then do
      Log.info $ "Serving " <> name <> " cover from S3: " <> s3Key
      liftEffect $ Metrics.incCoverRequest slug name "s3_hit"
      serveS3 s3cfg s3Key res
      pure true
    else do
      mUrl <- findUrl
      case mUrl of
        Nothing ->
          pure false
        Just urlStr -> do
          success <- tryProxyAndCache s3cfg urlStr s3Key res
          liftEffect $
            if success then Metrics.incCoverRequest slug name "fetch"
            else Metrics.incCoverRequest slug name "miss"
          pure success

  checkS3 s3cfg s3Key
    | not cfg.coverCacheEnabled = pure false
    | otherwise = do
        result <- try $ existsInS3 s3cfg s3Key
        pure $ case result of
          Right b -> b
          Left _ -> false

  serveS3 s3cfg s3Key response = liftEffect $ do
    setStatusCode 302 response
    setHeader "Location" (getS3Url s3cfg s3Key) (toOutgoingMessage response)
    end (toWriteable (toOutgoingMessage response))

  tryProxyAndCache s3cfg urlStr s3Key response = do
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
        when cfg.coverCacheEnabled $ void $ forkAff $ do
          uploadResult <- try $ uploadToS3 s3cfg s3Key (unsafeCoerce buf) contentType
          case uploadResult of
            Right _ -> Log.info $ "Cached to S3: " <> s3Key
            Left err -> Log.error $ "S3 upload failed: " <> Exception.message err
        pure true
      _ ->
        pure false

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

fetchCosineSimilar :: String -> UserConfig -> String -> Aff String
fetchCosineSimilar slug cfg query = do
  let apiKey = fromMaybe "" cfg.cosineApiKey
  if apiKey == "" then do
    Log.warn "cosineApiKey not configured for similar tracks"
    liftEffect $ Metrics.incCosineRequest slug "not_configured"
    pure "{\"data\":{\"similar_tracks\":[]},\"success\":true}"
  else do
    let headers = { "User-Agent": "corpus/1.0 +https://codeberg.org/mtmn/corpus", "Authorization": "Bearer " <> apiKey }
    let searchUrl = "https://cosine.club/api/v1/search?q=" <> (fromMaybe "" $ encodeURIComponent query) <> "&limit=1"
    Log.info $ "Cosine Club: searching for: " <> query
    searchResult <- try $ fetch searchUrl { method: GET, headers: headers }
    case searchResult of
      Left err -> do
        liftEffect $ Metrics.incCosineRequest slug "error"
        throwError err
      Right searchRes ->
        if searchRes.status == 429 then do
          Log.warn "Cosine Club: rate limited on search"
          liftEffect $ Metrics.incCosineRequest slug "rate_limited"
          throwError (Exception.error "Rate limit exceeded")
        else if searchRes.status /= 200 then do
          Log.warn $ "Cosine Club: search returned " <> show searchRes.status
          liftEffect $ Metrics.incCosineRequest slug "error"
          throwError (Exception.error "Search API error")
        else do
          searchBody <- searchRes.text
          let
            mTrackId = do
              json <- hush $ parseJson searchBody
              obj <- toObject json
              arr <- Object.lookup "data" obj >>= toArray
              first <- arr !! 0
              firstObj <- toObject first
              Object.lookup "id" firstObj >>= toString
          case mTrackId of
            Nothing -> do
              Log.info $ "Cosine Club: track not indexed: " <> query
              liftEffect $ Metrics.incCosineRequest slug "not_indexed"
              pure "{\"data\":{\"similar_tracks\":[]},\"success\":true}"
            Just trackId -> do
              let similarUrl = "https://cosine.club/api/v1/tracks/" <> trackId <> "/similar?limit=10"
              Log.info $ "Cosine Club: fetching similar for ID " <> trackId
              similarResult <- try $ fetch similarUrl { method: GET, headers: headers }
              case similarResult of
                Left err -> do
                  liftEffect $ Metrics.incCosineRequest slug "error"
                  throwError err
                Right similarRes ->
                  if similarRes.status == 429 then do
                    Log.warn "Cosine Club: rate limited on similar"
                    liftEffect $ Metrics.incCosineRequest slug "rate_limited"
                    throwError (Exception.error "Rate limit exceeded")
                  else if similarRes.status /= 200 then do
                    Log.warn $ "Cosine Club: similar API returned " <> show similarRes.status
                    liftEffect $ Metrics.incCosineRequest slug "error"
                    throwError (Exception.error "Similar API error")
                  else do
                    liftEffect $ Metrics.incCosineRequest slug "success"
                    similarRes.text

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

serveSimilar :: String -> UserConfig -> URL -> Response -> Effect Unit
serveSimilar slug cfg url res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  launchAff_ do
    let artist = fromMaybe "" (getQueryParam "artist" url)
    let track = fromMaybe "" (getQueryParam "track" url)
    if artist == "" || track == "" then
      liftEffect $ serveBadRequest res "Artist and track parameters are required"
    else do
      let query = artist <> " - " <> track
      result <- try $ fetchCosineSimilar slug cfg query

      case result of
        Left err -> do
          Log.error $ "Cosine Club API error: " <> Exception.message err
          liftEffect $ serveError res 502 "Bad Gateway" "Failed to fetch similar tracks"
        Right responseBody -> do
          liftEffect $ do
            setStatusCode 200 res
            let w = toWriteable (toOutgoingMessage res)
            void $ writeString w UTF8 responseBody
            end w

type MbData = { genre :: Maybe String, label :: Maybe String, year :: Maybe Int }

fetchMusicBrainzRelease :: String -> Aff (Maybe MbData)
fetchMusicBrainzRelease mbid = do
  let url = "https://musicbrainz.org/ws/2/release/" <> mbid <> "?inc=genres+labels+release-groups&fmt=json"
  result <- try $ fetch url { method: GET, headers: { "User-Agent": "corpus/1.0 +https://codeberg.org/mtmn/corpus" } }
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
              String.split (Pattern "-") dateStr !! 0 >>= fromString
          Log.info $ "Enriched " <> mbid <> ": genre=" <> show genre <> " label=" <> show label <> " year=" <> show year

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

-- Explicit apiKey parameter — no env read.
fetchLastfmGenre :: Maybe String -> String -> String -> Aff (Maybe String)
fetchLastfmGenre Nothing _ _ = do
  Log.warn "lastfmApiKey not configured for genre fallback"
  pure Nothing
fetchLastfmGenre (Just k) artist release = do
  let searchUrl = "https://ws.audioscrobbler.com/2.0/?method=album.getinfo&artist=" <> (fromMaybe "" $ encodeURIComponent artist) <> "&album=" <> (fromMaybe "" $ encodeURIComponent release) <> "&format=json" <> "&api_key=" <> k
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

-- Explicit token parameter — no env read.
fetchDiscogsGenre :: Maybe String -> String -> String -> Aff (Maybe String)
fetchDiscogsGenre Nothing _ _ = do
  Log.warn "discogsToken not configured for genre fallback"
  pure Nothing
fetchDiscogsGenre (Just t) artist release = do
  let queryStr = artist <> " " <> release
  let searchUrl = "https://api.discogs.com/database/search?q=" <> (fromMaybe "" $ encodeURIComponent queryStr) <> "&type=release&per_page=1"
  Log.info $ "Fetching Discogs genre for: " <> queryStr
  result <- try $ fetch searchUrl { method: GET, headers: { "User-Agent": "ScrobblerPureScript/1.0", "Authorization": "Discogs token=" <> t } }
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

type GenreSource =
  { name :: String
  , enabled :: Boolean
  , fetch :: Aff (Maybe String)
  }

-- Try each source in order, stopping at the first that returns Just.
-- Records found/not_found metrics only for sources that are enabled and queried.
fetchFallbackGenre :: String -> Array GenreSource -> Aff (Maybe String)
fetchFallbackGenre slug = foldM trySource Nothing
  where
  trySource (Just g) _ = pure (Just g)
  trySource Nothing { name, enabled, fetch }
    | not enabled = pure Nothing
    | otherwise = do
        result <- fetch
        liftEffect $ case result of
          Just _ -> Metrics.incEnrichmentFetch slug name "found"
          Nothing -> Metrics.incEnrichmentFetch slug name "not_found"
        pure result

enrichMetadata :: Connection -> UserConfig -> String -> Aff Unit
enrichMetadata conn cfg slug = forever do
  unenrichedMbids <- getUnenrichedMbids conn 10
  emptyGenreMbids <- getEmptyGenreMbids conn 10
  let allMbids = unenrichedMbids <> emptyGenreMbids

  liftEffect $ Metrics.setEnrichmentQueueSize slug "unenriched" (length unenrichedMbids)
  liftEffect $ Metrics.setEnrichmentQueueSize slug "empty_genre" (length emptyGenreMbids)

  if length allMbids == 0 then
    delay (Milliseconds 60000.0)
  else do
    Log.info $ "Processing " <> show (length unenrichedMbids) <> " unenriched + " <> show (length emptyGenreMbids) <> " empty genre releases"
    artistReleaseMap <- getArtistReleasesByMbids conn allMbids
    for_ allMbids \mbid -> do
      delay (Milliseconds 1100.0)
      result <- try $ fetchMusicBrainzRelease mbid
      case result of
        Left err -> do
          Log.error $ "Enrichment error: " <> Exception.message err
          liftEffect $ Metrics.incEnrichmentFetch slug "musicbrainz" "error"
        Right Nothing -> do
          liftEffect $ Metrics.incEnrichmentFetch slug "musicbrainz" "retry"
          upsertReleaseMetadata conn mbid Nothing Nothing Nothing
          touchGenreCheckedAt conn mbid
        Right (Just mbdata) -> do
          liftEffect $ Metrics.incEnrichmentFetch slug "musicbrainz" "success"
          case mbdata.genre of
            Just _ ->
              upsertReleaseMetadata conn mbid mbdata.genre mbdata.label mbdata.year
            Nothing -> do
              let artistRelease = Object.lookup mbid artistReleaseMap
              case artistRelease of
                Just { artist, release } -> do
                  let
                    sources =
                      [ { name: "lastfm", enabled: isJust cfg.lastfmApiKey, fetch: fetchLastfmGenre cfg.lastfmApiKey artist release }
                      , { name: "discogs", enabled: isJust cfg.discogsToken, fetch: fetchDiscogsGenre cfg.discogsToken artist release }
                      ]
                  finalGenre <- fetchFallbackGenre slug sources
                  upsertReleaseMetadata conn mbid finalGenre mbdata.label mbdata.year
                  case finalGenre of
                    Just genre ->
                      Log.info $ "Added fallback genre for " <> mbid <> ": " <> genre
                    Nothing -> do
                      Log.info $ "No genre found in any source for " <> mbid
                      touchGenreCheckedAt conn mbid
                Nothing -> do
                  Log.warn $ "No artist/release info found for MBID " <> mbid <> ", cannot use fallback sources"
                  upsertReleaseMetadata conn mbid mbdata.genre mbdata.label mbdata.year
                  touchGenreCheckedAt conn mbid

-- Initialise one user: connect DB, start sync loops, return a UserContext.
startUser :: UserEntry -> Aff UserContext
startUser { slug, config } = do
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
  void $ forkAff $ enrichMetadata conn config slug
  when config.backupEnabled $ void $ forkAff $
    backupDb conn config.databaseFile (s3ConfigFromUser config)
      (toNumber config.backupIntervalHours * 3600000.0)
      slug

  pure { conn, writeLock, config, slug }

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
