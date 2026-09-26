module Stats
  ( getStats
  ) where

import Prelude

import Data.Argonaut.Core (Json, toNumber, toObject, toString)
import Data.Array (mapMaybe, (!!))
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Db (Connection, queryAll, toParam)
import Effect.Aff (Aff)
import Foreign (Foreign)
import Foreign.Object as Object
import Types (Stats(..), StatsEntry(..))

-- | Compute aggregated listening statistics for the requested period and section.
getStats
  :: Connection
  -> Maybe String
  -> Maybe String
  -> Maybe String
  -> Maybe String
  -> Aff Stats
getStats conn mPeriod mFrom mTo mSection = do
  let
    buildTimeFilterAndParams
      :: { timeFilter :: String, params :: Array Foreign }
    buildTimeFilterAndParams = case mFrom, mTo of
      Just from, Just to ->
        { timeFilter:
            " AND s.listened_at >= CAST(epoch(CAST(? || ' 00:00:00' AS TIMESTAMP)) AS INTEGER) AND s.listened_at < CAST(epoch(CAST(? || ' 00:00:00' AS TIMESTAMP)) AS INTEGER) + 86400"
        , params: [ toParam from, toParam to ]
        }
      _, _ -> case mPeriod >>= Int.fromString of
        Just days ->
          { timeFilter:
              " AND s.listened_at >= CAST(epoch(now()) AS INTEGER) - ?"
          , params: [ toParam (days * 86400) ]
          }
        Nothing ->
          { timeFilter: "", params: [] }
    { timeFilter, params: buildTimeParams } = buildTimeFilterAndParams
    -- Section requests are bounded at 1000 rows: an unbounded all-time
    -- "show all" over a large scrobble history produces huge JSON payloads
    -- and thousands of DOM rows in the client.
    fetch name q extraParams = case mSection of
      Nothing -> queryAll conn (q <> " LIMIT 50")
        (buildTimeParams <> extraParams)
      Just s | s == name -> queryAll conn (q <> " LIMIT 1000")
        (buildTimeParams <> extraParams)
      Just _ -> pure []
  genreRows <- fetch "genre"
    ( "SELECT rm.genre as name, COUNT(*) as count FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid WHERE rm.genre IS NOT NULL AND rm.genre != ''"
        <> timeFilter
        <> " GROUP BY rm.genre ORDER BY count DESC"
    )
    []
  labelRows <- fetch "label"
    ( "SELECT rm.label as name, COUNT(*) as count FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid WHERE rm.label IS NOT NULL AND rm.label != ''"
        <> timeFilter
        <> " GROUP BY rm.label ORDER BY count DESC"
    )
    []
  yearRows <- fetch "year"
    ( "SELECT CAST(rm.release_year AS VARCHAR) as name, COUNT(*) as count FROM scrobbles s JOIN release_metadata rm ON s.release_mbid = rm.release_mbid WHERE rm.release_year IS NOT NULL"
        <> timeFilter
        <> " GROUP BY rm.release_year ORDER BY rm.release_year DESC"
    )
    []
  artistRows <- fetch "artist"
    ( "SELECT s.artist_name as name, COUNT(*) as count FROM scrobbles s WHERE s.artist_name != ''"
        <> timeFilter
        <> " GROUP BY s.artist_name ORDER BY count DESC"
    )
    []
  trackRows <- fetch "track"
    ( "SELECT s.artist_name || ' — ' || s.track_name as name, COUNT(*) as count FROM scrobbles s WHERE s.track_name != '' AND s.artist_name != ''"
        <> timeFilter
        <> " GROUP BY s.artist_name, s.track_name ORDER BY count DESC"
    )
    []
  -- The total count is only used by the full stats view; section requests
  -- discard it, so skip the extra table scan.
  totalRows <- case mSection of
    Nothing -> queryAll conn
      ("SELECT COUNT(*) as count FROM scrobbles s WHERE 1 = 1" <> timeFilter)
      buildTimeParams
    Just _ -> pure []
  pure $ Stats
    { totalScrobbles: fromMaybe 0 (totalRows !! 0 >>= rowToCount)
    , genres: mapMaybe rowToEntry genreRows
    , labels: mapMaybe rowToEntry labelRows
    , years: mapMaybe rowToEntry yearRows
    , artists: mapMaybe rowToEntry artistRows
    , tracks: mapMaybe rowToEntry trackRows
    }

rowToEntry :: Json -> Maybe StatsEntry
rowToEntry json = do
  obj <- toObject json
  name <- Object.lookup "name" obj >>= toString
  count <- map Int.round $ Object.lookup "count" obj >>= toNumber
  pure $ StatsEntry { name, count }

rowToCount :: Json -> Maybe Int
rowToCount json = do
  obj <- toObject json
  map Int.round $ Object.lookup "count" obj >>= toNumber
