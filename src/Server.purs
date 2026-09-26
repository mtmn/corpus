module Server
  ( UserContext
  , ServerEnv
  ) where

import Prelude

import Config (AppConfig, UserConfig)
import Data.Maybe (Maybe)
import Db (Connection)
import Effect.Aff (Fiber)
import Effect.Aff.AVar (AVar)
import Effect.Ref (Ref)

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
type ServerEnv =
  { contextsRef :: Ref (Array UserContext)
  , regConn :: Connection
  , regLock :: AVar Unit
  , appConfig :: AppConfig
  }
