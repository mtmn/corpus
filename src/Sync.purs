module Sync
  ( listenBrainzUrl
  , lastfmTrackToListen
  , parseLastfmResponse
  , fetchLastfmPage
  , lbSync
  , lbSyncLoop
  , lfSync
  , lfSyncLoop
  ) where

import Prelude

import Control.Monad.Rec.Class (forever)
import Data.Argonaut (decodeJson, parseJson)
import Data.Argonaut.Core (Json, stringify)
import Data.Array (length, mapMaybe, null)
import Data.Either (Either(..))
import Data.Foldable (foldM, for_)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String (Pattern(..), stripPrefix)
import Data.Time.Duration (Milliseconds(..))
import Db (Connection, checkExists, getOldestTs, upsertScrobble, withTransaction)
import Effect.Aff (Aff, delay, launchAff_, makeAff, nonCanceler, throwError, try)
import Effect.Aff.AVar (AVar)
import Effect.Aff.Retry (RetryStatus(..), exponentialBackoff, limitRetries, recovering)
import Effect.Class (liftEffect)
import Effect.Exception (error, message)
import Effect.Uncurried (mkEffectFn1)
import Fetch (fetch, Method(GET))
import Fetch.Argonaut.Json (fromJson)
import JSURI (encodeURIComponent)
import Log as Log
import Metrics as Metrics
import Node.EventEmitter (EventHandle(..), on_)
import Node.HTTP.ClientRequest as Client
import Node.HTTP.IncomingMessage as IM
import Node.HTTPS as HTTPS
import Node.Stream.Aff (readableToStringUtf8)
import Types (Listen(..), ListenBrainzResponse(..), MbidMapping(..), Payload(..), TrackMetadata(..), LastfmResponse(..), LastfmRecentTracks(..), LastfmAttr(..), LastfmTracks(..), LastfmArtist(..), LastfmAlbum(..), LastfmDate(..), LastfmTrack(..))
-- | Cast required due to a gap in the node-http FFI bindings:
-- | the request object lacks an "error" event emitter type.
import Unsafe.Coerce (unsafeCoerce)

-- | Result of processing a batch of listens/scrobbles.
type SyncResult =
  { added :: Int
  , hitCount :: Int
  , minTs :: Maybe Int
  }

-- | Process a batch of listens: check existence, insert new ones, track stats.
-- | When trackMinTs is true, the minimum timestamp is tracked (for cursor-based pagination).
processTracks :: Connection -> Array Listen -> Boolean -> Aff SyncResult
processTracks conn listens trackMinTs = do
  foldM step { added: 0, hitCount: 0, minTs: Nothing } listens
  where
  step :: SyncResult -> Listen -> Aff SyncResult
  step s l@(Listen { listenedAt: Just ts }) = do
    exists <- checkExists conn ts
    if exists then do
      let nextMinTs = if trackMinTs then Just ts else s.minTs
      pure $ s { added = s.added, hitCount = s.hitCount + 1, minTs = nextMinTs }
    else do
      upsertScrobble conn l
      let nextMinTs = if trackMinTs then Just ts else s.minTs
      pure $ s { added = s.added + 1, hitCount = s.hitCount, minTs = nextMinTs }
  step s (Listen { listenedAt: Nothing }) = do
    Log.warn "Skipping scrobble without timestamp"
    pure s

-- | Wraps unsafeCoerce for attaching error handlers to HTTP requests.
-- | This is the only legitimate use of unsafeCoerce in this module.
castRequestForError :: forall a. a -> a
castRequestForError = unsafeCoerce

listenBrainzUrl :: String -> String
listenBrainzUrl username = "https://api.listenbrainz.org/1/user/" <> username <> "/listens"

-- | Retry an action with exponential backoff, but only for transient errors.
-- | Parse errors and other permanent failures are not retried.
withRetry :: forall a. String -> Aff a -> Aff a
withRetry label action = recovering policy [ \_ err -> pure $ isTransientError err ] \(RetryStatus status) -> do
  when (status.iterNumber > 0)
    $ Log.warn
    $ label <> " failed, retry attempt " <> show status.iterNumber
  action
  where
  policy = exponentialBackoff (Milliseconds 1000.0) <> limitRetries 5
  isTransientError err = not isPermanent
    where
    msg = message err
    isPermanent =
      msg == "Last.fm: Failed to parse JSON response"
        || startsWith "Last.fm API returned status" msg
        || startsWith "ListenBrainz API returned status" msg
  startsWith prefix str = case stripPrefix (Pattern prefix) str of
    Just _ -> true
    Nothing -> false

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
            callback (Left $ error $ "ListenBrainz API returned status " <> show (IM.statusCode res))

  let errorH = EventHandle "error" mkEffectFn1
  on_ errorH (\err -> callback (Left err)) (castRequestForError req)

  pure nonCanceler

fetchLastfmPage :: String -> String -> Int -> Maybe Int -> Aff { tracks :: Array Json, totalPages :: Int }
fetchLastfmPage apiKey lfmUser page mTo = withRetry "Last.fm fetch" do
  let
    toParam = case mTo of
      Just ts -> "&to=" <> show ts
      Nothing -> ""
    baseUrl = "https://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&user="
      <> (fromMaybe lfmUser $ encodeURIComponent lfmUser)
      <> "&format=json&limit=200&page="
      <> show page
      <> toParam
    url = baseUrl <> "&api_key=" <> apiKey
  let headers = { "User-Agent": "corpus/1.0 (+https://sr.ht/~mtmn/corpus)" }
  fr <- fetch url { method: GET, headers }
  if fr.status == 200 then do
    json <- fromJson fr.json
    case parseLastfmResponse json of
      Just result -> do
        pure result
      Nothing -> do
        Log.error $ "Last.fm: Failed to parse JSON response: " <> stringify json
        throwError $ error "Last.fm: Failed to parse JSON response"
  else do
    throwError $ error ("Last.fm API returned status " <> show fr.status)

parseLastfmResponse :: Json -> Maybe { tracks :: Array Json, totalPages :: Int }
parseLastfmResponse json = case decodeJson json of
  Right (LastfmResponse { recenttracks: LastfmRecentTracks { track, attr: LastfmAttr { totalPages } } }) ->
    let
      tracks = case track of
        LastfmTrackArray' ts -> ts
        LastfmTrackSingle' t -> [ t ]
    in
      Just { tracks, totalPages: totalPages }
  Left _ -> Nothing

lastfmTrackToListen :: Json -> Maybe Listen
lastfmTrackToListen json = case decodeJson json of
  Right (LastfmTrack { name, artist: LastfmArtist { text: artistName }, album, date }) -> do
    ts <- date >>= \(LastfmDate { uts }) -> Just uts
    let
      releaseName = album >>= \(LastfmAlbum { text }) -> text
      releaseMbid = album >>= \(LastfmAlbum { mbid }) -> if mbid == "" then Nothing else Just mbid
    pure $ Listen
      { listenedAt: Just ts
      , trackMetadata: TrackMetadata
          { trackName: Just name
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
  Left _ -> Nothing

recordSyncSuccess :: String -> String -> Int -> Aff Unit
recordSyncSuccess slug source n = do
  liftEffect $ Metrics.incSyncRuns slug source "success"
  when (n > 0) $ liftEffect $ Metrics.incSyncScrobbles slug source n
  liftEffect $ Metrics.setSyncLastSuccess slug source

lbSync :: Connection -> String -> String -> AVar Unit -> Aff Unit
lbSync conn username slug writeLock = void do
  Log.info $ "Starting ListenBrainz sync for " <> username
  result <- try $ fetchListenBrainzUrl (listenBrainzUrl username <> "?count=100")
  case result of
    Left err -> do
      Log.error $ "Sync fetch error: " <> message err
      liftEffect $ Metrics.incSyncRuns slug "listenbrainz" "error"
    Right body ->
      case parseJson body >>= decodeJson of
        Left err -> do
          Log.error $ "Sync parse error: " <> show err
          liftEffect $ Metrics.incSyncRuns slug "listenbrainz" "error"
        Right (ListenBrainzResponse { payload: Payload { listens } }) -> do
          syncResult <- withTransaction conn writeLock (processListens listens)
          let
            added = syncResult.added
            minTs = syncResult.minTs
            hitCount = syncResult.hitCount
          Log.info $ "ListenBrainz batch 1: added " <> show added <> ", " <> show hitCount <> " already present."
          let allExist = hitCount == length listens && not (null listens)
          if allExist || null listens then do
            when (added > 0) $ Log.info $ "ListenBrainz sync complete. Added " <> show added <> " new scrobbles."
            recordSyncSuccess slug "listenbrainz" added
          else do
            total <- paginateUntilDone 2 minTs added
            Log.info $ "ListenBrainz sync complete. Added " <> show total <> " new scrobbles."
            recordSyncSuccess slug "listenbrainz" total
  where
  paginateUntilDone batchNum minTs acc = case minTs of
    Nothing ->
      pure acc
    Just ts -> do
      Log.info $ "Fetching ListenBrainz batch " <> show batchNum <> " (before " <> show ts <> ")..."
      result <- try $ fetchListenBrainzUrl (listenBrainzUrl username <> "?count=100&max_ts=" <> show ts)
      case result of
        Left err -> do
          Log.error $ "Sync fetch error: " <> message err
          pure acc
        Right body ->
          case parseJson body >>= decodeJson of
            Left err -> do
              Log.error $ "Sync parse error: " <> show err
              pure acc
            Right (ListenBrainzResponse { payload: Payload { listens } }) -> do
              syncResult <- withTransaction conn writeLock (processListens listens)
              let
                added = syncResult.added
                newMinTs = syncResult.minTs
                hitCount = syncResult.hitCount
              Log.info $ "ListenBrainz batch " <> show batchNum <> ": added " <> show added <> ", " <> show hitCount <> " already present."
              let allExist = hitCount == length listens && not (null listens)
              if allExist || null listens then
                pure (acc + added)
              else
                paginateUntilDone (batchNum + 1) newMinTs (acc + added)

  processListens listens = processTracks conn listens true

lbSyncLoop :: Connection -> String -> String -> AVar Unit -> Aff Unit
lbSyncLoop conn username slug writeLock = forever do
  delay (Milliseconds 60000.0)
  lbSync conn username slug writeLock

lfSync :: Connection -> String -> String -> String -> AVar Unit -> Aff Unit
lfSync conn apiKey lfmUser slug writeLock = do
  void performLastfmSync
  void performLastfmBackfill
  where
  performLastfmSync = do
    Log.info $ "Starting Last.fm sync for " <> lfmUser
    res <- try $ fetchLastfmPage apiKey lfmUser 1 Nothing
    case res of
      Left err -> do
        Log.error $ "Last.fm sync fetch error: " <> message err
        liftEffect $ Metrics.incSyncRuns slug "lastfm" "error"
      Right { tracks, totalPages } -> do
        result <- withTransaction conn writeLock (processLastfmTracks tracks)
        let
          added = result.added
          hitCount = result.hitCount
        Log.info $ "Last.fm page 1/" <> show totalPages <> ": added " <> show added <> ", " <> show hitCount <> " already present."
        let
          validTracks = mapMaybe lastfmTrackToListen tracks
          allExist = hitCount == length validTracks && not (null validTracks)
        if allExist || totalPages <= 1 then do
          when (added > 0) $ Log.info $ "Last.fm sync complete. Added " <> show added <> " new scrobbles."
          recordSyncSuccess slug "lastfm" added
        else do
          total <- paginateLastfmUntilDone 2 totalPages Nothing added
          Log.info $ "Last.fm sync complete. Added " <> show total <> " new scrobbles."
          recordSyncSuccess slug "lastfm" total

  paginateLastfmUntilDone page totalPages mTo acc
    | page > totalPages = pure acc
    | otherwise = do
        Log.info $ "Fetching Last.fm page " <> show page <> "/" <> show totalPages <> "..."
        res <- try $ fetchLastfmPage apiKey lfmUser page mTo
        case res of
          Left err -> do
            Log.error $ "Last.fm sync fetch error: " <> message err
            pure acc
          Right { tracks } -> do
            result <- withTransaction conn writeLock (processLastfmTracks tracks)
            let
              added = result.added
              hitCount = result.hitCount
            Log.info $ "Last.fm page" <> show page <> "/" <> show totalPages <> ": added " <> show added <> ", " <> show hitCount <> " already present."
            let
              validTracks = mapMaybe lastfmTrackToListen tracks
              allExist = hitCount == length validTracks && not (null validTracks)
            if allExist || null tracks then pure (acc + added)
            else paginateLastfmUntilDone (page + 1) totalPages mTo (acc + added)

  performLastfmBackfill = do
    mOldest <- getOldestTs conn
    for_ mOldest \oldestTs -> do
      Log.info $ "Checking for Last.fm history before " <> show oldestTs <> "..."
      res <- try $ fetchLastfmPage apiKey lfmUser 1 (Just (oldestTs - 1))
      case res of
        Left err ->
          Log.error $ "Last.fm backfill fetch error: " <> message err
        Right { tracks, totalPages } ->
          if null tracks then
            Log.info "No older Last.fm history found."
          else do
            Log.info $ "Backfilling " <> show totalPages <> " pages of Last.fm history before " <> show oldestTs
            result <- withTransaction conn writeLock (processLastfmTracks tracks)
            let
              added = result.added
              hitCount = result.hitCount
            Log.info $ "Last.fm backfill page 1/" <> show totalPages <> ": added " <> show added <> ", " <> show hitCount <> " already present."
            total <- paginateLastfmUntilDone 2 totalPages (Just (oldestTs - 1)) added
            Log.info $ "Last.fm backfill complete. Added " <> show total <> " older scrobbles."

  processLastfmTracks tracks = processTracks conn (mapMaybe lastfmTrackToListen tracks) false

lfSyncLoop :: Connection -> String -> String -> String -> AVar Unit -> Aff Unit
lfSyncLoop conn apiKey lfmUser slug writeLock = forever do
  delay (Milliseconds 60000.0)
  lfSync conn apiKey lfmUser slug writeLock
