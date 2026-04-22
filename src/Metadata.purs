module Metadata
  ( MbData
  , GenreSource
  , fetchMusicBrainzRelease
  , fetchLastfmGenre
  , fetchDiscogsGenre
  , fetchFallbackGenre
  , enrichMetadata
  ) where

import Prelude

import Config (UserConfig)
import Control.Monad.Rec.Class (forever)
import Data.Array ((!!), length, null)
import Data.Either (Either(..))
import Data.Foldable (foldM, for_)
import Data.Int (fromString)
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.String (Pattern(..))
import Data.String.Common as String
import Data.Time.Duration (Milliseconds(..))
import Data.Argonaut.Core (toArray, toObject, toString)
import Db (Connection, getArtistReleasesByMbids, getEmptyGenreMbids, getUnenrichedMbids, touchGenreCheckedAt, upsertReleaseMetadata)
import Effect.Aff (Aff, delay, try)
import Effect.Class (liftEffect)
import Effect.Exception as Exception
import Fetch (fetch, Method(GET))
import Fetch.Argonaut.Json (fromJson)
import Foreign.Object as Object
import JSURI (encodeURIComponent)
import Log as Log
import Metrics as Metrics

type MbData = { genre :: Maybe String, label :: Maybe String, year :: Maybe Int }

type GenreSource =
  { name :: String
  , enabled :: Boolean
  , fetch :: Aff (Maybe String)
  }

fetchMusicBrainzRelease :: String -> Aff (Maybe MbData)
fetchMusicBrainzRelease mbid = do
  let url = "https://musicbrainz.org/ws/2/release/" <> mbid <> "?inc=genres+labels+release-groups&fmt=json"
  result <- try $ fetch url { method: GET, headers: { "User-Agent": "corpus/1.0 +https://github.com/mtmn/corpus" } }
  case result of
    Left err -> do
      Log.error $ "MusicBrainz fetch error for " <> mbid <> ": " <> Exception.message err
      pure Nothing
    Right fr | fr.status == 200 -> do
      jsonResult <- try $ fromJson fr.json
      case jsonResult of
        Left err -> do
          Log.error $ "MusicBrainz JSON parse error for " <> mbid <> ": " <> Exception.message err
          pure $ Just { genre: Nothing, label: Nothing, year: Nothing }
        Right json -> do
          let
            genre = do
              obj <- toObject json
              genres <- Object.lookup "genres" obj >>= toArray
              firstGenre <- genres !! 0 >>= toObject
              Object.lookup "name" firstGenre >>= toString
            label = do
              obj <- toObject json
              labelInfo <- Object.lookup "label-info" obj >>= toArray
              firstLabel <- labelInfo !! 0 >>= toObject
              labelObj <- Object.lookup "label" firstLabel >>= toObject
              Object.lookup "name" labelObj >>= toString
            year = do
              obj <- toObject json
              rg <- Object.lookup "release-group" obj >>= toObject
              dateStr <- Object.lookup "first-release-date" rg >>= toString
              String.split (Pattern "-") dateStr !! 0 >>= fromString
          Log.info $ "Enriched " <> mbid <> ": genre=" <> show genre <> " label=" <> show label <> " year=" <> show year
          when (genre == Nothing && label == Nothing && year == Nothing)
            $ Log.warn
            $ "All fields empty for " <> mbid <> " - possible parsing issue or missing data"
          pure $ Just { genre, label, year }
    Right fr | fr.status == 404 -> do
      Log.info $ "MusicBrainz 404 for " <> mbid
      pure $ Just { genre: Nothing, label: Nothing, year: Nothing }
    Right fr -> do
      Log.warn $ "MusicBrainz " <> show fr.status <> " for " <> mbid <> ", will retry"
      pure Nothing

fetchLastfmGenre :: Maybe String -> String -> String -> Aff (Maybe String)
fetchLastfmGenre Nothing _ _ = do
  Log.warn "lastfmApiKey not configured for genre fallback"
  pure Nothing
fetchLastfmGenre (Just k) artist release = do
  let searchUrl = "https://ws.audioscrobbler.com/2.0/?method=album.getinfo&artist=" <> (fromMaybe "" $ encodeURIComponent artist) <> "&album=" <> (fromMaybe "" $ encodeURIComponent release) <> "&format=json" <> "&api_key=" <> k
  Log.info $ "Fetching Last.fm genre for: " <> artist <> " - " <> release
  result <- try $ fetch searchUrl { method: GET }
  case result of
    Right fetchRes | fetchRes.status == 200 -> do
      jsonResult <- try $ fromJson fetchRes.json
      case jsonResult of
        Left err -> do
          Log.error $ "Last.fm genre JSON error: " <> Exception.message err
          pure Nothing
        Right json -> do
          let
            genre = do
              obj <- toObject json
              album <- Object.lookup "album" obj >>= toObject
              tags <- Object.lookup "tags" album >>= toObject
              mTag <- Object.lookup "tag" tags
              let tagArray = fromMaybe [ mTag ] (toArray mTag)
              firstTag <- tagArray !! 0 >>= toObject
              Object.lookup "name" firstTag >>= toString
          pure genre
    _ -> do
      Log.warn "Last.fm genre API request failed"
      pure Nothing

fetchDiscogsGenre :: Maybe String -> String -> String -> Aff (Maybe String)
fetchDiscogsGenre Nothing _ _ = do
  Log.warn "discogsToken not configured for genre fallback"
  pure Nothing
fetchDiscogsGenre (Just t) artist release = do
  let queryStr = artist <> " " <> release
  let searchUrl = "https://api.discogs.com/database/search?q=" <> (fromMaybe "" $ encodeURIComponent queryStr) <> "&type=release&per_page=1"
  Log.info $ "Fetching Discogs genre for: " <> queryStr
  result <- try $ fetch searchUrl { method: GET, headers: { "User-Agent": "corpus/1.0 +https://github.com/mtmn/corpus", "Authorization": "Discogs token=" <> t } }
  case result of
    Right fetchRes | fetchRes.status == 200 -> do
      jsonResult <- try $ fromJson fetchRes.json
      case jsonResult of
        Left err -> do
          Log.error $ "Discogs genre JSON error: " <> Exception.message err
          pure Nothing
        Right json -> do
          let
            genre = do
              obj <- toObject json
              results <- Object.lookup "results" obj >>= toArray
              firstResult <- results !! 0 >>= toObject
              genres <- Object.lookup "genres" firstResult >>= toArray
              genres !! 0 >>= toString
          pure genre
    _ -> do
      Log.warn "Discogs genre API request failed"
      pure Nothing

fetchFallbackGenre :: String -> Array GenreSource -> Aff (Maybe String)
fetchFallbackGenre slug = foldM trySource Nothing
  where
  trySource (Just g) _ = pure (Just g)
  trySource Nothing { name, enabled, fetch }
    | not enabled = pure Nothing
    | otherwise = do
        result <- fetch
        liftEffect $ case result of
          Just _ -> Metrics.incEnrichmentFetch slug name "found"
          Nothing -> Metrics.incEnrichmentFetch slug name "not_found"
        pure result

enrichMetadata :: Connection -> UserConfig -> String -> Aff Unit
enrichMetadata conn cfg slug = forever do
  unenrichedMbids <- getUnenrichedMbids conn 10
  emptyGenreMbids <- getEmptyGenreMbids conn 10
  let allMbids = unenrichedMbids <> emptyGenreMbids

  liftEffect $ Metrics.setEnrichmentQueueSize slug "unenriched" (length unenrichedMbids)
  liftEffect $ Metrics.setEnrichmentQueueSize slug "empty_genre" (length emptyGenreMbids)

  if null allMbids then
    delay (Milliseconds 60000.0)
  else do
    Log.info $ "Processing " <> show (length unenrichedMbids) <> " unenriched + " <> show (length emptyGenreMbids) <> " empty genre releases"
    artistReleaseMap <- getArtistReleasesByMbids conn allMbids
    for_ allMbids \mbid -> do
      delay (Milliseconds 1100.0)
      result <- try $ fetchMusicBrainzRelease mbid
      case result of
        Left err -> do
          Log.error $ "Enrichment error: " <> Exception.message err
          liftEffect $ Metrics.incEnrichmentFetch slug "musicbrainz" "error"
        Right Nothing -> do
          liftEffect $ Metrics.incEnrichmentFetch slug "musicbrainz" "retry"
          upsertReleaseMetadata conn mbid Nothing Nothing Nothing
          touchGenreCheckedAt conn mbid
        Right (Just mbdata) -> do
          liftEffect $ Metrics.incEnrichmentFetch slug "musicbrainz" "success"
          case mbdata.genre of
            Just _ ->
              upsertReleaseMetadata conn mbid mbdata.genre mbdata.label mbdata.year
            Nothing -> do
              let artistRelease = Object.lookup mbid artistReleaseMap
              case artistRelease of
                Just { artist, release } -> do
                  let
                    sources =
                      [ { name: "lastfm", enabled: isJust cfg.lastfmApiKey, fetch: fetchLastfmGenre cfg.lastfmApiKey artist release }
                      , { name: "discogs", enabled: isJust cfg.discogsToken, fetch: fetchDiscogsGenre cfg.discogsToken artist release }
                      ]
                  finalGenre <- fetchFallbackGenre slug sources
                  upsertReleaseMetadata conn mbid finalGenre mbdata.label mbdata.year
                  case finalGenre of
                    Just genre ->
                      Log.info $ "Added fallback genre for " <> mbid <> ": " <> genre
                    Nothing -> do
                      Log.info $ "No genre found in any source for " <> mbid
                      touchGenreCheckedAt conn mbid
                Nothing -> do
                  Log.warn $ "No artist/release info found for MBID " <> mbid <> ", cannot use fallback sources"
                  upsertReleaseMetadata conn mbid mbdata.genre mbdata.label mbdata.year
                  touchGenreCheckedAt conn mbid