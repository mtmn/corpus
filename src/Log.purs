module Log
  ( LogLevel(..)
  , LogMessage
  , debug
  , info
  , warn
  , error
  ) where

import Prelude

import Control.Logger (Logger(..), log)
import Data.DateTime (DateTime)
import Data.Formatter.DateTime (FormatterCommand(..), format)
import Data.List (fromFoldable)
import Effect (Effect)
import Effect.Class (class MonadEffect, liftEffect)
import Effect.Console as Console
import Effect.Now (nowDateTime)

data LogLevel = DEBUG | INFO | WARN | ERROR

instance showLogLevel :: Show LogLevel where
  show DEBUG = "DEBUG"
  show INFO = "INFO"
  show WARN = "WARN"
  show ERROR = "ERROR"

type LogMessage =
  { level :: LogLevel
  , message :: String
  }

formatTimestamp :: DateTime -> String
formatTimestamp dt =
  format (fromFoldable
    [ YearFull
    , Placeholder "-"
    , MonthTwoDigits
    , Placeholder "-"
    , DayOfMonthTwoDigits
    , Placeholder " "
    , Hours24
    , Placeholder ":"
    , MinutesTwoDigits
    , Placeholder ":"
    , SecondsTwoDigits
    , Placeholder "."
    , Milliseconds
    ]) dt

logger :: Logger Effect LogMessage
logger = Logger \{ level, message } -> do
  now <- nowDateTime
  let ts = formatTimestamp now
  Console.log $ "[" <> ts <> "] [" <> show level <> "] " <> message

debug :: forall m. MonadEffect m => String -> m Unit
debug msg = liftEffect $ log logger { level: DEBUG, message: msg }

info :: forall m. MonadEffect m => String -> m Unit
info msg = liftEffect $ log logger { level: INFO, message: msg }

warn :: forall m. MonadEffect m => String -> m Unit
warn msg = liftEffect $ log logger { level: WARN, message: msg }

error :: forall m. MonadEffect m => String -> m Unit
error msg = liftEffect $ log logger { level: ERROR, message: msg }
