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
import Data.Set as Set
import Data.String (Pattern(..), stripPrefix)
import Data.Time.Duration (Milliseconds(..))
import Db
  ( Connection
  , getExistingTimestamps
  , getOldestTs
  , upsertScrobble
  , withTransaction
  )
import Effect.Aff (Aff, delay, throwError, try)
import Effect.Aff.AVar (AVar)
import Effect.Aff.Retry
  ( RetryStatus(..)
  , exponentialBackoff
  , limitRetries
  , recovering
  )
import Effect.Class (liftEffect)
import Effect.Exception (error, message)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Fetch (Method(GET), fetch)
import Fetch.Argonaut.Json (fromJson)
import Http (apiTimeout, withTimeout)
import JSURI (encodeURIComponent)
import Log as Log
import Metrics as Metrics
import Types
  ( LastfmAlbum(..)
  , LastfmArtist(..)
  , LastfmAttr(..)
  , LastfmDate(..)
  , LastfmRecentTracks(..)
  , LastfmResponse(..)
  , LastfmTrack(..)
  , LastfmTracks(..)
  , Listen(..)
  , ListenBrainzResponse(..)
  , MbidMapping(..)
  , Payload(..)
  , TrackMetadata(..)
  )

-- | Result of processing a batch of listens/scrobbles.
type SyncResult =
  { added :: Int
  , hitCount :: Int
  , minTs :: Maybe Int
  }

-- | Process a batch of listens: check existence, insert new ones, track stats.
-- | When trackMinTs is true, the minimum timestamp is tracked (for cursor-based pagination).
-- | Existence is checked with one batch query up front instead of one query
-- | per listen; `seen` also guards against duplicate timestamps within a batch.
processTracks :: Connection -> Array Listen -> Boolean -> Aff SyncResult
processTracks conn listens trackMinTs = do
  existing <- getExistingTimestamps conn
    (mapMaybe (\(Listen l) -> l.listenedAt) listens)
  acc <- foldM step
    { added: 0, hitCount: 0, minTs: Nothing, seen: existing }
    listens
  pure { added: acc.added, hitCount: acc.hitCount, minTs: acc.minTs }
  where
  step
    :: { added :: Int
       , hitCount :: Int
       , minTs :: Maybe Int
       , seen :: Set.Set Int
       }
    -> Listen
    -> Aff
         { added :: Int
         , hitCount :: Int
         , minTs :: Maybe Int
         , seen :: Set.Set Int
         }
  step s l@(Listen { listenedAt: Just ts })
    | Set.member ts s.seen = do
        let nextMinTs = if trackMinTs then Just ts else s.minTs
        pure $ s { hitCount = s.hitCount + 1, minTs = nextMinTs }
    | otherwise = do
        upsertScrobble conn l
        let nextMinTs = if trackMinTs then Just ts else s.minTs
        pure $ s
          { added = s.added + 1
          , minTs = nextMinTs
          , seen = Set.insert ts s.seen
          }
  step s (Listen { listenedAt: Nothing }) = do
    Log.warn "Skipping scrobble without timestamp"
    pure s

-- | Build the ListenBrainz listens endpoint for a username.
listenBrainzUrl :: String -> String
listenBrainzUrl username = "https://api.listenbrainz.org/1/user/" <> username <>
  "/listens"

-- | Retry an action with exponential backoff, but only for transient errors.
-- | Parse errors and other permanent failures are not retried.
withRetry :: forall a. String -> Aff a -> Aff a
withRetry label action = recovering policy
  [ \_ err -> pure $ isTransientError err ]
  \(RetryStatus status) -> do
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
fetchListenBrainzUrl url = withRetry "ListenBrainz fetch" do
  let headers = { "User-Agent": "corpus/1.0 (+https://sr.ht/~mtmn/corpus)" }
  fr <- withTimeout apiTimeout "ListenBrainz fetch" $ fetch url
    { method: GET, headers }
  if fr.status == 200 then
    withTimeout apiTimeout "ListenBrainz response" fr.text
  else
    throwError $ error $ "ListenBrainz API returned status " <> show fr.status

-- | Fetch and decode one Last.fm recent-tracks page.
fetchLastfmPage
  :: String
  -> String
  -> Int
  -> Maybe Int
  -> Aff { tracks :: Array Json, totalPages :: Int }
fetchLastfmPage apiKey lfmUser page mTo = withRetry "Last.fm fetch" do
  let
    toParam = case mTo of
      Just ts -> "&to=" <> show ts
      Nothing -> ""
    baseUrl =
      "https://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&user="
        <> (fromMaybe lfmUser $ encodeURIComponent lfmUser)
        <> "&format=json&limit=200&page="
        <> show page
        <> toParam
    url = baseUrl <> "&api_key=" <> apiKey
  let headers = { "User-Agent": "corpus/1.0 (+https://sr.ht/~mtmn/corpus)" }
  fr <- withTimeout apiTimeout "Last.fm sync fetch" $ fetch url
    { method: GET, headers }
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

-- | Parse a Last.fm page into tracks and its total-page count.
parseLastfmResponse :: Json -> Maybe { tracks :: Array Json, totalPages :: Int }
parseLastfmResponse json = case decodeJson json of
  Right
    ( LastfmResponse
        { recenttracks: LastfmRecentTracks
            { track, attr: LastfmAttr { totalPages } }
        }
    ) ->
    let
      tracks = case track of
        LastfmTrackArray' ts -> ts
        LastfmTrackSingle' t -> [ t ]
    in
      Just { tracks, totalPages: totalPages }
  Left _ ->
    Nothing

-- | Convert a Last.fm track JSON value into a listen when it has a timestamp.
lastfmTrackToListen :: Json -> Maybe Listen
lastfmTrackToListen json = case decodeJson json of
  Right
    ( LastfmTrack
        { name, artist: LastfmArtist { text: artistName }, album, date }
    ) -> do
    ts <- date >>= \(LastfmDate { uts }) -> Just uts
    let
      releaseName = album >>= \(LastfmAlbum { text }) -> text
      releaseMbid = album >>= \(LastfmAlbum { mbid }) ->
        if mbid == "" then Nothing else Just mbid
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
  Left _ ->
    Nothing

recordSyncSuccess :: String -> String -> Int -> Aff Unit
recordSyncSuccess slug source n = do
  liftEffect $ Metrics.incSyncRuns slug source "success"
  when (n > 0) $ liftEffect $ Metrics.incSyncScrobbles slug source n
  liftEffect $ Metrics.setSyncLastSuccess slug source

-- | True when every track in the batch was already present.
syncBatchDone :: Array Listen -> Int -> Boolean
syncBatchDone listens hitCount =
  hitCount == length listens && not (null listens)

-- | Log the result of processing one sync batch.
logSyncBatch :: String -> Int -> SyncResult -> Aff Unit
logSyncBatch source batchNum result =
  Log.info $ source <> " batch " <> show batchNum <> ": added "
    <> show result.added
    <> ", "
    <> show result.hitCount
    <> " already present."

-- | Perform one ListenBrainz synchronization pass.
lbSync :: Connection -> String -> String -> AVar Unit -> Aff Unit
lbSync conn username slug writeLock = void do
  Log.info $ "Starting ListenBrainz sync for " <> username
  result <- try $ fetchListenBrainzUrl
    (listenBrainzUrl username <> "?count=100")
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
          logSyncBatch "ListenBrainz" 1 syncResult
          let allExist = syncBatchDone listens syncResult.hitCount
          if allExist || null listens then do
            when (syncResult.added > 0) $ Log.info $
              "ListenBrainz sync complete. Added " <> show syncResult.added <>
                " new scrobbles."
            recordSyncSuccess slug "listenbrainz" syncResult.added
          else do
            total <- paginateUntilDone 2 syncResult.minTs syncResult.added
            Log.info $ "ListenBrainz sync complete. Added " <> show total <>
              " new scrobbles."
            recordSyncSuccess slug "listenbrainz" total
  where
  paginateUntilDone batchNum minTs acc = case minTs of
    Nothing ->
      pure acc
    Just ts -> do
      Log.info $ "Fetching ListenBrainz batch " <> show batchNum <> " (before "
        <> show ts
        <> ")..."
      result <- try $ fetchListenBrainzUrl
        (listenBrainzUrl username <> "?count=100&max_ts=" <> show ts)
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
              syncResult <- withTransaction conn writeLock
                (processListens listens)
              logSyncBatch "ListenBrainz" batchNum syncResult
              let allExist = syncBatchDone listens syncResult.hitCount
              if allExist || null listens then
                pure (acc + syncResult.added)
              else
                paginateUntilDone (batchNum + 1) syncResult.minTs
                  (acc + syncResult.added)

  processListens listens = processTracks conn listens true

-- | Run ListenBrainz synchronization every minute.
lbSyncLoop :: Connection -> String -> String -> AVar Unit -> Aff Unit
lbSyncLoop conn username slug writeLock = forever do
  delay (Milliseconds 60000.0)
  lbSync conn username slug writeLock

-- | Perform one Last.fm synchronization and optional history backfill.
-- | backfillDoneRef is set once the backfill finds no older history, so the
-- | hourly-needless Last.fm probe stops instead of running every minute forever.
lfSync
  :: Connection
  -> String
  -> String
  -> String
  -> AVar Unit
  -> Ref Boolean
  -> Aff Unit
lfSync conn apiKey lfmUser slug writeLock backfillDoneRef = do
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
        let validTracks = mapMaybe lastfmTrackToListen tracks
        result <- withTransaction conn writeLock
          (processLastfmTracks validTracks)
        logSyncBatch "Last.fm" 1 result
        let allExist = syncBatchDone validTracks result.hitCount
        if allExist || totalPages <= 1 then do
          when (result.added > 0) $ Log.info $
            "Last.fm sync complete. Added " <> show result.added <>
              " new scrobbles."
          recordSyncSuccess slug "lastfm" result.added
        else do
          total <- paginateLastfmUntilDone 2 totalPages Nothing result.added
          Log.info $ "Last.fm sync complete. Added " <> show total <>
            " new scrobbles."
          recordSyncSuccess slug "lastfm" total

  paginateLastfmUntilDone page totalPages mTo acc
    | page > totalPages = pure acc
    | otherwise = do
        Log.info $ "Fetching Last.fm page " <> show page <> "/"
          <> show totalPages
          <> "..."
        res <- try $ fetchLastfmPage apiKey lfmUser page mTo
        case res of
          Left err -> do
            Log.error $ "Last.fm sync fetch error: " <> message err
            pure acc
          Right { tracks } -> do
            let validTracks = mapMaybe lastfmTrackToListen tracks
            result <- withTransaction conn writeLock
              (processLastfmTracks validTracks)
            logSyncBatch "Last.fm" page result
            let allExist = syncBatchDone validTracks result.hitCount
            if allExist || null tracks then pure (acc + result.added)
            else paginateLastfmUntilDone (page + 1) totalPages mTo
              (acc + result.added)

  performLastfmBackfill = do
    done <- liftEffect $ Ref.read backfillDoneRef
    unless done do
      mOldest <- getOldestTs conn
      for_ mOldest \oldestTs -> do
        Log.info $ "Checking for Last.fm history before " <> show oldestTs <>
          "..."
        res <- try $ fetchLastfmPage apiKey lfmUser 1 (Just (oldestTs - 1))
        case res of
          Left err ->
            Log.error $ "Last.fm backfill fetch error: " <> message err
          Right { tracks, totalPages } ->
            if null tracks then do
              liftEffect $ Ref.write true backfillDoneRef
              Log.info "No older Last.fm history found."
            else do
              Log.info $ "Backfilling " <> show totalPages
                <> " pages of Last.fm history before "
                <> show oldestTs
              let validTracks = mapMaybe lastfmTrackToListen tracks
              result <- withTransaction conn writeLock
                (processLastfmTracks validTracks)
              logSyncBatch "Last.fm backfill" 1 result
              total <- paginateLastfmUntilDone 2 totalPages
                (Just (oldestTs - 1))
                result.added
              Log.info $ "Last.fm backfill complete. Added " <> show total <>
                " older scrobbles."

  processLastfmTracks validTracks = processTracks conn validTracks false

-- | Run Last.fm synchronization every minute.
lfSyncLoop
  :: Connection
  -> String
  -> String
  -> String
  -> AVar Unit
  -> Ref Boolean
  -> Aff Unit
lfSyncLoop conn apiKey lfmUser slug writeLock backfillDoneRef = forever do
  delay (Milliseconds 60000.0)
  lfSync conn apiKey lfmUser slug writeLock backfillDoneRef
