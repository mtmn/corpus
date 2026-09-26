module Server
  ( UserContext
  , ServerEnv
  ) where

import Prelude

import Config (AppConfig, UserConfig)
import Data.Map (Map)
import Data.Maybe (Maybe)
import Db (Connection)
import Effect.Aff (Fiber)
import Effect.Aff.AVar (AVar)
import Effect.Ref (Ref)
import Node.Buffer (Buffer)

-- | Per-user runtime state: DB connection, write lock, background fibers.
type UserContext =
  { conn :: Connection
  , writeLock :: AVar Unit
  , config :: UserConfig
  , slug :: String
  , displayName :: String
  , isRegistered :: Boolean
  , initialSyncFibers :: Array (Fiber Unit)
  , enrichMetadataFiber :: Maybe (Fiber Unit)
  , backupFiber :: Maybe (Fiber Unit)
  , syncFibers :: Array (Fiber Unit)
  }

-- | Shared server state. contextsRef is mutable so approved users can go live without a restart.
-- | tokenCacheRef maps hashed API tokens to slugs so auth skips the per-user
-- | database scan. assetCacheRef memoizes static file contents in memory.
type ServerEnv =
  { contextsRef :: Ref (Array UserContext)
  , tokenCacheRef :: Ref (Map String String)
  , assetCacheRef :: Ref (Map String Buffer)
  , regConn :: Connection
  , regLock :: AVar Unit
  , appConfig :: AppConfig
  }
