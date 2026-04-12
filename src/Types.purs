module Types where

import Prelude

import Data.Argonaut (class DecodeJson, class EncodeJson, decodeJson, encodeJson, (.:), (.:?), (:=), (~>))
import Data.Argonaut.Core (jsonEmptyObject)
import Data.Maybe (Maybe)
import Data.Generic.Rep (class Generic)
import Data.Show.Generic (genericShow)

newtype ListenBrainzResponse = ListenBrainzResponse
  { payload :: Payload
  }

derive instance eqListenBrainzResponse :: Eq ListenBrainzResponse
derive instance genericListenBrainzResponse :: Generic ListenBrainzResponse _
instance showListenBrainzResponse :: Show ListenBrainzResponse where
  show = genericShow

instance DecodeJson ListenBrainzResponse where
  decodeJson json = do
    obj <- decodeJson json
    payload <- obj .: "payload"
    pure $ ListenBrainzResponse { payload }

instance EncodeJson ListenBrainzResponse where
  encodeJson (ListenBrainzResponse { payload }) =
    "payload" := encodeJson payload
      ~> jsonEmptyObject

newtype Payload = Payload
  { listens :: Array Listen
  }

derive instance eqPayload :: Eq Payload
derive instance genericPayload :: Generic Payload _
instance showPayload :: Show Payload where
  show = genericShow

instance DecodeJson Payload where
  decodeJson json = do
    obj <- decodeJson json
    listens <- obj .: "listens"
    pure $ Payload { listens }

instance EncodeJson Payload where
  encodeJson (Payload { listens }) =
    "listens" := encodeJson listens
      ~> jsonEmptyObject

newtype Listen = Listen
  { trackMetadata :: TrackMetadata
  , listenedAt :: Maybe Int
  }

derive instance eqListen :: Eq Listen
derive instance genericListen :: Generic Listen _
instance showListen :: Show Listen where
  show = genericShow

instance DecodeJson Listen where
  decodeJson json = do
    obj <- decodeJson json
    trackMetadata <- obj .: "track_metadata"
    listenedAt <- obj .:? "listened_at"
    pure $ Listen { trackMetadata, listenedAt }

instance EncodeJson Listen where
  encodeJson (Listen { trackMetadata, listenedAt }) =
    "track_metadata" := encodeJson trackMetadata
      ~> "listened_at" := encodeJson listenedAt
      ~> jsonEmptyObject

newtype TrackMetadata = TrackMetadata
  { trackName :: Maybe String
  , artistName :: Maybe String
  , releaseName :: Maybe String
  , mbidMapping :: Maybe MbidMapping
  , genre :: Maybe String
  }

derive instance eqTrackMetadata :: Eq TrackMetadata
derive instance genericTrackMetadata :: Generic TrackMetadata _
instance showTrackMetadata :: Show TrackMetadata where
  show = genericShow

instance DecodeJson TrackMetadata where
  decodeJson json = do
    obj <- decodeJson json
    trackName <- obj .:? "track_name"
    artistName <- obj .:? "artist_name"
    releaseName <- obj .:? "release_name"
    mbidMapping <- obj .:? "mbid_mapping"
    genre <- obj .:? "genre"
    pure $ TrackMetadata { trackName, artistName, releaseName, mbidMapping, genre }

instance EncodeJson TrackMetadata where
  encodeJson (TrackMetadata { trackName, artistName, releaseName, mbidMapping, genre }) =
    "track_name" := encodeJson trackName
      ~> "artist_name" := encodeJson artistName
      ~> "release_name" := encodeJson releaseName
      ~> "mbid_mapping" := encodeJson mbidMapping
      ~> "genre" := encodeJson genre
      ~> jsonEmptyObject

newtype MbidMapping = MbidMapping
  { releaseMbid :: Maybe String
  , caaReleaseMbid :: Maybe String
  }

derive instance eqMbidMapping :: Eq MbidMapping
derive instance genericMbidMapping :: Generic MbidMapping _
instance showMbidMapping :: Show MbidMapping where
  show = genericShow

instance DecodeJson MbidMapping where
  decodeJson json = do
    obj <- decodeJson json
    releaseMbid <- obj .:? "release_mbid"
    caaReleaseMbid <- obj .:? "caa_release_mbid"
    pure $ MbidMapping { releaseMbid, caaReleaseMbid }

instance EncodeJson MbidMapping where
  encodeJson (MbidMapping { releaseMbid, caaReleaseMbid }) =
    "release_mbid" := encodeJson releaseMbid
      ~> "caa_release_mbid" := encodeJson caaReleaseMbid
      ~> jsonEmptyObject

newtype StatsEntry = StatsEntry
  { name :: String
  , count :: Int
  }

derive instance eqStatsEntry :: Eq StatsEntry
derive instance genericStatsEntry :: Generic StatsEntry _
instance showStatsEntry :: Show StatsEntry where
  show = genericShow

instance DecodeJson StatsEntry where
  decodeJson json = do
    obj <- decodeJson json
    name <- obj .: "name"
    count <- obj .: "count"
    pure $ StatsEntry { name, count }

instance EncodeJson StatsEntry where
  encodeJson (StatsEntry { name, count }) =
    "name" := encodeJson name
      ~> "count" := encodeJson count
      ~> jsonEmptyObject

newtype Stats = Stats
  { genres :: Array StatsEntry
  , labels :: Array StatsEntry
  , years :: Array StatsEntry
  }

derive instance eqStats :: Eq Stats
derive instance genericStats :: Generic Stats _
instance showStats :: Show Stats where
  show = genericShow

instance DecodeJson Stats where
  decodeJson json = do
    obj <- decodeJson json
    genres <- obj .: "genres"
    labels <- obj .: "labels"
    years <- obj .: "years"
    pure $ Stats { genres, labels, years }

instance EncodeJson Stats where
  encodeJson (Stats { genres, labels, years }) =
    "genres" := encodeJson genres
      ~> "labels" := encodeJson labels
      ~> "years" := encodeJson years
      ~> jsonEmptyObject
