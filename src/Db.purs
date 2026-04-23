module Db where

import Prelude

import Data.Argonaut.Core (Json, toObject, toNumber, toString)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Effect.Aff (Aff, delay, makeAff, nonCanceler, try)
import Effect.Aff.AVar (AVar)
import Effect.Aff.AVar as Avar
import Effect.Class (liftEffect)
import Effect.Exception (Error, error, message)
import Control.Monad.Error.Class (throwError)
import Effect.Now (nowDateTime)
import Data.Formatter.DateTime (formatDateTime)
import Data.Function.Uncurried (Fn2, Fn4, runFn2, runFn4)
import Foreign (Foreign)
import Unsafe.Coerce (unsafeCoerce)
import Types (Listen(..), TrackMetadata(..), MbidMapping(..), Stats(..), StatsEntry(..))
import Foreign.Object as Object
import Data.Nullable (Nullable, toMaybe, toNullable)
import Data.Array (mapMaybe, (!!), last, length, null, replicate)
import Data.Foldable (for_)
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..))
import Data.Int (fromString, round)
import Data.String (Pattern(..), split, stripSuffix)
import Control.Monad.Rec.Class (forever)
import Node.FS.Aff as FSA
import Config (S3Config)
import S3 as S3
import Log as Log
import Metrics as Metrics
import Data.UUID (genUUID, toString) as UUID

foreign import data Connection :: Type

data FilterField = FilterArtist | FilterAlbum | FilterLabel | FilterYear | FilterGenre | FilterTrack

derive instance Eq FilterField

instance Show FilterField where
  show FilterArtist = "FilterArtist"
  show FilterAlbum = "FilterAlbum"
  show FilterLabel = "FilterLabel"
  show FilterYear = "FilterYear"
  show FilterGenre = "FilterGenre"
  show FilterTrack = "FilterTrack"

foreign import connectImpl :: Fn2 String (Nullable Error -> Nullable Connection -> Effect Unit) (Effect Unit)
foreign import runImpl :: Fn4 Connection String (Array Foreign) (Nullable Error -> Effect Unit) (Effect Unit)
foreign import allImpl :: Fn4 Connection String (Array Foreign) (Nullable Error -> Nullable (Array Json) -> Effect Unit) (Effect Unit)
foreign import checkpointImpl :: Fn2 Connection (Nullable Error -> Effect Unit) (Effect Unit)

connect :: String -> Aff Connection
connect path = makeAff \cb -> do
  runFn2 connectImpl path \err conn ->
    case toMaybe err of
      Just e ->
        cb (Left e)
      Nothing -> case toMaybe conn of
        Just c -> cb (Right c)
        Nothing -> cb (Left $ error "Failed to create connection")
  pure nonCanceler

run :: Connection -> String -> Array Foreign -> Aff Unit
run conn sql params = makeAff \cb -> do
  runFn4 runImpl conn sql params \err ->
    case toMaybe err of
      Just e -> cb (Left e)
      Nothing -> cb (Right unit)
  pure nonCanceler

checkpoint :: Connection -> Aff Unit
checkpoint conn = makeAff \cb -> do
  runFn2 checkpointImpl conn \err ->
    case toMaybe err of
      Just e -> cb (Left e)
      Nothing -> cb (Right unit)
  pure nonCanceler

dbBaseName :: String -> String
dbBaseName path =
  let
    parts = split (Pattern "/") path
    name = fromMaybe path (last parts)
  in
    fromMaybe name (stripSuffix (Pattern ".db") name)

performBackup :: Connection -> String -> S3Config -> String -> Aff Unit
performBackup conn dbFile s3cfg slug = do
  checkpoint conn
  dt <- liftEffect nowDateTime
  let
    ts = case formatDateTime "YYYY-MM-DDTHH:mm:ss" dt of
      Right s -> s
      Left _ -> "unknown"
  let key = "backups/" <> dbBaseName dbFile <> "-" <> ts <> ".db"
  buf <- FSA.readFile dbFile
  S3.uploadToS3 s3cfg key buf "application/octet-stream"
  Log.info $ "Backup uploaded to S3: " <> key
  liftEffect $ Metrics.setDbBackupLastSuccess slug
  liftEffect $ Metrics.incDbBackupRun slug "success"

backupDb :: Connection -> String -> S3Config -> Number -> String -> Aff Unit
backupDb conn dbFile s3cfg intervalMs slug = forever do
  delay (Milliseconds intervalMs)
  result <- try $ performBackup conn dbFile s3cfg slug
  case result of
    Left err -> do
      Log.error $ "Backup failed: " <> message err
      liftEffect $ Metrics.incDbBackupRun slug "error"
    Right _ ->
      pure unit

-- Acquires the write lock, runs the action inside a transaction, then releases.
-- The lock is always released: on success, on action failure (rollback), and on
-- BEGIN/COMMIT failure. This prevents deadlock if the database throws unexpectedly.
withTransaction :: forall a. Connection -> AVar Unit -> Aff a -> Aff a
withTransaction conn lock action = do
  Avar.take lock
  result <- try do
    run conn "BEGIN TRANSACTION" []
    r <- try action
    case r of
      Left err -> do
        void $ try $ run conn "ROLLBACK" []
        throwError err
      Right v -> do
        void $ try $ run conn "COMMIT" []
        pure v
  Avar.put unit lock
  case result of
    Left err -> throwError err
    Right v -> pure v

queryAll :: Connection -> String -> Array Foreign -> Aff (Array Json)
queryAll conn sql params = makeAff \cb -> do
  runFn4 allImpl conn sql params \err rows ->
    case toMaybe err of
      Just e -> cb (Left e)
      Nothing -> cb (Right (fromMaybe [] (toMaybe rows)))
  pure nonCanceler

initDb :: Connection -> Aff Unit
initDb conn = do
  run conn "CREATE TABLE IF NOT EXISTS scrobbles (listened_at BIGINT PRIMARY KEY, track_name VARCHAR, artist_name VARCHAR, release_name VARCHAR, release_mbid VARCHAR, caa_release_mbid VARCHAR)" []
  run conn "CREATE TABLE IF NOT EXISTS api_tokens (slug VARCHAR PRIMARY KEY, token VARCHAR UNIQUE)" []

getOrCreateToken :: Connection -> String -> Aff String
getOrCreateToken conn slug = do
  rows <- queryAll conn "SELECT token FROM api_tokens WHERE slug = ?" [ unsafeCoerce slug ]
  case rows !! 0 >>= toObject >>= Object.lookup "token" >>= toString of
    Just token ->
      pure token
    Nothing -> do
      token <- liftEffect $ map UUID.toString UUID.genUUID
      run conn "INSERT INTO api_tokens (slug, token) VALUES (?, ?)" [ unsafeCoerce slug, unsafeCoerce token ]
      pure token

checkExists :: Connection -> Int -> Aff Boolean
checkExists conn ts = do
  rows <- queryAll conn "SELECT 1 FROM scrobbles WHERE listened_at = ?" [ unsafeCoerce ts ]
  pure case rows of
    [] -> false
    _ -> true

getOldestTs :: Connection -> Aff (Maybe Int)
getOldestTs conn = do
  rows <- queryAll conn "SELECT MIN(listened_at) as min_ts FROM scrobbles" []
  pure $ do
    row <- rows !! 0
    obj <- toObject row
    n <- Object.lookup "min_ts" obj >>= toNumber
    let ts = round n
    if ts == 0 then Nothing else Just ts

upsertScrobble :: Connection -> Listen -> Aff Unit
upsertScrobble conn (Listen { listenedAt, trackMetadata: TrackMetadata track }) =
  for_ listenedAt \ts -> do
    let
      mbid = fromMaybe (MbidMapping { releaseMbid: Nothing, caaReleaseMbid: Nothing }) track.mbidMapping
      MbidMapping m = mbid
      params =
        [ unsafeCoerce ts
        , unsafeCoerce (fromMaybe "" track.trackName)
        , unsafeCoerce (fromMaybe "" track.artistName)
        , unsafeCoerce (fromMaybe "" track.releaseName)
        , unsafeCoerce (fromMaybe "" m.releaseMbid)
        , unsafeCoerce (fromMaybe "" m.caaReleaseMbid)
        ]
    run conn "INSERT INTO scrobbles SELECT * FROM (SELECT ? as listened_at, ? as track_name, ? as artist_name, ? as release_name, ? as release_mbid, ? as caa_release_mbid) t WHERE NOT EXISTS (SELECT 1 FROM scrobbles WHERE listened_at = t.listened_at)" params

scrobbleCols :: String
scrobbleCols = "SELECT s.listened_at, s.track_name, s.artist_name, s.release_name, s.release_mbid, s.caa_release_mbid, rm.genre, rm.label"

scrobbleFromLeft :: String
scrobbleFromLeft = " FROM scrobbles s LEFT JOIN release_metadata rm ON s.release_mbid = rm.release_mbid"

scrobbleFromInner :: String
scrobbleFromInner = " FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid"

scrobbleOrderPage :: String
scrobbleOrderPage = " ORDER BY s.listened_at DESC LIMIT ? OFFSET ?"

getScrobbles :: Connection -> Int -> Int -> Maybe { field :: FilterField, value :: String } -> Maybe String -> Aff (Array Listen)
getScrobbles conn limit offset _ (Just q) = do
  let pattern = "%" <> q <> "%"
  rows <- queryAll conn
    ( scrobbleCols <> scrobbleFromLeft
        <> " WHERE (s.track_name ILIKE ? OR s.artist_name ILIKE ? OR s.release_name ILIKE ? OR rm.label ILIKE ?)"
        <> scrobbleOrderPage
    )
    [ unsafeCoerce pattern, unsafeCoerce pattern, unsafeCoerce pattern, unsafeCoerce pattern, unsafeCoerce limit, unsafeCoerce offset ]
  pure $ mapMaybe rowToListen rows
getScrobbles conn limit offset Nothing Nothing = do
  rows <- queryAll conn
    (scrobbleCols <> scrobbleFromLeft <> scrobbleOrderPage)
    [ unsafeCoerce limit, unsafeCoerce offset ]
  pure $ mapMaybe rowToListen rows
getScrobbles conn limit offset (Just { field, value }) Nothing = do
  rows <- queryAll conn (filterQuery field) [ unsafeCoerce value, unsafeCoerce limit, unsafeCoerce offset ]
  pure $ mapMaybe rowToListen rows

filterQuery :: FilterField -> String
filterQuery FilterArtist =
  scrobbleCols <> scrobbleFromLeft
    <> " WHERE s.artist_name = ?"
    <> scrobbleOrderPage
filterQuery FilterAlbum =
  scrobbleCols <> scrobbleFromLeft
    <> " WHERE s.release_name = ?"
    <> scrobbleOrderPage
filterQuery FilterLabel =
  scrobbleCols <> scrobbleFromInner
    <> " WHERE rm.label = ?"
    <> scrobbleOrderPage
filterQuery FilterYear =
  scrobbleCols <> scrobbleFromInner
    <> " WHERE rm.release_year::VARCHAR = ?"
    <> scrobbleOrderPage
filterQuery FilterGenre =
  scrobbleCols <> scrobbleFromInner
    <> " WHERE rm.genre = ?"
    <> scrobbleOrderPage
filterQuery FilterTrack =
  scrobbleCols <> scrobbleFromLeft
    <> " WHERE s.track_name = ?"
    <> scrobbleOrderPage

initReleaseMetadata :: Connection -> Aff Unit
initReleaseMetadata conn = do
  run conn "CREATE TABLE IF NOT EXISTS release_metadata (release_mbid VARCHAR PRIMARY KEY, genre VARCHAR, label VARCHAR, release_year INTEGER, genre_checked_at INTEGER)" []
  -- Migration for existing databases; DuckDB supports IF NOT EXISTS for adding columns
  run conn "ALTER TABLE release_metadata ADD COLUMN IF NOT EXISTS genre_checked_at INTEGER" []

ping :: Connection -> Aff Unit
ping conn = void $ queryAll conn "SELECT 1" []

getUnenrichedMbids :: Connection -> Int -> Aff (Array String)
getUnenrichedMbids conn limit = do
  rows <- queryAll conn
    "SELECT DISTINCT release_mbid FROM scrobbles WHERE release_mbid != '' AND release_mbid NOT IN (SELECT release_mbid FROM release_metadata) LIMIT ?"
    [ unsafeCoerce limit ]
  pure $ mapMaybe extractMbid rows
  where
  extractMbid json = do
    obj <- toObject json
    Object.lookup "release_mbid" obj >>= toString

getEmptyGenreMbids :: Connection -> Int -> Aff (Array String)
getEmptyGenreMbids conn limit = do
  rows <- queryAll conn
    "SELECT DISTINCT s.release_mbid FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid WHERE (rm.genre IS NULL OR rm.genre = '') AND (rm.genre_checked_at IS NULL OR rm.genre_checked_at < CAST(epoch(now()) AS INTEGER) - 604800) LIMIT ?"
    [ unsafeCoerce limit ]
  pure $ mapMaybe extractMbid rows
  where
  extractMbid json = do
    obj <- toObject json
    Object.lookup "release_mbid" obj >>= toString

upsertReleaseMetadata :: Connection -> String -> Maybe String -> Maybe String -> Maybe Int -> Aff Unit
upsertReleaseMetadata conn mbid genre label year =
  run conn
    "INSERT INTO release_metadata (release_mbid, genre, label, release_year) VALUES (?, ?, ?, ?) ON CONFLICT(release_mbid) DO UPDATE SET genre=excluded.genre, label=excluded.label, release_year=excluded.release_year"
    [ unsafeCoerce mbid
    , unsafeCoerce (toNullable genre)
    , unsafeCoerce (toNullable label)
    , unsafeCoerce (toNullable year)
    ]

touchGenreCheckedAt :: Connection -> String -> Aff Unit
touchGenreCheckedAt conn mbid = do
  run conn
    "UPDATE release_metadata SET genre_checked_at = CAST(epoch(now()) AS INTEGER) WHERE release_mbid = ?"
    [ unsafeCoerce mbid ]

getStats :: Connection -> Maybe String -> Maybe String -> Maybe String -> Maybe String -> Aff Stats
getStats conn mPeriod mFrom mTo mSection = do
  let
    buildTimeFilterAndParams :: { timeFilter :: String, params :: Array Foreign }
    buildTimeFilterAndParams = case mFrom, mTo of
      Just from, Just to ->
        { timeFilter: " AND s.listened_at >= CAST(epoch(TIMESTAMP '" <> from <> " 00:00:00') AS INTEGER) AND s.listened_at < CAST(epoch(TIMESTAMP '" <> to <> " 00:00:00') AS INTEGER) + 86400"
        , params: []
        }
      _, _ -> case mPeriod >>= fromString of
        Just days ->
          { timeFilter: " AND s.listened_at >= CAST(epoch(now()) AS INTEGER) - ?"
          , params: [ unsafeCoerce (days * 86400) ]
          }
        Nothing ->
          { timeFilter: "", params: [] }
    { timeFilter, params: buildTimeParams } = buildTimeFilterAndParams
    fetch name q extraParams = case mSection of
      Nothing -> queryAll conn (q <> " LIMIT 50") (buildTimeParams <> extraParams)
      Just s | s == name -> queryAll conn q (buildTimeParams <> extraParams)
      Just _ -> pure []
  genreRows <- fetch "genre" ("SELECT rm.genre as name, COUNT(*) as count FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid WHERE rm.genre IS NOT NULL AND rm.genre != ''" <> timeFilter <> " GROUP BY rm.genre ORDER BY count DESC") []
  labelRows <- fetch "label" ("SELECT rm.label as name, COUNT(*) as count FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid WHERE rm.label IS NOT NULL AND rm.label != ''" <> timeFilter <> " GROUP BY rm.label ORDER BY count DESC") []
  yearRows <- fetch "year" ("SELECT CAST(rm.release_year AS VARCHAR) as name, COUNT(*) as count FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid WHERE rm.release_year IS NOT NULL" <> timeFilter <> " GROUP BY rm.release_year ORDER BY rm.release_year DESC") []
  artistRows <- fetch "artist" ("SELECT s.artist_name as name, COUNT(*) as count FROM scrobbles s WHERE s.artist_name != ''" <> timeFilter <> " GROUP BY s.artist_name ORDER BY count DESC") []
  trackRows <- fetch "track" ("SELECT s.artist_name || ' — ' || s.track_name as name, COUNT(*) as count FROM scrobbles s WHERE s.track_name != '' AND s.artist_name != ''" <> timeFilter <> " GROUP BY s.artist_name, s.track_name ORDER BY count DESC") []
  pure $ Stats
    { genres: mapMaybe rowToEntry genreRows
    , labels: mapMaybe rowToEntry labelRows
    , years: mapMaybe rowToEntry yearRows
    , artists: mapMaybe rowToEntry artistRows
    , tracks: mapMaybe rowToEntry trackRows
    }

rowToEntry :: Json -> Maybe StatsEntry
rowToEntry json = do
  obj <- toObject json
  name <- Object.lookup "name" obj >>= toString
  count <- map round $ Object.lookup "count" obj >>= toNumber
  pure $ StatsEntry { name, count }

getArtistReleasesByMbids :: Connection -> Array String -> Aff (Object.Object { artist :: String, release :: String })
getArtistReleasesByMbids _ mbids | null mbids = pure Object.empty
getArtistReleasesByMbids conn mbids = do
  let placeholders = joinWith "," (replicate (length mbids) "?")
  rows <- queryAll conn
    ( "SELECT DISTINCT release_mbid, artist_name, release_name FROM scrobbles"
        <> " WHERE release_mbid IN ("
        <> placeholders
        <> ") AND artist_name != '' AND release_name != ''"
    )
    (map unsafeCoerce mbids)
  pure $ Object.fromFoldable (mapMaybe extractPair rows)
  where
  extractPair json = do
    obj <- toObject json
    mbid <- Object.lookup "release_mbid" obj >>= toString
    artist <- Object.lookup "artist_name" obj >>= toString
    release <- Object.lookup "release_name" obj >>= toString
    pure $ Tuple mbid { artist, release }

rowToListen :: Json -> Maybe Listen
rowToListen json = do
  obj <- toObject json
  listenedAt <- map round $ Object.lookup "listened_at" obj >>= toNumber
  trackName <- Object.lookup "track_name" obj >>= toString
  artistName <- Object.lookup "artist_name" obj >>= toString
  releaseName <- Object.lookup "release_name" obj >>= toString
  releaseMbid <- Object.lookup "release_mbid" obj >>= toString
  caaReleaseMbid <- Object.lookup "caa_release_mbid" obj >>= toString
  let genre = Object.lookup "genre" obj >>= toString
  let label = Object.lookup "label" obj >>= toString

  pure $ Listen
    { listenedAt: Just listenedAt
    , trackMetadata: TrackMetadata
        { trackName: Just trackName
        , artistName: Just artistName
        , releaseName: Just releaseName
        , genre
        , label
        , mbidMapping: Just $ MbidMapping
            { releaseMbid: if releaseMbid == "" then Nothing else Just releaseMbid
            , caaReleaseMbid: if caaReleaseMbid == "" then Nothing else Just caaReleaseMbid
            }
        }
    }

getTokenUser :: Connection -> String -> Aff (Maybe String)
getTokenUser conn token = do
  rows <- queryAll conn "SELECT slug FROM api_tokens WHERE token = ?" [ unsafeCoerce token ]
  pure $ rows !! 0 >>= toObject >>= Object.lookup "slug" >>= toString
