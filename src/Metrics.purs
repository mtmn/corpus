module Metrics
  ( getContentType
  , getMetrics
  , incCosineRequest
  , incCoverRequest
  , incDbBackupRun
  , incEnrichmentFetch
  , initializeMetrics
  , incSyncRuns
  , incSyncScrobbles
  , setDbBackupLastSuccess
  , setEnrichmentQueueSize
  , setSyncLastSuccess
  , wrapRequest
  ) where

import Prelude

import Data.Either (Either(..))
import Data.Function.Uncurried (Fn2, Fn3, Fn6, runFn2, runFn3, runFn6)
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Exception (error)
import Node.HTTP.Types (IMServer, IncomingMessage, ServerResponse)

-- | Create the Prometheus registry (or a no-op implementation) based on the
-- | runtime configuration flag. Call once at startup before recording metrics.
foreign import initializeMetrics :: Boolean -> Effect Unit

-- | Async: serialises all registered metrics to Prometheus text format.
foreign import getMetricsImpl
  :: Fn2 (String -> Effect Unit) (String -> Effect Unit) (Effect Unit)

-- | The MIME type to use for the /metrics response body.
foreign import getContentType :: Effect String

-- | Attaches a 'finish' listener to record metrics and log the request.
foreign import wrapRequestImpl
  :: Fn6 String String (String -> Effect Unit) (IncomingMessage IMServer)
       ServerResponse
       (Effect Unit)
       (Effect Unit)

-- Sync
foreign import incSyncRunsImpl :: Fn3 String String String (Effect Unit)
foreign import incSyncScrobblesImpl :: Fn3 String String Int (Effect Unit)
foreign import setSyncLastSuccessImpl :: Fn2 String String (Effect Unit)

-- Metadata enrichment
foreign import incEnrichmentFetchImpl :: Fn3 String String String (Effect Unit)
foreign import setEnrichmentQueueSizeImpl :: Fn3 String String Int (Effect Unit)

-- Cover art
foreign import incCoverRequestImpl :: Fn3 String String String (Effect Unit)

-- Cosine Club
foreign import incCosineRequestImpl :: Fn2 String String (Effect Unit)

-- Database backup
foreign import incDbBackupRunImpl :: Fn2 String String (Effect Unit)
-- | Record the timestamp of a successful database backup.
foreign import setDbBackupLastSuccess :: String -> Effect Unit

-- | Collect all registered metrics in Prometheus text exposition format.
getMetrics :: Aff String
getMetrics = makeAff \cb -> do
  runFn2 getMetricsImpl
    (\s -> cb (Right s))
    (\e -> cb (Left (error e)))
  pure nonCanceler

-- | Record request metrics after the supplied HTTP handler finishes.
wrapRequest
  :: String
  -> String
  -> (String -> Effect Unit)
  -> IncomingMessage IMServer
  -> ServerResponse
  -> Effect Unit
  -> Effect Unit
wrapRequest method path logFn req res handler = runFn6 wrapRequestImpl method
  path
  logFn
  req
  res
  handler

-- | Increment a sync-run counter for a user, source, and outcome.
incSyncRuns :: String -> String -> String -> Effect Unit
incSyncRuns u s r = runFn3 incSyncRunsImpl u s r

-- | Add accepted scrobbles to the source-specific counter.
incSyncScrobbles :: String -> String -> Int -> Effect Unit
incSyncScrobbles u s c = runFn3 incSyncScrobblesImpl u s c

-- | Record the timestamp of a successful user sync.
setSyncLastSuccess :: String -> String -> Effect Unit
setSyncLastSuccess u s = runFn2 setSyncLastSuccessImpl u s

-- | Increment a metadata-enrichment fetch outcome counter.
incEnrichmentFetch :: String -> String -> String -> Effect Unit
incEnrichmentFetch u s r = runFn3 incEnrichmentFetchImpl u s r

-- | Set the current metadata-enrichment queue size.
setEnrichmentQueueSize :: String -> String -> Int -> Effect Unit
setEnrichmentQueueSize u t n = runFn3 setEnrichmentQueueSizeImpl u t n

-- | Increment a cover-art request outcome counter.
incCoverRequest :: String -> String -> String -> Effect Unit
incCoverRequest u s r = runFn3 incCoverRequestImpl u s r

-- | Increment a Cosine Club request outcome counter.
incCosineRequest :: String -> String -> Effect Unit
incCosineRequest u r = runFn2 incCosineRequestImpl u r

-- | Increment a database-backup outcome counter.
incDbBackupRun :: String -> String -> Effect Unit
incDbBackupRun u r = runFn2 incDbBackupRunImpl u r
