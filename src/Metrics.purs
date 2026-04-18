module Metrics where

import Prelude

import Data.Either (Either(..))
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Exception (error)
import Node.HTTP.Types (IMServer, IncomingMessage, ServerResponse)

-- | Async: serialises all registered metrics to Prometheus text format.
foreign import getMetricsImpl :: (String -> Effect Unit) -> (String -> Effect Unit) -> Effect Unit

-- | The MIME type to use for the /metrics response body.
foreign import getContentType :: Effect String

-- | Attaches a 'finish' listener to `res` so that, once the response is
-- | fully written, the request count, latency histogram, and OTEL span are
-- | updated, and logFn is called with "METHOD path status Nms".
-- | W3C trace-context headers are extracted from `req` for span parenting.
-- | Call once at the top of the request handler before routing.
foreign import observeHttpRequest :: String -> String -> (String -> Effect Unit) -> IncomingMessage IMServer -> ServerResponse -> Effect Unit

-- Sync
foreign import incSyncRuns :: String -> String -> String -> Effect Unit
foreign import incSyncScrobbles :: String -> String -> Int -> Effect Unit
foreign import setSyncLastSuccess :: String -> String -> Effect Unit

-- Metadata enrichment
foreign import incEnrichmentFetch :: String -> String -> String -> Effect Unit
foreign import setEnrichmentQueueSize :: String -> String -> Int -> Effect Unit

-- Cover art
foreign import incCoverRequest :: String -> String -> String -> Effect Unit

-- Database backup
foreign import incDbBackupRun :: String -> String -> Effect Unit
foreign import setDbBackupLastSuccess :: String -> Effect Unit

getMetrics :: Aff String
getMetrics = makeAff \cb -> do
  getMetricsImpl
    (\s -> cb (Right s))
    (\e -> cb (Left (error e)))
  pure nonCanceler
