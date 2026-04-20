module S3 where

import Prelude

import Config (S3Config)
import Data.Either (Either(..))
import Data.Function.Uncurried (Fn2, Fn3, Fn5, runFn2, runFn3, runFn5)
import Data.Maybe (Maybe(..))
import Data.Nullable (Nullable, toMaybe, toNullable)
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Exception (Error)
import Node.Buffer (Buffer)

type S3ConfigJs =
  { bucket :: Nullable String
  , region :: String
  , accessKeyId :: Nullable String
  , secretAccessKey :: Nullable String
  , endpointUrl :: Nullable String
  , addressingStyle :: Nullable String
  }

toJs :: S3Config -> S3ConfigJs
toJs cfg =
  { bucket: toNullable cfg.bucket
  , region: cfg.region
  , accessKeyId: toNullable cfg.accessKeyId
  , secretAccessKey: toNullable cfg.secretAccessKey
  , endpointUrl: toNullable cfg.endpointUrl
  , addressingStyle: toNullable cfg.addressingStyle
  }

foreign import uploadToS3Impl
  :: Fn5 S3ConfigJs String Buffer String (Nullable Error -> Effect Unit) (Effect Unit)

foreign import existsInS3Impl
  :: Fn3 S3ConfigJs String (Nullable Error -> Boolean -> Effect Unit) (Effect Unit)

foreign import getS3UrlImpl :: Fn2 S3ConfigJs String String

uploadToS3 :: S3Config -> String -> Buffer -> String -> Aff Unit
uploadToS3 cfg key body contentType = makeAff \cb -> do
  runFn5 uploadToS3Impl (toJs cfg) key body contentType \err ->
    case toMaybe err of
      Just e -> cb (Left e)
      Nothing -> cb (Right unit)
  pure nonCanceler

existsInS3 :: S3Config -> String -> Aff Boolean
existsInS3 cfg key = makeAff \cb -> do
  runFn3 existsInS3Impl (toJs cfg) key \err exists ->
    case toMaybe err of
      Just e -> cb (Left e)
      Nothing -> cb (Right exists)
  pure nonCanceler

getS3Url :: S3Config -> String -> String
getS3Url cfg key = runFn2 getS3UrlImpl (toJs cfg) key
