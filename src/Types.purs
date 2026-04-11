module Types where

import Prelude

import Data.Argonaut (class DecodeJson, decodeJson, (.:), (.:?))
import Data.Maybe (Maybe)
import Data.Generic.Rep (class Generic)

newtype ListenBrainzResponse = ListenBrainzResponse
  { payload :: Payload
  }

derive instance eqListenBrainzResponse :: Eq ListenBrainzResponse
derive instance genericListenBrainzResponse :: Generic ListenBrainzResponse _

instance DecodeJson ListenBrainzResponse where
  decodeJson json = do
    obj <- decodeJson json
    payload <- obj .: "payload"
    pure $ ListenBrainzResponse { payload }

newtype Payload = Payload
  { listens :: Array Listen
  }

derive instance eqPayload :: Eq Payload
derive instance genericPayload :: Generic Payload _

instance DecodeJson Payload where
  decodeJson json = do
    obj <- decodeJson json
    listens <- obj .: "listens"
    pure $ Payload { listens }

newtype Listen = Listen
  { trackMetadata :: TrackMetadata
  , listenedAt :: Maybe Int
  }

derive instance eqListen :: Eq Listen
derive instance genericListen :: Generic Listen _

instance DecodeJson Listen where
  decodeJson json = do
    obj <- decodeJson json
    trackMetadata <- obj .: "track_metadata"
    listenedAt <- obj .:? "listened_at"
    pure $ Listen { trackMetadata, listenedAt }

newtype TrackMetadata = TrackMetadata
  { trackName :: Maybe String
  , artistName :: Maybe String
  , releaseName :: Maybe String
  , mbidMapping :: Maybe MbidMapping
  }

derive instance eqTrackMetadata :: Eq TrackMetadata
derive instance genericTrackMetadata :: Generic TrackMetadata _

instance DecodeJson TrackMetadata where
  decodeJson json = do
    obj <- decodeJson json
    trackName <- obj .:? "track_name"
    artistName <- obj .:? "artist_name"
    releaseName <- obj .:? "release_name"
    mbidMapping <- obj .:? "mbid_mapping"
    pure $ TrackMetadata { trackName, artistName, releaseName, mbidMapping }

newtype MbidMapping = MbidMapping
  { releaseMbid :: Maybe String
  , caaReleaseMbid :: Maybe String
  }

derive instance eqMbidMapping :: Eq MbidMapping
derive instance genericMbidMapping :: Generic MbidMapping _

instance DecodeJson MbidMapping where
  decodeJson json = do
    obj <- decodeJson json
    releaseMbid <- obj .:? "release_mbid"
    caaReleaseMbid <- obj .:? "caa_release_mbid"
    pure $ MbidMapping { releaseMbid, caaReleaseMbid }
