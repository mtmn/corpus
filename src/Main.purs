module Main where

import Prelude

import Config (AppConfig, UserConfig, UserEntry, defaultUserConfig, fillUserConfigFromEnv, loadConfig, s3ConfigFromUser)
import Cover (serveCover)
import Cosine (serveSimilar)
import Data.Argonaut (decodeJson, encodeJson, parseJson, stringify)
import Data.Array (find, length, snoc)
import Data.Array as Data.Array
import Data.Either (Either(..), hush)
import Data.Foldable (any, elem, for_, traverse_)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String (Pattern(..), stripPrefix, trim)
import Data.String.Regex (Regex, regex, replace, parseFlags)
import Data.Traversable (traverse)
import Data.Tuple (Tuple(..), fst)
import Db (Connection, backupDb, closeConnection, connect, fromString, getOrCreateToken, getScrobbles, getStats, getTokenUser, initDb, initReleaseMetadata, ping, upsertScrobble, withTransaction)
import Effect (Effect)
import Effect.Aff (Aff, Fiber, forkAff, joinFiber, killFiber, launchAff_, try)
import Effect.Aff.AVar (AVar)
import Effect.Aff.AVar as Avar
import Effect.Class (liftEffect)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Effect.Exception as Exception
import Mail as Mail
import Registrations as Reg
import Node.Encoding (Encoding(UTF8))
import Log as Log
import Node.EventEmitter (on_)
import Metadata (enrichMetadata)
import Metrics as Metrics
import Node.FS.Aff as FSA
import Node.HTTP (createServer)
import Node.HTTP.IncomingMessage as IM
import Node.HTTP.OutgoingMessage (setHeader, toWriteable)
import Node.HTTP.ServerResponse (setStatusCode, toOutgoingMessage)
import Node.HTTP.Server as Server
import Node.Net.Server (listenTcp, listeningH)
import Node.Process (argv, lookupEnv)
import Node.Stream (end, write, writeString)
import Node.Stream.Aff (readableToStringUtf8)
import Sync (lbSync, lbSyncLoop, lfSync, lfSyncLoop)
import Web.URL (URL)
import Web.URL as URL
import Web.URL.URLSearchParams as URLSearchParams
import Command as Command
import Handler (Request, Response, respond, serveBadRequest, serveError, serveInternalError, serveNotFound, serveUnauthorized)
import Templates (indexHtml)
import Types (Listen(..), ListenBrainzAdditionalInfo(..), ListenBrainzSubmitListen(..), ListenBrainzSubmitPayload(..), ListenBrainzSubmitTrackMetadata(..), MbidMapping(..), TrackMetadata(..))
import Foreign.Object as Object

type UserContext =
  { conn :: Connection
  , writeLock :: AVar Unit
  , config :: UserConfig
  , slug :: String
  , displayName :: String
  , enrichMetadataFiber :: Maybe (Fiber Unit)
  , backupFiber :: Maybe (Fiber Unit)
  , syncFibers :: Array (Fiber Unit)
  }

-- Shared server state. contextsRef is mutable so approved users can go live without a restart.
type ServerEnv =
  { contextsRef :: Ref (Array UserContext)
  , regConn :: Connection
  , regLock :: AVar Unit
  , appConfig :: AppConfig
  }

normalizePath :: String -> String
normalizePath path = case stripPrefix (Pattern "/u/") path of
  Just _ -> "/u/:slug"
  Nothing -> path

-- Request handler
-- API endpoints (/proxy, /stats, /cover, /healthz) select the user via ?user=<slug>.
-- Index pages are served at / (root user) and /u/<slug> (named users).
handleRequest :: ServerEnv -> Request -> Response -> Effect Unit
handleRequest env req res = do
  let method = IM.method req
  let rawUrl = IM.url req
  contexts <- Ref.read env.contextsRef
  let allUsers = map (\ctx -> { slug: ctx.slug, name: ctx.displayName }) contexts
  case URL.fromRelative rawUrl "http://localhost" of
    Nothing ->
      serveNotFound res
    Just url -> do
      let path = URL.pathname url
      Metrics.wrapRequest method (normalizePath path) Log.info req res do
        launchAff_ $ do
          result <- try $ routeRequest env contexts req url path allUsers res
          case result of
            Left err -> do
              Log.error $ "Internal server error: " <> Exception.message err
              liftEffect $ serveInternalError res
            Right _ ->
              pure unit

routeRequest :: ServerEnv -> Array UserContext -> Request -> URL -> String -> Array { slug :: String, name :: String } -> Response -> Aff Unit
routeRequest env contexts req url path allUsers res = liftEffect $ case path of
  "/client.js" ->
    serveClientJs res
  "/favicon.png" ->
    serveAsset "image/png" "assets/favicon.png" res
  "/cover.webp" ->
    serveAsset "image/webp" "assets/cover.webp" res
  "/" ->
    serveIndex regEnabled allUsers "" res
  "/register" ->
    if IM.method req == "POST" then
      launchAff_ $ serveRegister env req res
    else
      serveIndex regEnabled allUsers "" res
  "/admin" ->
    serveIndex regEnabled allUsers "" res
  "/admin/registrations" ->
    if IM.method req == "GET" then
      launchAff_ $ withAdmin env req res (serveListRegistrations env res)
    else
      serveBadRequest res "Method not allowed"
  "/admin/registrations/approve" ->
    if IM.method req == "POST" then
      launchAff_ $ withAdmin env req res (serveApprove env req res)
    else
      serveBadRequest res "Method not allowed"
  "/admin/registrations/deny" ->
    if IM.method req == "POST" then
      launchAff_ $ withAdmin env req res (serveDeny env req res)
    else
      serveBadRequest res "Method not allowed"
  "/admin/users" ->
    if IM.method req == "GET" then
      launchAff_ $ withAdmin env req res (serveListUsers env res)
    else
      serveBadRequest res "Method not allowed"
  "/admin/users/remove" ->
    if IM.method req == "POST" then
      launchAff_ $ withAdmin env req res (serveRemoveUser env req res)
    else
      serveBadRequest res "Method not allowed"
  "/metrics" ->
    if env.appConfig.metricsEnabled then serveMetrics res
    else do
      Log.warn "Path not found: /metrics"
      serveNotFound res
  "/proxy" ->
    withUser url \ctx -> serveProxy env.appConfig.corsOrigin ctx.conn url res
  "/stats" ->
    withUser url \ctx -> serveStats ctx.conn url res
  "/cover" ->
    withUser url \ctx -> launchAff_ $ serveCover serveNotFound ctx.config ctx.slug url res
  "/similar" ->
    withUser url \ctx -> serveSimilar serveBadRequest serveError ctx.slug ctx.config url res
  "/healthz" ->
    withUser url \ctx -> serveHealthz ctx.conn res
  "/1/validate-token" ->
    if IM.method req == "GET" then
      launchAff_ $ serveValidateToken contexts req res
    else
      liftEffect $ serveBadRequest res "Method not allowed"
  "/1/submit-listens" ->
    if IM.method req == "POST" then
      launchAff_ $ withUserFromToken contexts req res \ctx ->
        serveSubmitListens ctx.slug ctx.conn ctx.writeLock req res
    else
      liftEffect $ serveBadRequest res "Method not allowed"
  _ ->
    case stripPrefix (Pattern "/u/") path of
      Just slug ->
        serveIndex regEnabled allUsers slug res
      Nothing -> do
        Log.warn $ "Path not found: " <> path
        serveNotFound res
  where
  regEnabled = env.appConfig.registrationEnabled
  withUser urlParam f =
    let
      slug = fromMaybe "" (getQueryParam "user" urlParam)
    in
      case find (\c -> c.slug == slug) contexts of
        Nothing -> do
          Log.warn $ "Unknown user: " <> show slug
          serveNotFound res
        Just ctx ->
          f ctx

withUserFromToken :: Array UserContext -> Request -> Response -> (UserContext -> Aff Unit) -> Aff Unit
withUserFromToken contextsParam reqParam resParam f = do
  let mToken = parseAuthToken (Object.lookup "authorization" (IM.headers reqParam))
  case mToken of
    Nothing -> liftEffect $ do
      Log.warn "Missing or invalid Authorization header"
      serveUnauthorized resParam
    Just tokenValue -> do
      -- We need to check which connection to use to verify the token.
      -- Since initDb creates the table in every user's database, but usually tokens are user-specific.
      -- The current structure assumes each user has their own DB.
      -- We'll try to find the user by checking each context's DB for the token.
      mCtx <- findUserByToken contextsParam tokenValue
      case mCtx of
        Nothing -> liftEffect $ do
          Log.warn $ "Unknown API token provided"
          serveUnauthorized resParam
        Just ctx ->
          f ctx

-- ListenBrainz `validate-token` endpoint. Clients such as Navidrome call this
-- (GET, with `Authorization: Token <token>`) before linking and require a
-- `{"valid": true, "user_name": ...}` response, otherwise they refuse to scrobble.
serveValidateToken :: Array UserContext -> Request -> Response -> Aff Unit
serveValidateToken contextsParam reqParam resParam = do
  let mToken = parseAuthToken (Object.lookup "authorization" (IM.headers reqParam))
  case mToken of
    Nothing -> liftEffect $ do
      Log.warn "validate-token: missing or invalid Authorization header"
      respond "application/json" 401
        """{"code":401,"error":"You need to provide an Authorization header."}"""
        resParam
    Just tokenValue -> do
      mCtx <- findUserByToken contextsParam tokenValue
      liftEffect $ respond "application/json" 200
        (validateTokenJson (map _.displayName mCtx))
        resParam

-- Extract a ListenBrainz API token from an `Authorization: Token <token>` header value.
parseAuthToken :: Maybe String -> Maybe String
parseAuthToken mAuth = mAuth >>= stripPrefix (Pattern "Token ")

-- Build the `validate-token` response body. `Just displayName` means the token
-- resolved to a user (valid); `Nothing` means the token is unknown (invalid).
-- The shape mirrors the real ListenBrainz API so clients like Navidrome accept it.
validateTokenJson :: Maybe String -> String
validateTokenJson Nothing =
  """{"code":200,"message":"Token invalid.","valid":false}"""
validateTokenJson (Just displayName) =
  stringify $ encodeJson
    { code: 200
    , message: "Token valid."
    , valid: true
    , user_name: displayName
    }

findUserByToken :: Array UserContext -> String -> Aff (Maybe UserContext)
findUserByToken contexts tokenValue = case Data.Array.uncons contexts of
  Nothing ->
    pure Nothing
  Just { head: ctx, tail: rest } -> do
    mSlug <- getTokenUser ctx.conn tokenValue
    case mSlug of
      Just slug | slug == ctx.slug ->
        pure (Just ctx)
      _ ->
        findUserByToken rest tokenValue

serveIndex :: Boolean -> Array { slug :: String, name :: String } -> String -> Response -> Effect Unit
serveIndex registrationEnabled allUsers slug res = do
  setHeader "Content-Type" "text/html" (toOutgoingMessage res)
  setStatusCode 200 res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 (indexHtml registrationEnabled slug allUsers)
  end w

-- 409 Conflict helper for slug collisions.
serveConflict :: Response -> String -> Effect Unit
serveConflict res message = respond "text/plain" 409 message res

-- Extract an admin secret from an `Authorization: Bearer <token>` header value.
parseBearer :: Maybe String -> Maybe String
parseBearer mAuth = mAuth >>= stripPrefix (Pattern "Bearer ")

-- Gates admin endpoints behind ADMIN_TOKEN: unset -> 404 (disabled), mismatch -> 401.
withAdmin :: ServerEnv -> Request -> Response -> Aff Unit -> Aff Unit
withAdmin env req res action =
  case env.appConfig.adminToken of
    Nothing ->
      liftEffect $ serveNotFound res
    Just secret -> do
      let mToken = parseBearer (Object.lookup "authorization" (IM.headers req))
      if mToken == Just secret then action
      else liftEffect $ serveUnauthorized res

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
          liftEffect $ serveBadRequest res "Invalid username: use lowercase letters, numbers and dashes"
        else if Reg.isReservedSlug slug || elem slug existingSlugs then
          liftEffect $ serveConflict res "That username is already taken"
        else do
          taken <- Reg.slugTaken env.regConn slug
          if taken then
            liftEffect $ serveConflict res "That username has already been requested"
          else do
            Reg.insertRegistration env.regConn env.regLock
              { slug, displayName, email, listenbrainzUser: lb, lastfmUser: lf }
            notifyAdminNewRegistration env slug displayName email
            liftEffect $ respond "application/json" 200 """{"status":"ok"}""" res

serveListRegistrations :: ServerEnv -> Response -> Aff Unit
serveListRegistrations env res = do
  regs <- Reg.listByStatus env.regConn "pending"
  liftEffect $ respond "application/json" 200 (stringify $ encodeJson (map regToJson regs)) res

regToJson
  :: Reg.Registration
  -> { id :: String, slug :: String, name :: String, email :: String, listenbrainzUser :: Maybe String, lastfmUser :: Maybe String, status :: String, createdAt :: Int }
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
                  Log.error $ "Failed to provision user '" <> reg.slug <> "': " <> Exception.message err
                  liftEffect $ serveInternalError res
                Right mToken -> do
                  Reg.setStatus env.regConn env.regLock id "approved"
                  notifyApproved env reg mToken
                  liftEffect $ respond "application/json" 200
                    (stringify $ encodeJson { status: "approved", token: mToken })
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
        Just reg -> do
          Reg.setStatus env.regConn env.regLock id "denied"
          notifyDenied env reg
          liftEffect $ respond "application/json" 200 """{"status":"denied"}""" res

-- Lists the currently-registered (approved) users.
serveListUsers :: ServerEnv -> Response -> Aff Unit
serveListUsers env res = do
  regs <- Reg.listByStatus env.regConn "approved"
  liftEffect $ respond "application/json" 200 (stringify $ encodeJson (map regToJson regs)) res

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
            removeUser env reg
            liftEffect $ respond "application/json" 200 """{"status":"removed"}""" res

-- Removes an approved user: stops its fibers, drops it from the live set,
-- deletes its database file, and marks the registration 'revoked' (so it stays
-- gone across restarts and the slug frees up for re-registration).
removeUser :: ServerEnv -> Reg.Registration -> Aff Unit
removeUser env reg = do
  contexts <- liftEffect $ Ref.read env.contextsRef
  for_ (find (\c -> c.slug == reg.slug) contexts) \ctx -> do
    cleanupUser ctx
    liftEffect $ Ref.modify_ (Data.Array.filter (\c -> c.slug /= reg.slug)) env.contextsRef
    void $ try $ closeConnection ctx.conn
    void $ try $ FSA.unlink ctx.config.databaseFile
  Reg.setStatus env.regConn env.regLock reg.id "revoked"

-- Builds a runnable UserEntry from an approved registration (users.json is not touched).
registrationUserEntry :: Reg.Registration -> Aff UserEntry
registrationUserEntry reg = do
  let base = defaultUserConfig ("corpus-" <> reg.slug <> ".db") reg.listenbrainzUser reg.lastfmUser
  config <- fillUserConfigFromEnv base
  pure { slug: reg.slug, name: Just reg.displayName, config }

-- Starts an approved registration as a live user, returning its new API token.
provisionUser :: ServerEnv -> Reg.Registration -> Aff (Maybe String)
provisionUser env reg = do
  entry <- registrationUserEntry reg
  Tuple ctx mToken <- startUser entry
  liftEffect $ Ref.modify_ (\cs -> snoc cs ctx) env.contextsRef
  pure mToken

-- Sends an email if SMTP is configured, logging (never throwing) on failure.
sendMailBestEffort :: ServerEnv -> Mail.Mail -> Aff Unit
sendMailBestEffort env mail =
  if Mail.isConfigured env.appConfig.smtp then do
    result <- try $ Mail.sendMail env.appConfig.smtp mail
    case result of
      Left err -> Log.error $ "Failed to send email to " <> mail.to <> ": " <> Exception.message err
      Right _ -> Log.info $ "Sent email to " <> mail.to
  else
    Log.warn "SMTP not configured; skipping email"

notifyAdminNewRegistration :: ServerEnv -> String -> String -> String -> Aff Unit
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

serveMetrics :: Response -> Effect Unit
serveMetrics res = do
  launchAff_ do
    contentType <- liftEffect Metrics.getContentType
    metricsText <- Metrics.getMetrics
    liftEffect $ do
      setHeader "Content-Type" contentType (toOutgoingMessage res)
      setStatusCode 200 res
      let w = toWriteable (toOutgoingMessage res)
      void $ writeString w UTF8 metricsText
      end w

serveClientJs :: Response -> Effect Unit
serveClientJs res = do
  setHeader "Content-Type" "application/javascript" (toOutgoingMessage res)
  launchAff_ do
    result <- try $ FSA.readTextFile UTF8 "client.js"
    liftEffect $ case result of
      Right content -> do
        setStatusCode 200 res
        let w = toWriteable (toOutgoingMessage res)
        void $ writeString w UTF8 content
        end w
      Left err -> do
        Log.error $ "Failed to read client.js: " <> Exception.message err
        serveNotFound res

getQueryParam :: String -> URL -> Maybe String
getQueryParam name url = URLSearchParams.get name (URL.searchParams url)

serveProxy :: String -> Connection -> URL -> Response -> Effect Unit
serveProxy corsOrigin db url res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" corsOrigin (toOutgoingMessage res)

  launchAff_ do
    let limit = fromMaybe 25 (getQueryParam "limit" url >>= Int.fromString)
    let offset = fromMaybe 0 (getQueryParam "offset" url >>= Int.fromString)
    let
      mFilter = do
        field <- getQueryParam "filterField" url >>= fromString
        value <- getQueryParam "filterValue" url
        pure { field, value }

    let mSearch = getQueryParam "search" url
    listens <- getScrobbles db limit offset mFilter mSearch
    let responseBody = stringify $ encodeJson { payload: { listens: listens } }

    liftEffect $ do
      setStatusCode 200 res
      let w = toWriteable (toOutgoingMessage res)
      void $ writeString w UTF8 responseBody
      end w

sanitizeDate :: String -> String
sanitizeDate s = case sanitizeDateRe of
  Nothing -> s
  Just re -> replace re "" s

sanitizeDateRe :: Maybe Regex
sanitizeDateRe = hush $ regex "[^0-9\\-]" (parseFlags "g")

serveStats :: Connection -> URL -> Response -> Effect Unit
serveStats db url res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  launchAff_ do
    let period = getQueryParam "period" url
    let section = getQueryParam "section" url
    let safeDate = map sanitizeDate
    let mFrom = safeDate (getQueryParam "from" url)
    let mTo = safeDate (getQueryParam "to" url)
    stats <- getStats db period mFrom mTo section
    let responseBody = stringify $ encodeJson stats
    liftEffect $ do
      setStatusCode 200 res
      let w = toWriteable (toOutgoingMessage res)
      void $ writeString w UTF8 responseBody
      end w

serveAsset :: String -> String -> Response -> Effect Unit
serveAsset contentType path res = do
  setHeader "Content-Type" contentType (toOutgoingMessage res)
  setHeader "Cache-Control" "public, max-age=86400" (toOutgoingMessage res)
  launchAff_ do
    result <- try $ FSA.readFile path
    liftEffect $ case result of
      Right buf -> do
        setStatusCode 200 res
        let w = toWriteable (toOutgoingMessage res)
        void $ write w buf
        end w
      Left _ ->
        serveNotFound res

serveHealthz :: Connection -> Response -> Effect Unit
serveHealthz db res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  launchAff_ do
    result <- try $ ping db
    liftEffect $ do
      let w = toWriteable (toOutgoingMessage res)
      case result of
        Right _ -> do
          setStatusCode 200 res
          void $ writeString w UTF8 """{"status":"ok"}"""
        Left err -> do
          setStatusCode 503 res
          void $ writeString w UTF8 $ """{"status":"error","message":""" <> show (Exception.message err) <> "}"
      end w

serveSubmitListens :: String -> Connection -> AVar Unit -> Request -> Response -> Aff Unit
serveSubmitListens slug db lock req res = do
  body <- readableToStringUtf8 (IM.toReadable req)
  case parseJson body >>= decodeJson of
    Left err ->
      liftEffect $ serveBadRequest res $ "Invalid JSON: " <> show err
    Right (ListenBrainzSubmitPayload { listenType, payload }) -> do
      let listens = Data.Array.mapMaybe (submitListenToListen listenType) payload
      withTransaction db lock $ traverse_ (upsertScrobble db) listens
      liftEffect $ do
        Metrics.incSyncScrobbles slug "api" (length listens)
        setHeader "Content-Type" "application/json" (toOutgoingMessage res)
        setStatusCode 200 res
        let w = toWriteable (toOutgoingMessage res)
        void $ writeString w UTF8 """{"status":"ok"}"""
        end w

submitListenToListen :: String -> ListenBrainzSubmitListen -> Maybe Listen
submitListenToListen "single" (ListenBrainzSubmitListen { listenedAt, trackMetadata }) =
  Just $ Listen
    { listenedAt
    , trackMetadata: submitTrackMetadataToTrackMetadata trackMetadata
    }
submitListenToListen "import" (ListenBrainzSubmitListen { listenedAt, trackMetadata }) =
  Just $ Listen
    { listenedAt
    , trackMetadata: submitTrackMetadataToTrackMetadata trackMetadata
    }
submitListenToListen "playing_now" _ = Nothing
submitListenToListen _ _ = Nothing

submitTrackMetadataToTrackMetadata :: ListenBrainzSubmitTrackMetadata -> TrackMetadata
submitTrackMetadataToTrackMetadata (ListenBrainzSubmitTrackMetadata { trackName, artistName, releaseName, additionalInfo }) =
  TrackMetadata
    { trackName: Just trackName
    , artistName: Just artistName
    , releaseName
    , genre: Nothing
    , label: Nothing
    , mbidMapping: do
        info <- additionalInfo
        let ListenBrainzAdditionalInfo i = info
        pure $ MbidMapping
          { releaseMbid: i.releaseMbid
          , caaReleaseMbid: i.releaseMbid
          }
    }

startUser :: UserEntry -> Aff (Tuple UserContext (Maybe String))
startUser { slug, name, config } = do
  Log.info $ "Starting user: " <> if slug == "" then "(root)" else slug
  conn <- connect config.databaseFile
  initDb conn
  initReleaseMetadata conn
  writeLock <- Avar.new unit

  mToken <- getOrCreateToken conn slug
  for_ mToken \token ->
    Log.info $ "User '" <> slug <> "' token: " <> token

  case config.lastfmUser, config.lastfmApiKey of
    Just _, Nothing -> Log.warn $ "User '" <> slug <> "': Last.fm sync disabled (missing API key)"
    _, _ -> pure unit

  lbFiber <- case config.listenbrainzUser of
    Just username -> Just <$> forkAff (lbSync conn username slug writeLock)
    Nothing -> pure Nothing
  lfFiber <- case config.lastfmUser, config.lastfmApiKey of
    Just lfmUser, Just apiKey -> Just <$> forkAff (lfSync conn apiKey lfmUser slug writeLock)
    _, _ -> pure Nothing

  -- Join the initial sync fibers so their completion is logged before loops start.
  void $ forkAff do
    for_ lbFiber joinFiber
    for_ lfFiber joinFiber

  -- Spawn the recurring sync loops eagerly; each starts with a 60s delay so
  -- they won't race with the initial sync above. Track them so cleanupUser
  -- can kill them on shutdown.
  loopFibers <- traverse forkAff
    $
      [ case config.listenbrainzUser of
          Just username -> Just $ lbSyncLoop conn username slug writeLock
          Nothing -> Nothing
      , case config.lastfmUser, config.lastfmApiKey of
          Just lfmUser, Just apiKey -> Just $ lfSyncLoop conn apiKey lfmUser slug writeLock
          _, _ -> Nothing
      ] # Data.Array.mapMaybe identity

  enrichMetadataFiber <- forkAff $ enrichMetadata conn config slug
  backupFiber <-
    if config.backupEnabled then Just <$> forkAff (backupDb conn config.databaseFile (s3ConfigFromUser config) (Int.toNumber config.backupIntervalHours * 3600000.0) slug)
    else pure Nothing

  let displayName = fromMaybe (if slug == "" then "root" else slug) name
  pure $ Tuple
    { conn, writeLock, config, slug, displayName, enrichMetadataFiber: Just enrichMetadataFiber, backupFiber, syncFibers: loopFibers }
    mToken

cleanupUser :: UserContext -> Aff Unit
cleanupUser ctx = do
  let label = if ctx.slug == "" then "(root)" else ctx.slug
  Log.info $ "Shutting down user: " <> label
  for_ ctx.enrichMetadataFiber \fiber ->
    void $ try $ killFiber (Exception.error "Server shutting down") fiber
  for_ ctx.backupFiber \fiber ->
    void $ try $ killFiber (Exception.error "Server shutting down") fiber
  for_ ctx.syncFibers \fiber ->
    void $ try $ killFiber (Exception.error "Server shutting down") fiber
  Log.info $ "Closed user: " <> label

foreign import dotenvConfig :: Effect Unit

main :: Effect Unit
main = do
  dotenvConfig
  launchAff_ do
    configFile <- liftEffect $ map (fromMaybe "users.json") $ lookupEnv "CORPUS_USERS_FILE"
    args <- liftEffect argv
    let commandArgs = Data.Array.drop 2 args
    case Data.Array.uncons commandArgs of
      Just _ ->
        Command.run configFile commandArgs
      Nothing -> do
        result <- try $ loadConfig configFile
        case result of
          Left err -> do
            Log.error $ "Failed to load " <> configFile <> ": " <> Exception.message err
            liftEffect $ Exception.throwException err
          Right (appConfig :: AppConfig) -> do
            Log.info $ "Loaded " <> show (length appConfig.users) <> " user(s) from " <> configFile
            results <- traverse startUser appConfig.users
            let jsonContexts = map fst results
            -- Also start approved registrations, skipping slugs already in users.json.
            regConn <- connect appConfig.registrationsDb
            Reg.initRegistrations regConn
            approved <- Reg.listByStatus regConn "approved"
            let jsonSlugs = map _.slug jsonContexts
            let toStart = Data.Array.filter (\r -> not (elem r.slug jsonSlugs)) approved
            when (not (Data.Array.null toStart))
              $ Log.info
              $ "Starting " <> show (length toStart) <> " approved registered user(s)"
            approvedEntries <- traverse registrationUserEntry toStart
            approvedResults <- traverse startUser approvedEntries
            let contexts = jsonContexts <> map fst approvedResults
            contextsRef <- liftEffect $ Ref.new contexts
            regLock <- Avar.new unit
            let env = { contextsRef, regConn, regLock, appConfig }
            liftEffect $ do
              server <- createServer
              server # on_ Server.requestH (handleRequest env)
              let netServer = Server.toNetServer server

              netServer # on_ listeningH do
                Log.info $ "Server is running on " <> appConfig.host <> ":" <> show appConfig.port

              listenTcp netServer { host: appConfig.host, port: appConfig.port, backlog: 128 }
