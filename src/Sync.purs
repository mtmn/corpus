module Sync
  ( listenBrainzUrl
  , lastfmTrackToListen
  , lbSyncOnce
  , lbSyncLoop
  , lfSyncOnce
  , lfSyncLoop
  ) where

import Prelude

import Control.Monad.Rec.Class (forever)
import Data.Argonaut (decodeJson, parseJson)
import Data.Argonaut.Core (Json, toArray, toObject, toString)
import Data.Array (length, mapMaybe, null)
import Data.Either (Either(..))
import Data.Foldable (foldM, for_)
import Data.Int (fromString)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple (Tuple(..))
import Db (Connection, checkExists, getOldestTs, upsertScrobble, withTransaction)
import Effect.Aff (Aff, delay, launchAff_, makeAff, nonCanceler, try)
import Effect.Aff.AVar (AVar)
import Effect.Aff.Retry (RetryStatus(..), exponentialBackoff, limitRetries, recovering)
import Effect.Class (liftEffect)
import Effect.Exception as Exception
import Effect.Uncurried (mkEffectFn1)
import Fetch (fetch, Method(GET))
import Fetch.Argonaut.Json (fromJson)
import Foreign.Object as Object
import JSURI (encodeURIComponent)
import Log as Log
import Metrics as Metrics
import Node.EventEmitter (EventHandle(..), on_)
import Node.HTTP.ClientRequest as Client
import Node.HTTP.IncomingMessage as IM
import Node.HTTPS as HTTPS
import Node.Stream.Aff (readableToStringUtf8)
import Types (Listen(..), ListenBrainzResponse(..), MbidMapping(..), Payload(..), TrackMetadata(..))
import Unsafe.Coerce (unsafeCoerce)

listenBrainzUrl :: String -> String
listenBrainzUrl username = "https://api.listenbrainz.org/1/user/" <> username <> "/listens"

withRetry :: forall a. String -> Aff a -> Aff a
withRetry label action = recovering policy [ \_ _ -> pure true ] \(RetryStatus status) -> do
  when (status.iterNumber > 0)
    $ Log.warn
    $ label <> " failed, retry attempt " <> show status.iterNumber
  action
  where
  policy = exponentialBackoff (Milliseconds 1000.0) <> limitRetries 5

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
              if allExist || null listens then
                pure (acc + added)
              else
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
