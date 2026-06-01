module Types where

import Prelude

import Data.Argonaut (class DecodeJson, class EncodeJson, decodeJson, encodeJson, (.:), (.:?), (:=), (~>))
import Data.Argonaut.Decode.Error (JsonDecodeError(..))
import Data.Either (Either(..))
import Data.Argonaut.Core (Json, toArray, jsonEmptyObject, toNumber, toString)
import Data.Int (fromString, fromNumber)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Generic.Rep (class Generic)
import Data.Show.Generic (genericShow)

newtype ListenBrainzSubmitPayload = ListenBrainzSubmitPayload
  { listenType :: String
  , payload :: Array ListenBrainzSubmitListen
  }

derive instance eqListenBrainzSubmitPayload :: Eq ListenBrainzSubmitPayload
derive instance genericListenBrainzSubmitPayload :: Generic ListenBrainzSubmitPayload _
instance showListenBrainzSubmitPayload :: Show ListenBrainzSubmitPayload where
  show = genericShow

instance DecodeJson ListenBrainzSubmitPayload where
  decodeJson json = do
    obj <- decodeJson json
    listenType <- obj .: "listen_type"
    payload <- obj .: "payload"
    pure $ ListenBrainzSubmitPayload { listenType, payload }

newtype ListenBrainzSubmitListen = ListenBrainzSubmitListen
  { listenedAt :: Maybe Int
  , trackMetadata :: ListenBrainzSubmitTrackMetadata
  }

derive instance eqListenBrainzSubmitListen :: Eq ListenBrainzSubmitListen
derive instance genericListenBrainzSubmitListen :: Generic ListenBrainzSubmitListen _
instance showListenBrainzSubmitListen :: Show ListenBrainzSubmitListen where
  show = genericShow

instance DecodeJson ListenBrainzSubmitListen where
  decodeJson json = do
    obj <- decodeJson json
    listenedAt <- obj .:? "listened_at"
    trackMetadata <- obj .: "track_metadata"
    pure $ ListenBrainzSubmitListen { listenedAt, trackMetadata }

newtype ListenBrainzSubmitTrackMetadata = ListenBrainzSubmitTrackMetadata
  { trackName :: String
  , artistName :: String
  , releaseName :: Maybe String
  , additionalInfo :: Maybe ListenBrainzAdditionalInfo
  }

derive instance eqListenBrainzSubmitTrackMetadata :: Eq ListenBrainzSubmitTrackMetadata
derive instance genericListenBrainzSubmitTrackMetadata :: Generic ListenBrainzSubmitTrackMetadata _
instance showListenBrainzSubmitTrackMetadata :: Show ListenBrainzSubmitTrackMetadata where
  show = genericShow

instance DecodeJson ListenBrainzSubmitTrackMetadata where
  decodeJson json = do
    obj <- decodeJson json
    trackName <- obj .: "track_name"
    artistName <- obj .: "artist_name"
    releaseName <- obj .:? "release_name"
    additionalInfo <- obj .:? "additional_info"
    pure $ ListenBrainzSubmitTrackMetadata { trackName, artistName, releaseName, additionalInfo }

newtype ListenBrainzAdditionalInfo = ListenBrainzAdditionalInfo
  { releaseMbid :: Maybe String
  , artistMbids :: Maybe (Array String)
  , recordingMbid :: Maybe String
  }

derive instance eqListenBrainzAdditionalInfo :: Eq ListenBrainzAdditionalInfo
derive instance genericListenBrainzAdditionalInfo :: Generic ListenBrainzAdditionalInfo _
instance showListenBrainzAdditionalInfo :: Show ListenBrainzAdditionalInfo where
  show = genericShow

instance DecodeJson ListenBrainzAdditionalInfo where
  decodeJson json = do
    obj <- decodeJson json
    releaseMbid <- obj .:? "release_mbid"
    artistMbids <- obj .:? "artist_mbids"
    recordingMbid <- obj .:? "recording_mbid"
    pure $ ListenBrainzAdditionalInfo { releaseMbid, artistMbids, recordingMbid }

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
  , label :: Maybe String
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
    label <- obj .:? "label"
    pure $ TrackMetadata { trackName, artistName, releaseName, mbidMapping, genre, label }

instance EncodeJson TrackMetadata where
  encodeJson (TrackMetadata { trackName, artistName, releaseName, mbidMapping, genre, label }) =
    "track_name" := encodeJson trackName
      ~> "artist_name" := encodeJson artistName
      ~> "release_name" := encodeJson releaseName
      ~> "mbid_mapping" := encodeJson mbidMapping
      ~> "genre" := encodeJson genre
      ~> "label" := encodeJson label
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

-- Last.fm API types

newtype LastfmAttr = LastfmAttr
  { totalPages :: Int
  }

derive instance genericLastfmAttr :: Generic LastfmAttr _
instance showLastfmAttr :: Show LastfmAttr where
  show = genericShow

instance decodeJsonLastfmAttr :: DecodeJson LastfmAttr where
  decodeJson json = do
    obj <- decodeJson json
    tpJson <- obj .: "totalPages"
    let
      tpStr = toString tpJson
      tpNum = toNumber tpJson
      parsed = case tpStr >>= fromString of
        Just n -> Just n
        Nothing -> tpNum >>= fromNumber
    case parsed of
      Just n -> pure $ LastfmAttr { totalPages: n }
      Nothing -> Left $ TypeMismatch "Invalid totalPages"

newtype LastfmTrackArray = LastfmTrackArray (Array Json)
newtype LastfmTrackSingle = LastfmTrackSingle Json

data LastfmTracks = LastfmTrackArray' (Array Json) | LastfmTrackSingle' Json

instance showLastfmTracks :: Show LastfmTracks where
  show (LastfmTrackArray' _) = "LastfmTrackArray' _"
  show (LastfmTrackSingle' _) = "LastfmTrackSingle' _"

newtype LastfmRecentTracks = LastfmRecentTracks
  { track :: LastfmTracks
  , attr :: LastfmAttr
  }

derive instance genericLastfmRecentTracks :: Generic LastfmRecentTracks _
instance showLastfmRecentTracks :: Show LastfmRecentTracks where
  show = genericShow

instance decodeJsonLastfmRecentTracks :: DecodeJson LastfmRecentTracks where
  decodeJson json = do
    obj <- decodeJson json
    attr <- obj .: "@attr"
    trackResult <- obj .:? "track"
    tracks <- case trackResult of
      Nothing ->
        pure $ LastfmTrackArray' []
      Just trackJson ->
        case toArray trackJson of
          Just arr ->
            pure $ LastfmTrackArray' arr
          Nothing ->
            pure $ LastfmTrackSingle' trackJson
    pure $ LastfmRecentTracks { track: tracks, attr }

newtype LastfmResponse = LastfmResponse
  { recenttracks :: LastfmRecentTracks
  }

derive instance genericLastfmResponse :: Generic LastfmResponse _
instance showLastfmResponse :: Show LastfmResponse where
  show = genericShow

instance decodeJsonLastfmResponse :: DecodeJson LastfmResponse where
  decodeJson json = do
    obj <- decodeJson json
    recenttracks <- obj .: "recenttracks"
    pure $ LastfmResponse { recenttracks }

newtype LastfmArtist = LastfmArtist { text :: String }

derive instance genericLastfmArtist :: Generic LastfmArtist _
instance showLastfmArtist :: Show LastfmArtist where
  show = genericShow

instance decodeJsonLastfmArtist :: DecodeJson LastfmArtist where
  decodeJson json = do
    obj <- decodeJson json
    text <- obj .: "#text"
    pure $ LastfmArtist { text }

newtype LastfmAlbum = LastfmAlbum
  { text :: Maybe String
  , mbid :: String
  }

derive instance genericLastfmAlbum :: Generic LastfmAlbum _
instance showLastfmAlbum :: Show LastfmAlbum where
  show = genericShow

instance decodeJsonLastfmAlbum :: DecodeJson LastfmAlbum where
  decodeJson json = do
    obj <- decodeJson json
    text <- obj .:? "#text"
    mbid <- fromMaybe "" <$> obj .:? "mbid"
    pure $ LastfmAlbum { text, mbid }

newtype LastfmDate = LastfmDate { uts :: Int }

derive instance genericLastfmDate :: Generic LastfmDate _
instance showLastfmDate :: Show LastfmDate where
  show = genericShow

instance decodeJsonLastfmDate :: DecodeJson LastfmDate where
  decodeJson json = do
    obj <- decodeJson json
    utsStr <- obj .: "uts"
    case fromString utsStr of
      Just n -> pure $ LastfmDate { uts: n }
      Nothing -> Left $ TypeMismatch $ "Invalid uts: " <> utsStr

newtype LastfmTrack = LastfmTrack
  { name :: String
  , artist :: LastfmArtist
  , album :: Maybe LastfmAlbum
  , date :: Maybe LastfmDate
  }

derive instance genericLastfmTrack :: Generic LastfmTrack _
instance showLastfmTrack :: Show LastfmTrack where
  show = genericShow

instance decodeJsonLastfmTrack :: DecodeJson LastfmTrack where
  decodeJson json = do
    obj <- decodeJson json
    name <- obj .: "name"
    artist <- obj .: "artist"
    album <- obj .:? "album"
    date <- obj .:? "date"
    pure $ LastfmTrack { name, artist, album, date }

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
  , artists :: Array StatsEntry
  , tracks :: Array StatsEntry
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
    artists <- obj .: "artists"
    tracks <- obj .: "tracks"
    pure $ Stats { genres, labels, years, artists, tracks }

instance EncodeJson Stats where
  encodeJson (Stats { genres, labels, years, artists, tracks }) =
    "genres" := encodeJson genres
      ~> "labels" := encodeJson labels
      ~> "years" := encodeJson years
      ~> "artists" := encodeJson artists
      ~> "tracks" := encodeJson tracks
      ~> jsonEmptyObject
