module Http
  ( apiTimeout
  , imageTimeout
  , withTimeout
  ) where

import Prelude

import Control.Alt ((<|>))
import Control.Monad.Error.Class (throwError)
import Control.Parallel (parallel, sequential)
import Data.Either (Either(..))
import Data.Time.Duration (Milliseconds(..))
import Effect.Aff (Aff, delay)
import Effect.Exception (error)

-- | Timeout used for external API requests.
apiTimeout :: Milliseconds
apiTimeout = Milliseconds 10_000.0

-- | Timeout used for cover-image requests and downloads.
imageTimeout :: Milliseconds
imageTimeout = Milliseconds 20_000.0

-- | Run an action until it finishes or the timeout expires.
withTimeout :: forall a. Milliseconds -> String -> Aff a -> Aff a
withTimeout timeout label action = do
  result <- sequential $
    parallel (Right <$> action)
      <|> parallel
        (delay timeout *> pure (Left $ error $ label <> " timed out"))
  case result of
    Left err -> throwError err
    Right value -> pure value
