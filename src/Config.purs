module Config where

import Prelude

import Data.Argonaut.Core (Json)
import Data.Argonaut (decodeJson, (.:), (.:?))
import Data.Either (Either(..))
import Data.Int (fromString) as Data.Int
import Data.Maybe (Maybe(..), fromMaybe, isJust, isNothing)
import Data.String (joinWith)
import Data.Traversable (traverse)
import Effect (Effect)
import Control.Monad.Error.Class (throwError)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Class (liftEffect)
import Effect.Exception (error)
import Node.Process (cwd, lookupEnv)

type UserConfig =
  { listenbrainzUser :: Maybe String
  , lastfmUser :: Maybe String
  , lastfmApiKey :: Maybe String
  , discogsToken :: Maybe String
  , cosineApiKey :: Maybe String
  , databaseFile :: String
  , s3Bucket :: Maybe String
  , s3Region :: String
  , awsAccessKeyId :: Maybe String
  , awsSecretAccessKey :: Maybe String
  , awsEndpointUrl :: Maybe String
  , awsS3AddressingStyle :: Maybe String
  , coverCacheEnabled :: Boolean
  , backupEnabled :: Boolean
  , backupIntervalHours :: Int
  , initialSync :: Boolean
  }

type UserEntry =
  { slug :: String
  , config :: UserConfig
  }

type AppConfig =
  { port :: Int
  , metricsEnabled :: Boolean
  , users :: Array UserEntry
  }

type S3Config =
  { bucket :: Maybe String
  , region :: String
  , accessKeyId :: Maybe String
  , secretAccessKey :: Maybe String
  , endpointUrl :: Maybe String
  , addressingStyle :: Maybe String
  }

s3ConfigFromUser :: UserConfig -> S3Config
s3ConfigFromUser cfg =
  { bucket: cfg.s3Bucket
  , region: cfg.s3Region
  , accessKeyId: cfg.awsAccessKeyId
  , secretAccessKey: cfg.awsSecretAccessKey
  , endpointUrl: cfg.awsEndpointUrl
  , addressingStyle: cfg.awsS3AddressingStyle
  }

foreign import loadConfigImpl
  :: String
  -> (String -> Effect Unit)
  -> (Json -> Effect Unit)
  -> Effect Unit

loadConfig :: String -> Aff AppConfig
loadConfig path = do
  json <- makeAff \cb ->
    loadConfigImpl path
      (\msg -> cb (Left (error msg)))
      (\j -> cb (Right j))
      *> pure nonCanceler
  rawUsers <- case decodeUsersJson json of
    Left msg -> throwError (error msg)
    Right users -> pure users
  portStr <- liftEffect $ lookupEnv "PORT"
  lastfmApiKey <- liftEffect $ lookupEnv "LASTFM_API_KEY"
  discogsToken <- liftEffect $ lookupEnv "DISCOGS_TOKEN"
  cosineApiKey <- liftEffect $ lookupEnv "COSINE_API_KEY"
  s3Bucket <- liftEffect $ lookupEnv "S3_BUCKET"
  s3Region <- liftEffect $ map (fromMaybe "us-east-1") $ lookupEnv "S3_REGION"
  awsAccessKeyId <- liftEffect $ lookupEnv "AWS_ACCESS_KEY_ID"
  awsSecretAccessKey <- liftEffect $ lookupEnv "AWS_SECRET_ACCESS_KEY"
  awsEndpointUrl <- liftEffect $ lookupEnv "AWS_ENDPOINT_URL"
  awsS3AddressingStyle <- liftEffect $ lookupEnv "AWS_S3_ADDRESSING_STYLE"
  databasePath <- liftEffect $ lookupEnv "DATABASE_PATH"
  metricsEnabledStr <- liftEffect $ lookupEnv "METRICS_ENABLED"
  defaultPath <- liftEffect cwd
  let
    resolvePath file = case databasePath of
      Nothing -> defaultPath <> "/" <> file
      Just dir -> dir <> "/" <> file
    fillCreds cfg = cfg
      { lastfmApiKey = lastfmApiKey
      , discogsToken = discogsToken
      , cosineApiKey = cosineApiKey
      , s3Bucket = s3Bucket
      , s3Region = s3Region
      , awsAccessKeyId = awsAccessKeyId
      , awsSecretAccessKey = awsSecretAccessKey
      , awsEndpointUrl = awsEndpointUrl
      , awsS3AddressingStyle = awsS3AddressingStyle
      , databaseFile = resolvePath cfg.databaseFile
      }
  let
    port = fromMaybe 8000 (portStr >>= Data.Int.fromString)
    metricsEnabled = metricsEnabledStr == Just "true"
    fullConfig = { port, metricsEnabled, users: map (\u -> u { config = fillCreds u.config }) rawUsers }
  case validateConfig fullConfig of
    Left msg -> throwError (error msg)
    Right cfg -> pure cfg

validateConfig :: AppConfig -> Either String AppConfig
validateConfig cfg = do
  _ <- traverse validateUserEntry cfg.users
  pure cfg

validateUserEntry :: UserEntry -> Either String UserEntry
validateUserEntry entry =
  let
    c = entry.config
    label = if entry.slug == "" then "root" else entry.slug
    lfmMissing =
      if isJust c.lastfmUser && isNothing c.lastfmApiKey then [ "LASTFM_API_KEY" ]
      else []
    s3Missing =
      if c.coverCacheEnabled || c.backupEnabled then
        (if isNothing c.s3Bucket then [ "S3_BUCKET" ] else [])
          <> (if isNothing c.awsAccessKeyId then [ "AWS_ACCESS_KEY_ID" ] else [])
          <> (if isNothing c.awsSecretAccessKey then [ "AWS_SECRET_ACCESS_KEY" ] else [])
          <> (if isNothing c.awsEndpointUrl then [ "AWS_ENDPOINT_URL" ] else [])
      else []
    missing = lfmMissing <> s3Missing
  in
    if missing == [] then Right entry
    else Left ("User '" <> label <> "': missing required env vars: " <> joinWith ", " missing)

mapLeft :: forall a b c. (a -> c) -> Either a b -> Either c b
mapLeft f (Left a) = Left (f a)
mapLeft _ (Right b) = Right b

decodeUsersJson :: Json -> Either String (Array UserEntry)
decodeUsersJson json = do
  obj <- mapLeft show $ decodeJson json
  usersArr <- mapLeft show (obj .: "users" :: Either _ (Array Json))
  traverse decodeUserEntry usersArr

decodeUserEntry :: Json -> Either String UserEntry
decodeUserEntry json = do
  obj <- mapLeft show $ decodeJson json
  slug <- mapLeft show $ obj .: "slug"
  configJson <- mapLeft show (obj .: "config" :: Either _ Json)
  config <- decodeUserConfig configJson
  pure { slug, config }

-- Decodes only the non-sensitive, per-user fields from users.json.
-- Shared credentials are injected from environment variables in loadConfig.
decodeUserConfig :: Json -> Either String UserConfig
decodeUserConfig json = do
  obj <- mapLeft show $ decodeJson json
  listenbrainzUser <- mapLeft show $ obj .:? "listenbrainzUser"
  lastfmUser <- mapLeft show $ obj .:? "lastfmUser"
  databaseFile <- mapLeft show $ obj .: "databaseFile"
  coverCacheEnabled <- mapLeft show $ obj .: "coverCacheEnabled"
  backupEnabled <- mapLeft show $ obj .: "backupEnabled"
  backupIntervalHours <- mapLeft show $ obj .: "backupIntervalHours"
  initialSync <- mapLeft show $ obj .: "initialSync"
  pure
    { listenbrainzUser
    , lastfmUser
    , lastfmApiKey: Nothing
    , discogsToken: Nothing
    , cosineApiKey: Nothing
    , databaseFile
    , s3Bucket: Nothing
    , s3Region: "us-east-1"
    , awsAccessKeyId: Nothing
    , awsSecretAccessKey: Nothing
    , awsEndpointUrl: Nothing
    , awsS3AddressingStyle: Nothing
    , coverCacheEnabled
    , backupEnabled
    , backupIntervalHours
    , initialSync
    }
