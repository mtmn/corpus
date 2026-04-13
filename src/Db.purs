module Db where

import Prelude

import Data.Argonaut.Core (Json, toObject, toString)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Effect.Aff (Aff, delay, makeAff, nonCanceler, try)
import Effect.Class (liftEffect)
import Effect.Exception (Error, error, message)
import Effect.Now (nowDateTime)
import Data.Formatter.DateTime (formatDateTime)
import Foreign (Foreign)
import Unsafe.Coerce (unsafeCoerce)
import Types (Listen(..), TrackMetadata(..), MbidMapping(..), Stats(..), StatsEntry(..))
import Data.Traversable (traverse)
import Foreign.Object as Object
import Data.Nullable (Nullable, toMaybe, toNullable)
import Data.Array (mapMaybe, uncons, (!!))
import Data.String (lastIndexOf, Pattern(..), take)
import Control.Monad.Rec.Class (forever)
import Node.FS.Aff as FSA
import Node.FS.Perms (mkPerms, all, read) as Perms
import Log as Log

foreign import data Connection :: Type

foreign import connectImpl :: String -> (Nullable Error -> Nullable Connection -> Effect Unit) -> Effect Unit
foreign import runImpl :: Connection -> String -> Array Foreign -> (Nullable Error -> Effect Unit) -> Effect Unit
foreign import allImpl :: Connection -> String -> Array Foreign -> (Nullable Error -> Nullable (Array Json) -> Effect Unit) -> Effect Unit
foreign import checkpointImpl :: Connection -> (Nullable Error -> Effect Unit) -> Effect Unit

connect :: String -> Aff Connection
connect path = makeAff \cb -> do
  connectImpl path \err conn ->
    case toMaybe err of
      Just e -> cb (Left e)
      Nothing -> case toMaybe conn of
        Just c -> cb (Right c)
        Nothing -> cb (Left $ error "Failed to create connection")
  pure nonCanceler

run :: Connection -> String -> Array Foreign -> Aff Unit
run conn sql params = makeAff \cb -> do
  runImpl conn sql params \err ->
    case toMaybe err of
      Just e -> cb (Left e)
      Nothing -> cb (Right unit)
  pure nonCanceler

checkpoint :: Connection -> Aff Unit
checkpoint conn = makeAff \cb -> do
  checkpointImpl conn \err ->
    case toMaybe err of
      Just e -> cb (Left e)
      Nothing -> cb (Right unit)
  pure nonCanceler

dirName :: String -> String
dirName path = case lastIndexOf (Pattern "/") path of
  Just i -> take (i + 1) path
  Nothing -> "./"

performBackup :: Connection -> String -> Aff Unit
performBackup conn dbFile = do
  checkpoint conn
  dt <- liftEffect nowDateTime
  let
    ts = case formatDateTime "YYYY-MM-DDTHH:mm:ss" dt of
      Right s -> s
      Left _ -> "unknown"
  let dir = dirName dbFile <> "backup/"
  void $ try $ FSA.mkdir' dir { recursive: true, mode: Perms.mkPerms Perms.all Perms.all Perms.read }
  let dest = dir <> "scorpus-" <> ts <> ".db"
  FSA.copyFile dbFile dest
  Log.info $ "Backup saved locally: " <> dest

backupDb :: Connection -> String -> Number -> Aff Unit
backupDb conn dbFile intervalMs = forever do
  delay (Milliseconds intervalMs)
  result <- try $ performBackup conn dbFile
  case result of
    Left err -> Log.error $ "Backup failed: " <> message err
    Right _ -> pure unit

queryAll :: Connection -> String -> Array Foreign -> Aff (Array Json)
queryAll conn sql params = makeAff \cb -> do
  allImpl conn sql params \err rows ->
    case toMaybe err of
      Just e -> cb (Left e)
      Nothing -> cb (Right (fromMaybe [] (toMaybe rows)))
  pure nonCanceler

initDb :: Connection -> Aff Unit
initDb conn = do
  run conn "CREATE TABLE IF NOT EXISTS scrobbles (listened_at BIGINT PRIMARY KEY, track_name VARCHAR, artist_name VARCHAR, release_name VARCHAR, release_mbid VARCHAR, caa_release_mbid VARCHAR)" []

checkExists :: Connection -> Int -> Aff Boolean
checkExists conn ts = do
  rows <- queryAll conn "SELECT 1 FROM scrobbles WHERE listened_at = ?" [ unsafeCoerce ts ]
  pure $ fromMaybe false $ do
    arr <- Just rows
    case arr of
      [] -> Just false
      _ -> Just true

getOldestTs :: Connection -> Aff (Maybe Int)
getOldestTs conn = do
  rows <- queryAll conn "SELECT MIN(listened_at) as min_ts FROM scrobbles" []
  pure $ do
    row <- rows !! 0
    obj <- toObject row
    ts <- Object.lookup "min_ts" obj >>= (unsafeCoerce >>> Just)
    if ts == 0 then Nothing else Just ts

upsertScrobble :: Connection -> Listen -> Aff Unit
upsertScrobble conn (Listen { listenedAt, trackMetadata: TrackMetadata track }) = do
  case listenedAt of
    Nothing -> pure unit
    Just ts -> do
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
      _ <- run conn "INSERT INTO scrobbles SELECT * FROM (SELECT ? as listened_at, ? as track_name, ? as artist_name, ? as release_name, ? as release_mbid, ? as caa_release_mbid) t WHERE NOT EXISTS (SELECT 1 FROM scrobbles WHERE listened_at = t.listened_at)" params
      pure unit

getScrobbles :: Connection -> Int -> Int -> Maybe { field :: String, value :: String } -> Aff (Array Listen)
getScrobbles conn limit offset Nothing = do
  rows <- queryAll conn
    "SELECT s.listened_at, s.track_name, s.artist_name, s.release_name, s.release_mbid, s.caa_release_mbid, rm.genre FROM scrobbles s LEFT JOIN release_metadata rm ON s.release_mbid = rm.release_mbid ORDER BY s.listened_at DESC LIMIT ? OFFSET ?"
    [ unsafeCoerce limit, unsafeCoerce offset ]
  pure $ fromMaybe [] $ traverse rowToListen rows
getScrobbles conn limit offset (Just { field, value }) = do
  let
    col = case field of
      "label" -> "rm.label"
      "year" -> "rm.release_year::VARCHAR"
      _ -> "rm.genre"
  rows <- queryAll conn
    ( "SELECT s.listened_at, s.track_name, s.artist_name, s.release_name, s.release_mbid, s.caa_release_mbid, rm.genre"
        <> " FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid"
        <> " WHERE "
        <> col
        <> " = ? ORDER BY s.listened_at DESC LIMIT ? OFFSET ?"
    )
    [ unsafeCoerce value, unsafeCoerce limit, unsafeCoerce offset ]
  pure $ fromMaybe [] $ traverse rowToListen rows

initReleaseMetadata :: Connection -> Aff Unit
initReleaseMetadata conn = do
  _ <- run conn "CREATE TABLE IF NOT EXISTS release_metadata (release_mbid VARCHAR PRIMARY KEY, genre VARCHAR, label VARCHAR, release_year INTEGER, genre_checked_at INTEGER)" []
  -- Migration for existing databases; DuckDB supports IF NOT EXISTS for adding columns
  _ <- run conn "ALTER TABLE release_metadata ADD COLUMN IF NOT EXISTS genre_checked_at INTEGER" []
  pure unit

ping :: Connection -> Aff Unit
ping conn = do
  _ <- queryAll conn "SELECT 1" []
  pure unit

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
upsertReleaseMetadata conn mbid genre label year = do
  _ <- run conn
    "INSERT INTO release_metadata (release_mbid, genre, label, release_year) VALUES (?, ?, ?, ?) ON CONFLICT(release_mbid) DO UPDATE SET genre=excluded.genre, label=excluded.label, release_year=excluded.release_year"
    [ unsafeCoerce mbid
    , unsafeCoerce (toNullable genre)
    , unsafeCoerce (toNullable label)
    , unsafeCoerce (toNullable year)
    ]
  pure unit

touchGenreCheckedAt :: Connection -> String -> Aff Unit
touchGenreCheckedAt conn mbid = do
  run conn
    "UPDATE release_metadata SET genre_checked_at = CAST(epoch(now()) AS INTEGER) WHERE release_mbid = ?"
    [ unsafeCoerce mbid ]

getStats :: Connection -> Aff Stats
getStats conn = do
  genreRows <- queryAll conn "SELECT rm.genre as name, COUNT(*) as count FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid WHERE rm.genre IS NOT NULL AND rm.genre != '' GROUP BY rm.genre ORDER BY count DESC LIMIT 50" []
  labelRows <- queryAll conn "SELECT rm.label as name, COUNT(*) as count FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid WHERE rm.label IS NOT NULL AND rm.label != '' GROUP BY rm.label ORDER BY count DESC LIMIT 50" []
  yearRows <- queryAll conn "SELECT CAST(rm.release_year AS VARCHAR) as name, COUNT(*) as count FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid WHERE rm.release_year IS NOT NULL GROUP BY rm.release_year ORDER BY rm.release_year DESC" []
  pure $ Stats
    { genres: mapMaybe rowToEntry genreRows
    , labels: mapMaybe rowToEntry labelRows
    , years: mapMaybe rowToEntry yearRows
    }

rowToEntry :: Json -> Maybe StatsEntry
rowToEntry json = do
  obj <- toObject json
  name <- Object.lookup "name" obj >>= toString
  count <- Object.lookup "count" obj >>= (unsafeCoerce >>> Just)
  pure $ StatsEntry { name, count }

getArtistReleaseByMbid :: Connection -> String -> Aff (Maybe { artist :: String, release :: String })
getArtistReleaseByMbid conn mbid = do
  rows <- queryAll conn
    "SELECT DISTINCT artist_name, release_name FROM scrobbles WHERE release_mbid = ? AND artist_name != '' AND release_name != '' LIMIT 1"
    [ unsafeCoerce mbid ]
  pure $ case uncons rows of
    Just { head: row, tail: _ } -> do
      obj <- toObject row
      artist <- Object.lookup "artist_name" obj >>= toString
      release <- Object.lookup "release_name" obj >>= toString
      Just { artist, release }
    Nothing -> Nothing

rowToListen :: Json -> Maybe Listen
rowToListen json = do
  obj <- toObject json
  listenedAt <- Object.lookup "listened_at" obj >>= (unsafeCoerce >>> Just)
  trackName <- Object.lookup "track_name" obj >>= toString
  artistName <- Object.lookup "artist_name" obj >>= toString
  releaseName <- Object.lookup "release_name" obj >>= toString
  releaseMbid <- Object.lookup "release_mbid" obj >>= toString
  caaReleaseMbid <- Object.lookup "caa_release_mbid" obj >>= toString
  let genre = Object.lookup "genre" obj >>= toString

  pure $ Listen
    { listenedAt: Just listenedAt
    , trackMetadata: TrackMetadata
        { trackName: Just trackName
        , artistName: Just artistName
        , releaseName: Just releaseName
        , genre
        , mbidMapping: Just $ MbidMapping
            { releaseMbid: if releaseMbid == "" then Nothing else Just releaseMbid
            , caaReleaseMbid: if caaReleaseMbid == "" then Nothing else Just caaReleaseMbid
            }
        }
    }
