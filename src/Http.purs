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

-- External API calls should fail promptly so the caller can use its fallback
-- or retry policy. Cancelling Fetch's Aff aborts its underlying request.
apiTimeout :: Milliseconds
apiTimeout = Milliseconds 10_000.0

-- Image responses are larger than API payloads, but must still be bounded.
imageTimeout :: Milliseconds
imageTimeout = Milliseconds 20_000.0

withTimeout :: forall a. Milliseconds -> String -> Aff a -> Aff a
withTimeout timeout label action = do
  result <- sequential $
    parallel (Right <$> action)
      <|> parallel (delay timeout *> pure (Left $ error $ label <> " timed out"))
  case result of
    Left err -> throwError err
    Right value -> pure value
