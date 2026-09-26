module Db
  ( Connection
  , FilterField(..)
  , checkExists
  , checkpoint
  , closeConnection
  , connect
  , fromString
  , getArtistReleasesByMbids
  , getEmptyGenreMbids
  , getOldestTs
  , getOrCreateToken
  , getScrobbles
  , getTokenUser
  , getUnenrichedMbids
  , initDb
  , initReleaseMetadata
  , ping
  , queryAll
  , run
  , toParam
  , touchGenreCheckedAt
  , upsertReleaseMetadata
  , upsertScrobble
  , withTransaction
  ) where

import Prelude

import Control.Monad.Error.Class (throwError)
import Data.Argonaut.Core (Json, toNumber, toObject, toString)
import Data.Array (length, mapMaybe, null, replicate, (!!))
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Function.Uncurried (Fn2, Fn4, runFn2, runFn4)
import Data.Generic.Rep (class Generic)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Nullable (Nullable, toMaybe, toNullable)
import Data.Show.Generic (genericShow)
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..))
import Data.UUID (genUUID, toString) as UUID
import Effect (Effect)
import Effect.Aff (Aff, bracket, makeAff, nonCanceler, try)
import Effect.Aff.AVar (AVar)
import Effect.Aff.AVar as Avar
import Effect.Class (liftEffect)
import Effect.Exception (Error, error)
import Foreign (Foreign)
import Foreign.Object as Object
import Types
  ( Listen(..)
  , MbidMapping(..)
  , TrackMetadata(..)
  )
import Unsafe.Coerce (unsafeCoerce)

-- | An open SQLite database connection.
foreign import data Connection :: Type

-- | Coerces a value to Foreign for SQL parameters.
-- | This centralizes all unsafeCoerce usage for database operations
-- | into a single auditable point.
toParam :: forall a. a -> Foreign
toParam = unsafeCoerce

-- | Fields that can be used to filter a scrobble query.
data FilterField
  = FilterArtist
  | FilterAlbum
  | FilterLabel
  | FilterYear
  | FilterGenre
  | FilterTrack

derive instance Eq FilterField
derive instance Generic FilterField _
instance Show FilterField where
  show = genericShow

-- | Parse an API filter-field name.
fromString :: String -> Maybe FilterField
fromString "artist" = Just FilterArtist
fromString "album" = Just FilterAlbum
fromString "label" = Just FilterLabel
fromString "year" = Just FilterYear
fromString "genre" = Just FilterGenre
fromString "track" = Just FilterTrack
fromString _ = Nothing

foreign import connectImpl
  :: Fn2 String (Nullable Error -> Nullable Connection -> Effect Unit)
       (Effect Unit)

foreign import runImpl
  :: Fn4 Connection String (Array Foreign) (Nullable Error -> Effect Unit)
       (Effect Unit)

foreign import allImpl
  :: Fn4 Connection String (Array Foreign)
       (Nullable Error -> Nullable (Array Json) -> Effect Unit)
       (Effect Unit)

foreign import checkpointImpl
  :: Fn2 Connection (Nullable Error -> Effect Unit) (Effect Unit)

foreign import closeConnectionImpl
  :: Fn2 Connection (Nullable Error -> Effect Unit) (Effect Unit)

foreign import sha256 :: String -> String

-- | Open a SQLite database at the supplied path.
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

-- | Execute a parameterized SQL statement.
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

-- Closes the underlying DuckDB connection, releasing its file lock so the
-- database file can be deleted.
-- | Close an open database connection.
closeConnection :: Connection -> Aff Unit
closeConnection conn = makeAff \cb -> do
  runFn2 closeConnectionImpl conn \err ->
    case toMaybe err of
      Just e -> cb (Left e)
      Nothing -> cb (Right unit)
  pure nonCanceler

-- Acquires the write lock, runs the action inside a transaction, then releases.
-- Uses bracket to guarantee lock release even on fiber kill, preventing deadlocks.
-- | Run an action in a serialized SQLite transaction.
withTransaction :: forall a. Connection -> AVar Unit -> Aff a -> Aff a
withTransaction conn lock action =
  bracket (Avar.take lock) (\_ -> Avar.put unit lock) \_ -> do
    run conn "BEGIN TRANSACTION" []
    r <- try action
    case r of
      Left err -> do
        void $ try $ run conn "ROLLBACK" []
        throwError err
      Right v -> do
        void $ try $ run conn "COMMIT" []
        pure v

-- | Return all rows from a parameterized SQL query.
queryAll :: Connection -> String -> Array Foreign -> Aff (Array Json)
queryAll conn sql params = makeAff \cb -> do
  runFn4 allImpl conn sql params \err rows ->
    case toMaybe err of
      Just e -> cb (Left e)
      Nothing -> cb (Right (fromMaybe [] (toMaybe rows)))
  pure nonCanceler

-- | Create the core scrobble schema when it is absent.
initDb :: Connection -> Aff Unit
initDb conn = do
  run conn
    "CREATE TABLE IF NOT EXISTS scrobbles (listened_at BIGINT PRIMARY KEY, track_name VARCHAR, artist_name VARCHAR, release_name VARCHAR, release_mbid VARCHAR, caa_release_mbid VARCHAR)"
    []
  run conn
    "CREATE TABLE IF NOT EXISTS api_tokens (slug VARCHAR PRIMARY KEY, hashed_token VARCHAR UNIQUE)"
    []

-- | Look up or create the API token for a user slug.
getOrCreateToken :: Connection -> String -> Aff (Maybe String)
getOrCreateToken conn slug = do
  rows <- queryAll conn "SELECT hashed_token FROM api_tokens WHERE slug = ?"
    [ toParam slug ]
  case rows !! 0 >>= toObject >>= Object.lookup "hashed_token" >>= toString of
    Just _ ->
      pure Nothing
    Nothing -> do
      token <- liftEffect $ map UUID.toString UUID.genUUID
      let hashedToken = sha256 token
      run conn "INSERT INTO api_tokens (slug, hashed_token) VALUES (?, ?)"
        [ toParam slug, toParam hashedToken ]
      pure $ Just token

-- | Test whether a scrobble timestamp already exists.
checkExists :: Connection -> Int -> Aff Boolean
checkExists conn ts = do
  rows <- queryAll conn "SELECT 1 FROM scrobbles WHERE listened_at = ?"
    [ toParam ts ]
  pure case rows of
    [] -> false
    _ -> true

-- | Get the oldest stored scrobble timestamp.
getOldestTs :: Connection -> Aff (Maybe Int)
getOldestTs conn = do
  rows <- queryAll conn "SELECT MIN(listened_at) as min_ts FROM scrobbles" []
  pure $ do
    row <- rows !! 0
    obj <- toObject row
    n <- Object.lookup "min_ts" obj >>= toNumber
    let ts = Int.round n
    if ts == 0 then Nothing else Just ts

-- | Insert or update one normalized listen.
upsertScrobble :: Connection -> Listen -> Aff Unit
upsertScrobble conn (Listen { listenedAt, trackMetadata: TrackMetadata track }) =
  for_ listenedAt \ts -> do
    let
      mbid = fromMaybe
        (MbidMapping { releaseMbid: Nothing, caaReleaseMbid: Nothing })
        track.mbidMapping
      MbidMapping m = mbid
      params =
        [ toParam ts
        , toParam (fromMaybe "" track.trackName)
        , toParam (fromMaybe "" track.artistName)
        , toParam (fromMaybe "" track.releaseName)
        , toParam (fromMaybe "" m.releaseMbid)
        , toParam (fromMaybe "" m.caaReleaseMbid)
        ]
    run conn
      "INSERT INTO scrobbles SELECT * FROM (SELECT ? as listened_at, ? as track_name, ? as artist_name, ? as release_name, ? as release_mbid, ? as caa_release_mbid) t WHERE NOT EXISTS (SELECT 1 FROM scrobbles WHERE listened_at = t.listened_at)"
      params

scrobbleCols :: String
scrobbleCols =
  "SELECT s.listened_at, s.track_name, s.artist_name, s.release_name, s.release_mbid, s.caa_release_mbid, rm.genre, rm.label"

scrobbleFromLeft :: String
scrobbleFromLeft =
  " FROM scrobbles s LEFT JOIN release_metadata rm ON s.release_mbid = rm.release_mbid"

scrobbleFromInner :: String
scrobbleFromInner =
  " FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid"

scrobbleOrderPage :: String
scrobbleOrderPage = " ORDER BY s.listened_at DESC LIMIT ? OFFSET ?"

-- | Query a page of stored scrobbles with optional filtering.
getScrobbles
  :: Connection
  -> Int
  -> Int
  -> Maybe { field :: FilterField, value :: String }
  -> Maybe String
  -> Aff (Array Listen)
getScrobbles conn limit offset _ (Just q) = do
  let pattern = "%" <> q <> "%"
  rows <- queryAll conn
    ( scrobbleCols <> scrobbleFromLeft
        <>
          " WHERE (s.track_name ILIKE ? OR s.artist_name ILIKE ? OR s.release_name ILIKE ? OR rm.label ILIKE ?)"
        <> scrobbleOrderPage
    )
    [ toParam pattern
    , toParam pattern
    , toParam pattern
    , toParam pattern
    , toParam limit
    , toParam offset
    ]
  pure $ mapMaybe rowToListen rows
getScrobbles conn limit offset Nothing Nothing = do
  rows <- queryAll conn
    (scrobbleCols <> scrobbleFromLeft <> scrobbleOrderPage)
    [ toParam limit, toParam offset ]
  pure $ mapMaybe rowToListen rows
getScrobbles conn limit offset (Just { field, value }) Nothing = do
  rows <- queryAll conn (filterQuery field)
    [ toParam value, toParam limit, toParam offset ]
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

-- | Create the release-metadata schema when it is absent.
initReleaseMetadata :: Connection -> Aff Unit
initReleaseMetadata conn = do
  run conn
    "CREATE TABLE IF NOT EXISTS release_metadata (release_mbid VARCHAR PRIMARY KEY, genre VARCHAR, label VARCHAR, release_year INTEGER, genre_checked_at INTEGER)"
    []
  -- Migration for existing databases; DuckDB supports IF NOT EXISTS for adding columns
  run conn
    "ALTER TABLE release_metadata ADD COLUMN IF NOT EXISTS genre_checked_at INTEGER"
    []

-- | Verify that a database connection accepts queries.
ping :: Connection -> Aff Unit
ping conn = void $ queryAll conn "SELECT 1" []

-- | List release MBIDs missing metadata, up to a limit.
getUnenrichedMbids :: Connection -> Int -> Aff (Array String)
getUnenrichedMbids conn limit = do
  rows <- queryAll conn
    "SELECT DISTINCT release_mbid FROM scrobbles WHERE release_mbid != '' AND release_mbid NOT IN (SELECT release_mbid FROM release_metadata) LIMIT ?"
    [ toParam limit ]
  pure $ mapMaybe extractMbid rows
  where
  extractMbid json = do
    obj <- toObject json
    Object.lookup "release_mbid" obj >>= toString

-- | List release MBIDs still missing a genre, up to a limit.
getEmptyGenreMbids :: Connection -> Int -> Aff (Array String)
getEmptyGenreMbids conn limit = do
  rows <- queryAll conn
    "SELECT DISTINCT s.release_mbid FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid WHERE (rm.genre IS NULL OR rm.genre = '') AND (rm.genre_checked_at IS NULL OR rm.genre_checked_at < CAST(epoch(now()) AS INTEGER) - 604800) LIMIT ?"
    [ toParam limit ]
  pure $ mapMaybe extractMbid rows
  where
  extractMbid json = do
    obj <- toObject json
    Object.lookup "release_mbid" obj >>= toString

-- | Insert or update metadata for a MusicBrainz release.
upsertReleaseMetadata
  :: Connection
  -> String
  -> Maybe String
  -> Maybe String
  -> Maybe Int
  -> Aff Unit
upsertReleaseMetadata conn mbid genre label year =
  run conn
    "INSERT INTO release_metadata (release_mbid, genre, label, release_year) VALUES (?, ?, ?, ?) ON CONFLICT(release_mbid) DO UPDATE SET genre=excluded.genre, label=excluded.label, release_year=excluded.release_year"
    [ toParam mbid
    , toParam (toNullable genre)
    , toParam (toNullable label)
    , toParam (toNullable year)
    ]

-- | Mark a release genre as checked without changing its value.
touchGenreCheckedAt :: Connection -> String -> Aff Unit
touchGenreCheckedAt conn mbid = do
  run conn
    "UPDATE release_metadata SET genre_checked_at = CAST(epoch(now()) AS INTEGER) WHERE release_mbid = ?"
    [ toParam mbid ]

-- | Map release MBIDs to their locally known artist and release names.
getArtistReleasesByMbids
  :: Connection
  -> Array String
  -> Aff (Object.Object { artist :: String, release :: String })
getArtistReleasesByMbids _ mbids | null mbids = pure Object.empty
getArtistReleasesByMbids conn mbids = do
  let placeholders = joinWith "," (replicate (length mbids) "?")
  rows <- queryAll conn
    ( "SELECT DISTINCT release_mbid, artist_name, release_name FROM scrobbles"
        <> " WHERE release_mbid IN ("
        <> placeholders
        <> ") AND artist_name != '' AND release_name != ''"
    )
    (map toParam mbids)
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
  listenedAt <- map Int.round $ Object.lookup "listened_at" obj >>= toNumber
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
            { releaseMbid:
                if releaseMbid == "" then Nothing else Just releaseMbid
            , caaReleaseMbid:
                if caaReleaseMbid == "" then Nothing else Just caaReleaseMbid
            }
        }
    }

-- | Find the owning user slug for an API token.
getTokenUser :: Connection -> String -> Aff (Maybe String)
getTokenUser conn token = do
  let hashedToken = sha256 token
  rows <- queryAll conn "SELECT slug FROM api_tokens WHERE hashed_token = ?"
    [ toParam hashedToken ]
  pure $ rows !! 0 >>= toObject >>= Object.lookup "slug" >>= toString
