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
import Data.Either (Either(..))
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
import Data.Array ((!!), length, uncons, mapMaybe, find)
import Data.Tuple (Tuple(..))
import Data.Foldable (for_)
import Data.Traversable (traverse)
import Db (Connection, connect, initDb, upsertScrobble, getScrobbles, checkExists, getOldestTs, initReleaseMetadata, getUnenrichedMbids, getEmptyGenreMbids, getArtistReleaseByMbid, upsertReleaseMetadata, touchGenreCheckedAt, getStats, ping, backupDb, withTransaction)
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

fetchListenBrainzData :: String -> Int -> Aff String
fetchListenBrainzData username count = withRetry "ListenBrainz fetch" $ makeAff \callback -> do
  let url = listenBrainzUrl username <> "?count=" <> show count
  req <- HTTPS.get url

  req # on_ Client.responseH \res -> do
    launchAff_ do
      body <- readableToStringUtf8 (IM.toReadable res)
      let statusCode = IM.statusCode res
      liftEffect $
        if statusCode == 200 then
          callback (Right body)
        else
          callback (Left $ Exception.error $ "ListenBrainz API returned status " <> show statusCode)

  let errorH = EventHandle "error" mkEffectFn1
  on_ errorH
    ( \err -> do
        callback (Left err)
    )
    (unsafeCoerce req)

  pure nonCanceler

fetchListenBrainzDataBefore :: String -> Int -> Aff String
fetchListenBrainzDataBefore username maxTs = withRetry "ListenBrainz fetch" $ makeAff \callback -> do
  let url = listenBrainzUrl username <> "?count=100&max_ts=" <> show maxTs
  req <- HTTPS.get url

  req # on_ Client.responseH \res -> do
    launchAff_ do
      body <- readableToStringUtf8 (IM.toReadable res)
      let statusCode = IM.statusCode res
      liftEffect $
        if statusCode == 200 then
          callback (Right body)
        else
          callback (Left $ Exception.error $ "ListenBrainz API returned status " <> show statusCode)

  let errorH = EventHandle "error" mkEffectFn1
  on_ errorH
    ( \err -> do
        callback (Left err)
    )
    (unsafeCoerce req)

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
    url = "https://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&user="
      <> (fromMaybe lfmUser $ encodeURIComponent lfmUser)
      <> "&api_key="
      <> apiKey
      <> "&format=json&limit=200&page="
      <> show page
      <> toParam
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
    result <- try $ fetchListenBrainzData username 100
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
            let allExist = hitCount == length listens && length listens > 0
            if allExist || length listens == 0 || not initialSyncEnabled then do
              when (added > 0) $ Log.info $ "ListenBrainz sync complete. Added " <> show added <> " new scrobbles."
              liftEffect $ Metrics.incSyncRuns slug "listenbrainz" "success"
              when (added > 0) $ liftEffect $ Metrics.incSyncScrobbles slug "listenbrainz" added
              liftEffect $ Metrics.setSyncLastSuccess slug "listenbrainz"
            else do
              total <- paginateUntilDone 2 minTs added
              Log.info $ "ListenBrainz sync complete. Added " <> show total <> " new scrobbles."
              liftEffect $ Metrics.incSyncRuns slug "listenbrainz" "success"
              when (total > 0) $ liftEffect $ Metrics.incSyncScrobbles slug "listenbrainz" total
              liftEffect $ Metrics.setSyncLastSuccess slug "listenbrainz"
      Left err -> do
        Log.error $ "Sync fetch error: " <> Exception.message err
        liftEffect $ Metrics.incSyncRuns slug "listenbrainz" "error"

  paginateUntilDone batchNum minTs acc = case minTs of
    Nothing -> pure acc
    Just ts -> do
      Log.info $ "Fetching ListenBrainz batch " <> show batchNum <> " (before " <> show ts <> ")..."
      result <- try $ fetchListenBrainzDataBefore username ts
      case result of
        Right body -> do
          case parseJson body >>= decodeJson of
            Left err -> do
              Log.error $ "Sync parse error: " <> show err
              pure acc
            Right (ListenBrainzResponse { payload: Payload { listens } }) -> do
              Tuple added (Tuple newMinTs hitCount) <- withTransaction conn writeLock (processListens listens)
              Log.info $ "ListenBrainz batch " <> show batchNum <> ": added " <> show added <> ", " <> show hitCount <> " already present."
              let allExist = hitCount == length listens && length listens > 0
              if allExist || length listens == 0 then do
                pure (acc + added)
              else do
                paginateUntilDone (batchNum + 1) newMinTs (acc + added)
        Left err -> do
          Log.error $ "Sync fetch error: " <> Exception.message err
          pure acc

  processListens listens = do
    syncRecursive 0 Nothing 0 listens

  syncRecursive acc minTs hitCount listens = case uncons listens of
    Nothing -> pure $ Tuple acc (Tuple minTs hitCount)
    Just { head: l@(Listen { listenedAt: Just ts, trackMetadata: (TrackMetadata _) }), tail } -> do
      exists <- checkExists conn ts
      if exists then do
        syncRecursive acc (Just ts) (hitCount + 1) tail
      else do
        upsertScrobble conn l
        syncRecursive (acc + 1) (Just ts) hitCount tail
    Just { head: _, tail } -> do
      Log.warn "Skipping scrobble without timestamp"
      syncRecursive acc minTs hitCount tail

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
      allExist = hitCount == length validTracks && length validTracks > 0
    if allExist || totalPages <= 1 || not initialSyncEnabled then do
      when (added > 0) $ Log.info $ "Last.fm sync complete. Added " <> show added <> " new scrobbles."
      liftEffect $ Metrics.incSyncRuns slug "lastfm" "success"
      when (added > 0) $ liftEffect $ Metrics.incSyncScrobbles slug "lastfm" added
      liftEffect $ Metrics.setSyncLastSuccess slug "lastfm"
    else do
      total <- paginateLastfmUntilDone 2 totalPages Nothing added
      Log.info $ "Last.fm sync complete. Added " <> show total <> " new scrobbles."
      liftEffect $ Metrics.incSyncRuns slug "lastfm" "success"
      when (total > 0) $ liftEffect $ Metrics.incSyncScrobbles slug "lastfm" total
      liftEffect $ Metrics.setSyncLastSuccess slug "lastfm"

  paginateLastfmUntilDone page totalPages mTo acc
    | page > totalPages = pure acc
    | otherwise = do
        when initialSyncEnabled $ Log.info $ "Fetching Last.fm page " <> show page <> "/" <> show totalPages <> "..."
        { tracks } <- fetchLastfmPage apiKey lfmUser page mTo
        Tuple added hitCount <- withTransaction conn writeLock (processLastfmTracks tracks)
        Log.info $ "Last.fm page " <> show page <> "/" <> show totalPages <> ": added " <> show added <> ", " <> show hitCount <> " already present."
        let
          validTracks = mapMaybe lastfmTrackToListen tracks
          allExist = hitCount == length validTracks && length validTracks > 0
        if allExist || length tracks == 0 then pure (acc + added)
        else paginateLastfmUntilDone (page + 1) totalPages mTo (acc + added)

  performLastfmBackfill = do
    mOldest <- getOldestTs conn
    case mOldest of
      Nothing -> pure unit
      Just oldestTs -> do
        when initialSyncEnabled $ Log.info $ "Checking for Last.fm history before " <> show oldestTs <> "..."
        { tracks, totalPages } <- fetchLastfmPage apiKey lfmUser 1 (Just (oldestTs - 1))
        if length tracks == 0 then do
          when initialSyncEnabled $ Log.info "No older Last.fm history found."
          pure unit
        else do
          Log.info $ "Backfilling " <> show totalPages <> " pages of Last.fm history before " <> show oldestTs
          Tuple added hitCount <- withTransaction conn writeLock (processLastfmTracks tracks)
          Log.info $ "Last.fm backfill page 1/" <> show totalPages <> ": added " <> show added <> ", " <> show hitCount <> " already present."
          total <- paginateLastfmUntilDone 2 totalPages (Just (oldestTs - 1)) added
          Log.info $ "Last.fm backfill complete. Added " <> show total <> " older scrobbles."

  processLastfmTracks tracks = syncLastfmRecursive 0 0 (mapMaybe lastfmTrackToListen tracks)

  syncLastfmRecursive acc hitCount listens = case uncons listens of
    Nothing -> pure $ Tuple acc hitCount
    Just { head: l@(Listen { listenedAt: Just ts }), tail } -> do
      exists <- checkExists conn ts
      if exists then syncLastfmRecursive acc (hitCount + 1) tail
      else do
        upsertScrobble conn l
        syncLastfmRecursive (acc + 1) hitCount tail
    Just { head: _, tail } -> syncLastfmRecursive acc hitCount tail

lfSyncLoop :: Connection -> String -> String -> String -> AVar Unit -> Boolean -> Aff Unit
lfSyncLoop conn apiKey lfmUser slug writeLock initialSyncEnabled = forever do
  delay (Milliseconds 60000.0)
  lfSyncOnce conn apiKey lfmUser slug writeLock initialSyncEnabled

-- Build the per-user index HTML, inlining the slug for the Elm app.
indexHtml :: String -> String
indexHtml userSlug =
  """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>scrobbler</title>
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

        .stat-row.clickable {
            cursor: pointer;
        }

        .stat-row.clickable:hover .stat-name {
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

        .period-selector {
            display: flex;
            gap: 6px;
            margin-bottom: 16px;
        }

        .period-btn {
            background: none;
            border: 1px solid #50447f;
            color: #9fbfe7;
            padding: 4px 12px;
            border-radius: 3px;
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
        }

        .period-btn:hover {
            color: #ffffff;
            border-color: #ffffff;
        }

        .period-btn.active {
            background: #50447f;
            color: #ffffff;
            border-color: #50447f;
        }

        .custom-range {
            display: flex;
            gap: 8px;
            margin-top: 8px;
            align-items: center;
        }

        .custom-range-input {
            background: #521e40;
            border: 1px solid #50447f;
            color: #ffffff;
            padding: 4px 8px;
            border-radius: 3px;
            font-family: inherit;
            font-size: 12px;
            width: 220px;
        }

        .custom-range-input::placeholder {
            color: #9fbfe7;
            opacity: 0.7;
        }

        .custom-range-input:focus {
            outline: none;
            border-color: #ffffff;
        }

        .custom-range-input.error {
            border-color: #ff6b6b;
        }

        .custom-range-error {
            color: #ff6b6b;
            font-size: 12px;
            margin-top: 4px;
        }
    </style>
</head>
<body>
    <div id="app"></div>
    <script src="/client.js"></script>
    <script>
        var userSlug = '""" <> userSlug <>
    """';
        var app = Elm.Client.init({
            node: document.getElementById('app'),
            flags: { search: window.location.search, userSlug: userSlug }
        });
        app.ports.pushUrl.subscribe(function(url) {
            var prefix = userSlug ? '/~' + userSlug : '';
            history.pushState({}, '', prefix + url);
        });
    </script>
</body>
</html>"""

normalizePath :: String -> String
normalizePath path = case stripPrefix (Pattern "/~") path of
  Just _ -> "/~:slug"
  Nothing -> path

-- Request handler
-- API endpoints (/proxy, /stats, /cover, /healthz) select the user via ?user=<slug>.
-- Index pages are served at / (root user) and /~<slug> (named users).
handleRequest :: Array UserContext -> Request -> Response -> Effect Unit
handleRequest contexts req res = do
  let method = IM.method req
  let rawUrl = IM.url req
  case URL.fromRelative rawUrl "http://localhost" of
    Nothing -> serveNotFound res
    Just url -> do
      let path = URL.pathname url
      Metrics.wrapRequest method (normalizePath path) Log.info req res do
        case path of
          "/client.js" -> serveClientJs res
          "/favicon.png" -> serveAsset "image/png" "assets/favicon.png" res
          "/" -> serveIndex "" res
          "/metrics" -> serveMetrics res
          "/proxy" -> withUser url \ctx -> serveProxy ctx.conn url res
          "/stats" -> withUser url \ctx -> serveStats ctx.conn url res
          "/cover" -> withUser url \ctx -> serveCover ctx.config ctx.slug url res
          "/healthz" -> withUser url \ctx -> serveHealthz ctx.conn res
          _ -> case stripPrefix (Pattern "/~") path of
            Just slug -> serveIndex slug res
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
        Just ctx -> f ctx

serveIndex :: String -> Response -> Effect Unit
serveIndex slug res = do
  setHeader "Content-Type" "text/html" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
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

serveCover :: UserConfig -> String -> URL -> Response -> Effect Unit
serveCover cfg slug url res = do
  launchAff_ do
    let mbid = fromMaybe "" (getQueryParam "mbid" url)
    let artistStr = fromMaybe "" (getQueryParam "artist" url)
    let releaseStr = fromMaybe "" (getQueryParam "release" url)
    let s3cfg = s3ConfigFromUser cfg

    if mbid /= "" then do
      let safeMbid = sanitizeKey mbid
      let s3Key = "covers/caa/" <> safeMbid <> ".jpg"
      cached <- checkS3 s3cfg s3Key
      if cached then do
        Log.info $ "Serving CAA cover from S3: " <> s3Key
        liftEffect $ Metrics.incCoverRequest slug "caa" "s3_hit"
        serveS3 s3cfg s3Key res
      else do
        Log.info $ "Fetching CAA cover: " <> mbid
        let caaUrl = "https://coverartarchive.org/release/" <> mbid <> "/front-250"
        success <- tryProxyAndCache s3cfg caaUrl s3Key res
        if success then
          liftEffect $ Metrics.incCoverRequest slug "caa" "fetch"
        else do
          liftEffect $ Metrics.incCoverRequest slug "caa" "miss"
          Log.info $ "CAA cover not found for " <> mbid <> ", falling back to Last.fm"
          tryLastfm s3cfg artistStr releaseStr res
    else do
      Log.info $ "No MBID provided, trying Last.fm for: " <> artistStr <> " - " <> releaseStr
      tryLastfm s3cfg artistStr releaseStr res

  where
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
      _ -> pure false

  tryLastfm s3cfg artist release response
    | artist == "" || release == "" = do
        Log.warn "Missing artist or release for Last.fm fallback"
        liftEffect $ serveNotFound response
    | otherwise = do
        let safeArtist = sanitizeKey artist
        let safeRelease = sanitizeKey release
        let s3Key = "covers/lastfm/" <> safeArtist <> "-" <> safeRelease <> ".jpg"
        cached <- checkS3 s3cfg s3Key
        if cached then do
          Log.info $ "Serving Last.fm cover from S3: " <> s3Key
          liftEffect $ Metrics.incCoverRequest slug "lastfm" "s3_hit"
          serveS3 s3cfg s3Key response
        else case cfg.lastfmApiKey of
          Nothing -> do
            Log.warn "lastfmApiKey not configured, falling back to Discogs"
            tryDiscogs s3cfg artist release response
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
                    success <- tryProxyAndCache s3cfg urlStr s3Key response
                    if success then
                      liftEffect $ Metrics.incCoverRequest slug "lastfm" "fetch"
                    else do
                      liftEffect $ Metrics.incCoverRequest slug "lastfm" "miss"
                      Log.info "Last.fm image proxy failed, falling back to Discogs"
                      tryDiscogs s3cfg artist release response
                  Nothing -> do
                    Log.info "No cover found on Last.fm, falling back to Discogs"
                    liftEffect $ Metrics.incCoverRequest slug "lastfm" "not_found"
                    tryDiscogs s3cfg artist release response
              _ -> do
                Log.info "Last.fm API request failed, falling back to Discogs"
                liftEffect $ Metrics.incCoverRequest slug "lastfm" "error"
                tryDiscogs s3cfg artist release response

  tryDiscogs s3cfg artist release response = do
    let safeArtist = sanitizeKey artist
    let safeRelease = sanitizeKey release
    let s3Key = "covers/discogs/" <> safeArtist <> "-" <> safeRelease <> ".jpg"
    cached <- checkS3 s3cfg s3Key
    if cached then do
      Log.info $ "Serving Discogs cover from S3: " <> s3Key
      liftEffect $ Metrics.incCoverRequest slug "discogs" "s3_hit"
      serveS3 s3cfg s3Key response
    else case cfg.discogsToken of
      Nothing -> do
        Log.warn "discogsToken not configured, cannot fallback further"
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
                success <- tryProxyAndCache s3cfg urlStr s3Key response
                if success then
                  liftEffect $ Metrics.incCoverRequest slug "discogs" "fetch"
                else do
                  liftEffect $ Metrics.incCoverRequest slug "discogs" "miss"
                  Log.info "Discogs image proxy failed"
                  liftEffect $ serveNotFound response
              Nothing -> do
                Log.info "No cover found on Discogs"
                liftEffect $ Metrics.incCoverRequest slug "discogs" "not_found"
                liftEffect $ serveNotFound response
          _ -> do
            Log.info "Discogs API request failed"
            liftEffect $ Metrics.incCoverRequest slug "discogs" "error"
            liftEffect $ serveNotFound response

serveProxy :: Connection -> URL -> Response -> Effect Unit
serveProxy db url res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Methods" "GET, POST, OPTIONS" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Headers" "*" (toOutgoingMessage res)

  launchAff_ do
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
  setHeader "Cache-Control" "public, max-age=86400" (toOutgoingMessage res)
  launchAff_ do
    result <- try $ FSA.readFile path
    liftEffect $ case result of
      Right buf -> do
        setStatusCode 200 res
        let w = toWriteable (toOutgoingMessage res)
        void $ write w buf
        end w
      Left _ -> serveNotFound res

serveHealthz :: Connection -> Response -> Effect Unit
serveHealthz db res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
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
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  setStatusCode 404 res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 "Not Found"
  end w

serveStats :: Connection -> URL -> Response -> Effect Unit
serveStats db url res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
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
              case uncons (String.split (Pattern "-") dateStr) of
                Just { head } -> fromString head
                Nothing -> Nothing
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

-- Explicit token parameter — no env read.
fetchDiscogsGenre :: Maybe String -> String -> String -> Aff (Maybe String)
fetchDiscogsGenre Nothing _ _ = do
  Log.warn "discogsToken not configured for genre fallback"
  pure Nothing
fetchDiscogsGenre (Just t) artist release = do
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
    for_ allMbids \mbid -> do
      delay (Milliseconds 1100.0)
      result <- try $ fetchMusicBrainzRelease mbid
      case result of
        Left err -> do
          Log.error $ "Enrichment error: " <> Exception.message err
          liftEffect $ Metrics.incEnrichmentFetch slug "musicbrainz" "error"
        Right Nothing -> do
          liftEffect $ Metrics.incEnrichmentFetch slug "musicbrainz" "retry"
          pure unit
        Right (Just mbdata) -> do
          liftEffect $ Metrics.incEnrichmentFetch slug "musicbrainz" "success"
          if mbdata.genre == Nothing then do
            artistRelease <- getArtistReleaseByMbid conn mbid
            case artistRelease of
              Just { artist, release } -> do
                lastfmGenre <- fetchLastfmGenre cfg.lastfmApiKey artist release
                when (isJust cfg.lastfmApiKey) $ liftEffect $ case lastfmGenre of
                  Just _ -> Metrics.incEnrichmentFetch slug "lastfm" "found"
                  Nothing -> Metrics.incEnrichmentFetch slug "lastfm" "not_found"
                finalGenre <- case lastfmGenre of
                  Just _ -> pure lastfmGenre
                  Nothing -> do
                    g <- fetchDiscogsGenre cfg.discogsToken artist release
                    when (isJust cfg.discogsToken) $ liftEffect $ case g of
                      Just _ -> Metrics.incEnrichmentFetch slug "discogs" "found"
                      Nothing -> Metrics.incEnrichmentFetch slug "discogs" "not_found"
                    pure g

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
            upsertReleaseMetadata conn mbid mbdata.genre mbdata.label mbdata.year

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

  -- Run initial syncs in parallel, then join before starting loops.
  -- Both syncs share the write lock, so their transactions are serialized.
  lbFiber <- case config.listenbrainzUser of
    Just username -> Just <$> forkAff (lbSyncOnce conn username slug writeLock config.initialSync)
    Nothing -> pure Nothing
  lfFiber <- case config.lastfmUser, config.lastfmApiKey of
    Just lfmUser, Just apiKey -> Just <$> forkAff (lfSyncOnce conn apiKey lfmUser slug writeLock config.initialSync)
    _, _ -> pure Nothing
  for_ lbFiber joinFiber
  for_ lfFiber joinFiber

  -- Background loops
  void $ forkAff $ enrichMetadata conn config slug
  for_ config.listenbrainzUser \username ->
    void $ forkAff $ lbSyncLoop conn username slug writeLock config.initialSync
  case config.lastfmUser, config.lastfmApiKey of
    Just lfmUser, Just apiKey -> void $ forkAff $ lfSyncLoop conn apiKey lfmUser slug writeLock config.initialSync
    _, _ -> pure unit
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
          server # on_ Server.requestH (handleRequest contexts)
          let netServer = Server.toNetServer server

          netServer # on_ listeningH do
            Log.info $ "Server is running on port " <> show appConfig.port

          listenTcp netServer { host: "127.0.0.1", port: appConfig.port, backlog: 128 }
