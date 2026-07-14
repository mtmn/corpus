module Mail where

import Prelude

import Config (SmtpConfig)
import Data.Either (Either(..))
import Data.Function.Uncurried (Fn3, runFn3)
import Data.Maybe (Maybe(..), isJust)
import Data.Nullable (Nullable, toMaybe, toNullable)
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Exception (Error)

type SmtpConfigJs =
  { host :: Nullable String
  , port :: Int
  , user :: Nullable String
  , pass :: Nullable String
  , from :: Nullable String
  }

type Mail =
  { to :: String
  , subject :: String
  , text :: String
  }

toJs :: SmtpConfig -> SmtpConfigJs
toJs cfg =
  { host: toNullable cfg.host
  , port: cfg.port
  , user: toNullable cfg.user
  , pass: toNullable cfg.pass
  , from: toNullable cfg.from
  }

-- | True when SMTP is configured (host present).
isConfigured :: SmtpConfig -> Boolean
isConfigured cfg = isJust cfg.host

foreign import sendMailImpl
  :: Fn3 SmtpConfigJs Mail (Nullable Error -> Effect Unit) (Effect Unit)

-- | Sends one plaintext email over SMTP (STARTTLS). Wrap callers in `try`.
sendMail :: SmtpConfig -> Mail -> Aff Unit
sendMail cfg mail = makeAff \cb -> do
  runFn3 sendMailImpl (toJs cfg) mail \err ->
    case toMaybe err of
      Just e -> cb (Left e)
      Nothing -> cb (Right unit)
  pure nonCanceler
