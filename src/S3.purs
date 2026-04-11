module S3 where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Exception (Error)
import Node.Buffer (Buffer)
import Data.Nullable (Nullable, toMaybe)

foreign import uploadToS3Impl :: String -> Buffer -> String -> (Nullable Error -> Effect Unit) -> Effect Unit
foreign import existsInS3Impl :: String -> (Boolean -> Effect Unit) -> Effect Unit
foreign import getS3UrlImpl :: String -> String

uploadToS3 :: String -> Buffer -> String -> Aff Unit
uploadToS3 key body contentType = makeAff \cb -> do
  uploadToS3Impl key body contentType \err ->
    case toMaybe err of
      Just e -> cb (Left e)
      Nothing -> cb (Right unit)
  pure nonCanceler

existsInS3 :: String -> Aff Boolean
existsInS3 key = makeAff \cb -> do
  existsInS3Impl key \exists -> cb (Right exists)
  pure nonCanceler

getS3Url :: String -> String
getS3Url = getS3UrlImpl
