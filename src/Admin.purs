module Admin
  ( RegisterPayload
  , registrationUserEntry
  , provisionUser
  , removeUser
  , serveApprove
  , serveDeny
  , serveListRegistrations
  , serveListUsers
  , serveRegister
  , serveRemoveUser
  , withAdmin
  ) where

import Prelude

import Auth (parseBearer)
import Config
  ( UserEntry
  , defaultUserConfig
  , fillUserConfigFromEnv
  )
import Data.Argonaut (decodeJson, encodeJson, parseJson, stringify)
import Data.Array (elem, filter, find, mapMaybe, snoc)
import Data.Either (Either(..))
import Data.Foldable (any, for_)
import Data.Maybe (Maybe(..))
import Data.String (trim)
import Data.Tuple (Tuple(..))
import Db (closeConnection)
import Effect.Aff (Aff, try)
import Effect.Class (liftEffect)
import Effect.Exception as Exception
import Effect.Ref as Ref
import Foreign.Object as Object
import Handler
  ( Request
  , Response
  , respond
  , serveBadRequest
  , serveConflict
  , serveInternalError
  , serveNotFound
  , serveUnauthorized
  )
import Log as Log
import Mail as Mail
import Node.FS.Aff as FSA
import Node.HTTP.IncomingMessage as IM
import Node.Stream.Aff (readableToStringUtf8)
import Registrations as Reg
import Server (ServerEnv)
import UserLifecycle (cleanupUser, startUser)

-- | Fields supplied by the public registration form.
type RegisterPayload =
  { slug :: String
  , name :: String
  , email :: String
  , listenbrainzUser :: Maybe String
  , lastfmUser :: Maybe String
  }

-- Trims optional input and treats an empty string as absent.
normalizeOptional :: Maybe String -> Maybe String
normalizeOptional m = case map trim m of
  Just "" -> Nothing
  other -> other

-- Public registration endpoint: validates the slug, records a pending request, emails the admin.
serveRegister :: ServerEnv -> Request -> Response -> Aff Unit
serveRegister env req res =
  if not env.appConfig.registrationEnabled then liftEffect $ serveNotFound res
  else do
    body <- readableToStringUtf8 (IM.toReadable req)
    case parseJson body >>= decodeJson of
      Left _ ->
        liftEffect $ serveBadRequest res "Invalid JSON"
      Right (payload :: RegisterPayload) -> do
        let
          slug = trim payload.slug
          displayName = trim payload.name
          email = trim payload.email
          lb = normalizeOptional payload.listenbrainzUser
          lf = normalizeOptional payload.lastfmUser
        contexts <- liftEffect $ Ref.read env.contextsRef
        let existingSlugs = map _.slug contexts
        if displayName == "" || email == "" then
          liftEffect $ serveBadRequest res "Name and email are required"
        else if not (Reg.validSlugFormat slug) then
          liftEffect $ serveBadRequest res
            "Invalid username: use lowercase letters, numbers and dashes"
        else if Reg.isReservedSlug slug || elem slug existingSlugs then
          liftEffect $ serveConflict res "That username is already taken"
        else do
          taken <- Reg.slugTaken env.regConn slug
          if taken then
            liftEffect $ serveConflict res
              "That username has already been requested"
          else do
            Reg.insertRegistration env.regConn env.regLock
              { slug, displayName, email, listenbrainzUser: lb, lastfmUser: lf }
            notifyAdminNewRegistration env slug displayName email
            liftEffect $ respond "application/json" 200 """{"status":"ok"}"""
              res

serveListRegistrations :: ServerEnv -> Response -> Aff Unit
serveListRegistrations env res = do
  regs <- Reg.listByStatus env.regConn "pending"
  liftEffect $ respond "application/json" 200
    (stringify $ encodeJson (map regToJson regs))
    res

regToJson
  :: Reg.Registration
  -> { id :: String
     , slug :: String
     , name :: String
     , email :: String
     , listenbrainzUser :: Maybe String
     , lastfmUser :: Maybe String
     , status :: String
     , createdAt :: Int
     }
regToJson r =
  { id: r.id
  , slug: r.slug
  , name: r.displayName
  , email: r.email
  , listenbrainzUser: r.listenbrainzUser
  , lastfmUser: r.lastfmUser
  , status: r.status
  , createdAt: r.createdAt
  }

serveApprove :: ServerEnv -> Request -> Response -> Aff Unit
serveApprove env req res = do
  body <- readableToStringUtf8 (IM.toReadable req)
  case parseJson body >>= decodeJson of
    Left _ ->
      liftEffect $ serveBadRequest res "Invalid JSON"
    Right ({ id } :: { id :: String }) -> do
      mReg <- Reg.getById env.regConn id
      case mReg of
        Nothing ->
          liftEffect $ serveNotFound res
        Just reg ->
          if reg.status /= "pending" then
            liftEffect $ serveBadRequest res "Registration is not pending"
          else do
            contexts <- liftEffect $ Ref.read env.contextsRef
            if any (\c -> c.slug == reg.slug) contexts then
              liftEffect $ serveConflict res "That username is already taken"
            else do
              result <- try $ provisionUser env reg
              case result of
                Left err -> do
                  Log.error $ "Failed to provision user '" <> reg.slug <> "': "
                    <> Exception.message err
                  liftEffect $ serveInternalError res
                Right mToken -> do
                  Reg.setStatus env.regConn env.regLock id "approved"
                  notifyApproved env reg mToken
                  liftEffect $ respond "application/json" 200
                    ( stringify $ encodeJson
                        { status: "approved", token: mToken }
                    )
                    res

serveDeny :: ServerEnv -> Request -> Response -> Aff Unit
serveDeny env req res = do
  body <- readableToStringUtf8 (IM.toReadable req)
  case parseJson body >>= decodeJson of
    Left _ ->
      liftEffect $ serveBadRequest res "Invalid JSON"
    Right ({ id } :: { id :: String }) -> do
      mReg <- Reg.getById env.regConn id
      case mReg of
        Nothing ->
          liftEffect $ serveNotFound res
        Just reg ->
          if reg.status /= "pending" then
            liftEffect $ serveBadRequest res "Registration is not pending"
          else do
            Reg.setStatus env.regConn env.regLock id "denied"
            notifyDenied env reg
            liftEffect $ respond "application/json" 200
              """{"status":"denied"}"""
              res

serveListUsers :: ServerEnv -> Response -> Aff Unit
serveListUsers env res = do
  regs <- Reg.listByStatus env.regConn "approved"
  contexts <- liftEffect $ Ref.read env.contextsRef
  let
    isLiveRegistered reg = any
      (\ctx -> ctx.slug == reg.slug && ctx.isRegistered)
      contexts
  liftEffect $ respond "application/json" 200
    ( stringify $ encodeJson
        ( mapMaybe
            (\r -> if isLiveRegistered r then Just (regToJson r) else Nothing)
            regs
        )
    )
    res

serveRemoveUser :: ServerEnv -> Request -> Response -> Aff Unit
serveRemoveUser env req res = do
  body <- readableToStringUtf8 (IM.toReadable req)
  case parseJson body >>= decodeJson of
    Left _ ->
      liftEffect $ serveBadRequest res "Invalid JSON"
    Right ({ id } :: { id :: String }) -> do
      mReg <- Reg.getById env.regConn id
      case mReg of
        Nothing ->
          liftEffect $ serveNotFound res
        Just reg ->
          if reg.status /= "approved" then
            liftEffect $ serveBadRequest res "User is not active"
          else do
            removed <- removeUser env reg
            if removed then
              liftEffect $ respond "application/json" 200
                """{"status":"removed"}"""
                res
            else
              liftEffect $ serveBadRequest res
                "User is not an active self-registered user"

-- | Removes an approved user: stops its fibers, drops it from the live set,
-- | deletes its database file, and marks the registration 'revoked'.
removeUser :: ServerEnv -> Reg.Registration -> Aff Boolean
removeUser env reg = do
  contexts <- liftEffect $ Ref.read env.contextsRef
  case find (\ctx -> ctx.slug == reg.slug && ctx.isRegistered) contexts of
    Nothing ->
      pure false
    Just ctx -> do
      cleanupUser ctx
      liftEffect $ Ref.modify_
        (filter (\c -> c.slug /= reg.slug || not c.isRegistered))
        env.contextsRef
      void $ try $ closeConnection ctx.conn
      void $ try $ FSA.unlink ctx.config.databaseFile
      Reg.setStatus env.regConn env.regLock reg.id "revoked"
      pure true

-- | Builds a runnable UserEntry from an approved registration (users.json is not touched).
registrationUserEntry :: Reg.Registration -> Aff UserEntry
registrationUserEntry reg = do
  let
    base = defaultUserConfig ("corpus-" <> reg.slug <> ".db")
      reg.listenbrainzUser
      reg.lastfmUser
  config <- fillUserConfigFromEnv base
  pure { slug: reg.slug, name: Just reg.displayName, config }

-- | Starts an approved registration as a live user, returning its new API token.
provisionUser :: ServerEnv -> Reg.Registration -> Aff (Maybe String)
provisionUser env reg = do
  entry <- registrationUserEntry reg
  Tuple ctx mToken <- startUser true entry
  liftEffect $ Ref.modify_ (\cs -> snoc cs ctx) env.contextsRef
  pure mToken

-- Sends an email if SMTP is configured, logging (never throwing) on failure.
sendMailBestEffort :: ServerEnv -> Mail.Mail -> Aff Unit
sendMailBestEffort env mail =
  if Mail.isConfigured env.appConfig.smtp then do
    result <- try $ Mail.sendMail env.appConfig.smtp mail
    case result of
      Left err -> Log.error $ "Failed to send email to " <> mail.to <> ": " <>
        Exception.message err
      Right _ -> Log.info $ "Sent email to " <> mail.to
  else
    Log.warn "SMTP not configured; skipping email"

notifyAdminNewRegistration
  :: ServerEnv -> String -> String -> String -> Aff Unit
notifyAdminNewRegistration env slug displayName email =
  for_ env.appConfig.adminEmail \adminAddr ->
    sendMailBestEffort env
      { to: adminAddr
      , subject: "New corpus registration: " <> slug
      , text: "A new registration request is pending.\n\nUsername: " <> slug
          <> "\nName: "
          <> displayName
          <> "\nEmail: "
          <> email
          <> "\n\nApprove or deny it in the admin page."
      }

notifyApproved :: ServerEnv -> Reg.Registration -> Maybe String -> Aff Unit
notifyApproved env reg mToken =
  sendMailBestEffort env
    { to: reg.email
    , subject: "Your corpus account is approved"
    , text: "Hi " <> reg.displayName
        <> ",\n\nYour account '"
        <> reg.slug
        <> "' has been approved."
        <> tokenLine
        <> "\nYou can submit listens to /1/submit-listens using this token.\n"
    }
  where
  tokenLine = case mToken of
    Just t -> "\n\nYour API token: " <> t
    Nothing -> ""

notifyDenied :: ServerEnv -> Reg.Registration -> Aff Unit
notifyDenied env reg =
  sendMailBestEffort env
    { to: reg.email
    , subject: "Your corpus registration"
    , text: "Hi " <> reg.displayName
        <> ",\n\nUnfortunately your registration for '"
        <> reg.slug
        <> "' was not approved.\n"
    }

-- | Gates admin endpoints behind ADMIN_TOKEN: unset -> 404 (disabled), mismatch -> 401.
withAdmin :: ServerEnv -> Request -> Response -> Aff Unit -> Aff Unit
withAdmin env req res action =
  case env.appConfig.adminToken of
    Nothing ->
      liftEffect $ serveNotFound res
    Just secret -> do
      let mToken = parseBearer (Object.lookup "authorization" (IM.headers req))
      if mToken == Just secret then action
      else liftEffect $ serveUnauthorized res
