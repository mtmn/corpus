module Db where

import Prelude

import Data.Argonaut.Core (Json, toObject, toString, toArray)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Exception (Error, error)
import Foreign (Foreign)
import Unsafe.Coerce (unsafeCoerce)
import Types (Listen(..), TrackMetadata(..), MbidMapping(..))
import Data.Traversable (traverse)
import Foreign.Object as Object
import Data.Nullable (Nullable, toMaybe)

foreign import data Connection :: Type

foreign import connectImpl :: String -> (Nullable Error -> Nullable Connection -> Effect Unit) -> Effect Unit
foreign import runImpl :: Connection -> String -> Array Foreign -> (Nullable Error -> Effect Unit) -> Effect Unit
foreign import allImpl :: Connection -> String -> Array Foreign -> (Nullable Error -> Nullable (Array Json) -> Effect Unit) -> Effect Unit

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

getScrobbles :: Connection -> Int -> Int -> Aff (Array Listen)
getScrobbles conn limit offset = do
  rows <- queryAll conn "SELECT listened_at, track_name, artist_name, release_name, release_mbid, caa_release_mbid FROM scrobbles ORDER BY listened_at DESC LIMIT ? OFFSET ?"
    [ unsafeCoerce limit, unsafeCoerce offset ]
  pure $ fromMaybe [] $ traverse rowToListen rows

rowToListen :: Json -> Maybe Listen
rowToListen json = do
  obj <- toObject json
  listenedAt <- Object.lookup "listened_at" obj >>= (unsafeCoerce >>> Just)
  trackName <- Object.lookup "track_name" obj >>= toString
  artistName <- Object.lookup "artist_name" obj >>= toString
  releaseName <- Object.lookup "release_name" obj >>= toString
  releaseMbid <- Object.lookup "release_mbid" obj >>= toString
  caaReleaseMbid <- Object.lookup "caa_release_mbid" obj >>= toString

  pure $ Listen
    { listenedAt: Just listenedAt
    , trackMetadata: TrackMetadata
        { trackName: Just trackName
        , artistName: Just artistName
        , releaseName: Just releaseName
        , mbidMapping: Just $ MbidMapping
            { releaseMbid: if releaseMbid == "" then Nothing else Just releaseMbid
            , caaReleaseMbid: if caaReleaseMbid == "" then Nothing else Just caaReleaseMbid
            }
        }
    }
