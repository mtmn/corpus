module Proxy where

import Prelude

import Effect (Effect)
import Effect.Console as Console

-- Simple proxy that would work with a proper HTTP server implementation
-- For now, this is a placeholder that shows the structure

type ProxyConfig =
  { port :: Int
  , listenBrainzUrl :: String
  }

startProxy :: ProxyConfig -> Effect Unit
startProxy config = do
  Console.log $ "Proxy server would start on port " <> show config.port
  Console.log $ "Proxying requests to: " <> config.listenBrainzUrl
  Console.log "Note: This requires a proper HTTP server implementation in PureScript"

-- For a complete implementation, you would need:
-- 1. HTTP server library (like node-http or similar)
-- 2. HTTP client for making requests to ListenBrainz
-- 3. CORS handling
-- 4. Static file serving

defaultConfig :: ProxyConfig
defaultConfig =
  { port: 8000
  , listenBrainzUrl: "https://api.listenbrainz.org/1/user/mtmn/listens"
  }
