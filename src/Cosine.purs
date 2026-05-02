module Cosine
  ( fetchCosineSimilar
  , serveSimilar
  ) where

import Prelude

import Config (UserConfig)
import Control.Monad.Error.Class (throwError)
import Data.Array ((!!))
import Data.Either (Either(..), hush)
import Data.Argonaut (parseJson)
import Data.Argonaut.Core (toArray, toObject, toString)
import Data.Maybe (Maybe(..), fromMaybe)
import Effect (Effect)
import Effect.Aff (Aff, launchAff_, try)
import Effect.Class (liftEffect)
import Effect.Exception as Exception
import Fetch (fetch, Method(GET))
import Foreign.Object as Object
import JSURI (encodeURIComponent)
import Log as Log
import Metrics as Metrics
import Node.Encoding (Encoding(UTF8))
import Node.HTTP.OutgoingMessage (setHeader, toWriteable)
import Node.HTTP.ServerResponse (setStatusCode, toOutgoingMessage)
import Node.HTTP.Types (ServerResponse)
import Node.Stream (end, writeString)
import Web.URL (URL)
import Web.URL.URLSearchParams as URLSearchParams
import Web.URL as URL

type Response = ServerResponse

getQueryParam :: String -> URL -> Maybe String
getQueryParam key url = URLSearchParams.get key (URL.searchParams url)

fetchCosineSimilar :: String -> UserConfig -> String -> Aff String
fetchCosineSimilar slug cfg query = do
  let apiKey = fromMaybe "" cfg.cosineApiKey
  if apiKey == "" then do
    Log.warn "cosineApiKey not configured for similar tracks"
    liftEffect $ Metrics.incCosineRequest slug "not_configured"
    pure "{\"data\":{\"similar_tracks\":[]},\"success\":true}"
  else do
    let headers = { "User-Agent": "corpus/1.0 +https://sr.ht/~mtmn/corpus", "Authorization": "Bearer " <> apiKey }
    let searchUrl = "https://cosine.club/api/v1/search?q=" <> (fromMaybe "" $ encodeURIComponent query) <> "&limit=1"
    Log.info $ "Cosine Club: searching for: " <> query
    searchResult <- try $ fetch searchUrl { method: GET, headers: headers }
    case searchResult of
      Left err -> do
        liftEffect $ Metrics.incCosineRequest slug "error"
        throwError err
      Right searchRes ->
        if searchRes.status == 429 then do
          Log.warn "Cosine Club: rate limited on search"
          liftEffect $ Metrics.incCosineRequest slug "rate_limited"
          throwError (Exception.error "Rate limit exceeded")
        else if searchRes.status /= 200 then do
          Log.warn $ "Cosine Club: search returned " <> show searchRes.status
          liftEffect $ Metrics.incCosineRequest slug "error"
          throwError (Exception.error "Search API error")
        else do
          searchBody <- searchRes.text
          let
            mTrackId = do
              json <- hush $ parseJson searchBody
              obj <- toObject json
              arr <- Object.lookup "data" obj >>= toArray
              first <- arr !! 0
              firstObj <- toObject first
              Object.lookup "id" firstObj >>= toString
          case mTrackId of
            Nothing -> do
              Log.info $ "Cosine Club: track not indexed: " <> query
              liftEffect $ Metrics.incCosineRequest slug "not_indexed"
              pure "{\"data\":{\"similar_tracks\":[]},\"success\":true}"
            Just trackId -> do
              let similarUrl = "https://cosine.club/api/v1/tracks/" <> trackId <> "/similar?limit=10"
              Log.info $ "Cosine Club: fetching similar for ID " <> trackId
              similarResult <- try $ fetch similarUrl { method: GET, headers: headers }
              case similarResult of
                Left err -> do
                  liftEffect $ Metrics.incCosineRequest slug "error"
                  throwError err
                Right similarRes ->
                  if similarRes.status == 429 then do
                    Log.warn "Cosine Club: rate limited on similar"
                    liftEffect $ Metrics.incCosineRequest slug "rate_limited"
                    throwError (Exception.error "Rate limit exceeded")
                  else if similarRes.status /= 200 then do
                    Log.warn $ "Cosine Club: similar API returned " <> show similarRes.status
                    liftEffect $ Metrics.incCosineRequest slug "error"
                    throwError (Exception.error "Similar API error")
                  else do
                    liftEffect $ Metrics.incCosineRequest slug "success"
                    similarRes.text

serveSimilar
  :: (Response -> String -> Effect Unit)
  -> (Response -> Int -> String -> String -> Effect Unit)
  -> String
  -> UserConfig
  -> URL
  -> Response
  -> Effect Unit
serveSimilar serveBadRequest serveError slug cfg url res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  launchAff_ do
    let artist = fromMaybe "" (getQueryParam "artist" url)
    let track = fromMaybe "" (getQueryParam "track" url)
    if artist == "" || track == "" then
      liftEffect $ serveBadRequest res "Artist and track parameters are required"
    else do
      let query = artist <> " - " <> track
      result <- try $ fetchCosineSimilar slug cfg query
      case result of
        Left err -> do
          Log.error $ "Cosine Club API error: " <> Exception.message err
          liftEffect $ serveError res 502 "Bad Gateway" "Failed to fetch similar tracks"
        Right responseBody ->
          liftEffect $ do
            setStatusCode 200 res
            let w = toWriteable (toOutgoingMessage res)
            void $ writeString w UTF8 responseBody
            end w
