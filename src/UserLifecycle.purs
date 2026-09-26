module UserLifecycle
  ( startUser
  , cleanupUser
  ) where

import Prelude

import Backup (backupDb)
import Config (UserEntry, s3ConfigFromUser)
import Data.Array (mapMaybe) as Array
import Data.Foldable (for_)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Traversable (traverse)
import Data.Tuple (Tuple(..))
import Db (connect, getOrCreateToken, initDb, initReleaseMetadata)
import Effect.Aff (Aff, forkAff, killFiber, try)
import Effect.Aff.AVar as Avar
import Effect.Exception as Exception
import Log as Log
import Metadata (enrichMetadata)
import Server (UserContext)
import Sync (lbSync, lbSyncLoop, lfSync, lfSyncLoop)

-- | Start one user's DB, sync loops, metadata enrichment, and optional backup.
startUser :: Boolean -> UserEntry -> Aff (Tuple UserContext (Maybe String))
startUser isRegistered { slug, name, config } = do
  Log.info $ "Starting user: " <> if slug == "" then "(root)" else slug
  conn <- connect config.databaseFile
  initDb conn
  initReleaseMetadata conn
  writeLock <- Avar.new unit

  mToken <- getOrCreateToken conn slug
  for_ mToken \token ->
    Log.info $ "User '" <> slug <> "' token: " <> token

  case config.lastfmUser, config.lastfmApiKey of
    Just _, Nothing -> Log.warn $ "User '" <> slug <>
      "': Last.fm sync disabled (missing API key)"
    _, _ -> pure unit

  initialSyncFibers <- traverse forkAff
    $
      [ case config.listenbrainzUser of
          Just username -> Just $ lbSync conn username slug writeLock
          Nothing -> Nothing
      , case config.lastfmUser, config.lastfmApiKey of
          Just lfmUser, Just apiKey -> Just $ lfSync conn apiKey lfmUser slug
            writeLock
          _, _ -> Nothing
      ] # Array.mapMaybe identity

  loopFibers <- traverse forkAff
    $
      [ case config.listenbrainzUser of
          Just username -> Just $ lbSyncLoop conn username slug writeLock
          Nothing -> Nothing
      , case config.lastfmUser, config.lastfmApiKey of
          Just lfmUser, Just apiKey -> Just $ lfSyncLoop conn apiKey lfmUser
            slug
            writeLock
          _, _ -> Nothing
      ] # Array.mapMaybe identity

  enrichMetadataFiber <- forkAff $ enrichMetadata conn config slug
  backupFiber <-
    if config.backupEnabled then Just <$> forkAff
      ( backupDb conn config.databaseFile (s3ConfigFromUser config)
          (Int.toNumber config.backupIntervalHours * 3600000.0)
          slug
      )
    else pure Nothing

  let displayName = fromMaybe (if slug == "" then "root" else slug) name
  pure $ Tuple
    { conn
    , writeLock
    , config
    , slug
    , displayName
    , isRegistered
    , initialSyncFibers
    , enrichMetadataFiber: Just enrichMetadataFiber
    , backupFiber
    , syncFibers: loopFibers
    }
    mToken

-- | Stop a user's background work. Does not close the connection or delete files.
cleanupUser :: UserContext -> Aff Unit
cleanupUser ctx = do
  let label = if ctx.slug == "" then "(root)" else ctx.slug
  Log.info $ "Shutting down user: " <> label
  for_ ctx.initialSyncFibers \fiber ->
    void $ try $ killFiber (Exception.error "Server shutting down") fiber
  for_ ctx.enrichMetadataFiber \fiber ->
    void $ try $ killFiber (Exception.error "Server shutting down") fiber
  for_ ctx.backupFiber \fiber ->
    void $ try $ killFiber (Exception.error "Server shutting down") fiber
  for_ ctx.syncFibers \fiber ->
    void $ try $ killFiber (Exception.error "Server shutting down") fiber
  Log.info $ "Closed user: " <> label
