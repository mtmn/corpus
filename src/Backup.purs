module Backup
  ( backupDb
  , dbBaseName
  ) where

import Prelude

import Config (S3Config)
import Control.Monad.Rec.Class (forever)
import Data.Array (last)
import Data.Either (Either(..))
import Data.Formatter.DateTime (formatDateTime)
import Data.Maybe (fromMaybe)
import Data.String (Pattern(..), split, stripSuffix)
import Data.Time.Duration (Milliseconds(..))
import Db (Connection, checkpoint)
import Effect.Aff (Aff, delay, try)
import Effect.Class (liftEffect)
import Effect.Exception (message)
import Effect.Now (nowDateTime)
import Log as Log
import Metrics as Metrics
import Node.FS.Aff as FSA
import S3 as S3

-- | Derive the backup-safe database filename from a path.
dbBaseName :: String -> String
dbBaseName path =
  let
    parts = split (Pattern "/") path
    name = fromMaybe path (last parts)
  in
    fromMaybe name (stripSuffix (Pattern ".db") name)

performBackup :: Connection -> String -> S3Config -> String -> Aff Unit
performBackup conn dbFile s3cfg slug = do
  checkpoint conn
  dt <- liftEffect nowDateTime
  let
    ts = case formatDateTime "YYYY-MM-DDTHH:mm:ss" dt of
      Right s -> s
      Left _ -> "unknown"
  let key = "backups/" <> dbBaseName dbFile <> "-" <> ts <> ".db"
  buf <- FSA.readFile dbFile
  S3.uploadToS3 s3cfg key buf "application/octet-stream"
  Log.info $ "Backup uploaded to S3: " <> key
  liftEffect $ Metrics.setDbBackupLastSuccess slug
  liftEffect $ Metrics.incDbBackupRun slug "success"

-- | Upload a database backup when the configured interval has elapsed.
backupDb :: Connection -> String -> S3Config -> Number -> String -> Aff Unit
backupDb conn dbFile s3cfg intervalMs slug = forever do
  delay (Milliseconds intervalMs)
  result <- try $ performBackup conn dbFile s3cfg slug
  case result of
    Left err -> do
      Log.error $ "Backup failed: " <> message err
      liftEffect $ Metrics.incDbBackupRun slug "error"
    Right _ ->
      pure unit
