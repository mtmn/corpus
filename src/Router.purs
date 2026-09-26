module Router
  ( handleRequest
  , routeRequest
  ) where

import Prelude

import Admin
  ( serveApprove
  , serveDeny
  , serveListRegistrations
  , serveListUsers
  , serveRegister
  , serveRemoveUser
  , withAdmin
  )
import Auth
  ( findUserByTokenCached
  , parseAuthToken
  , sanitizeDate
  , submitListenToListen
  , validateTokenJson
  )
import Cosine (serveSimilar)
import Cover (serveCover)
import Data.Argonaut (decodeJson, encodeJson, parseJson, stringify)
import Data.Array (find, length, mapMaybe) as Array
import Data.Either (Either(..))
import Data.Foldable (traverse_)
import Data.Int as Int
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String (Pattern(..), stripPrefix)
import Db
  ( Connection
  , fromString
  , getScrobbles
  , ping
  , upsertScrobble
  , withTransaction
  )
import Effect (Effect)
import Effect.Aff (Aff, launchAff_, try)
import Effect.Aff.AVar (AVar)
import Effect.Class (liftEffect)
import Effect.Exception as Exception
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Foreign.Object as Object
import Handler
  ( Request
  , Response
  , respond
  , serveBadRequest
  , serveError
  , serveInternalError
  , serveNotFound
  , serveUnauthorized
  )
import Log as Log
import Metrics as Metrics
import Node.Buffer (Buffer)
import Node.Encoding (Encoding(UTF8))
import Node.FS.Aff as FSA
import Node.HTTP.IncomingMessage as IM
import Node.HTTP.OutgoingMessage (setHeader, toWriteable)
import Node.HTTP.ServerResponse (setStatusCode, toOutgoingMessage)
import Node.Stream (end, write, writeString)
import Node.Stream.Aff (readableToStringUtf8)
import Server (ServerEnv, UserContext)
import Stats (getStats)
import Templates (indexHtml)
import Types (ListenBrainzSubmitPayload(..))
import Web.URL (URL)
import Web.URL as URL
import Web.URL.URLSearchParams as URLSearchParams

normalizePath :: String -> String
normalizePath path = case stripPrefix (Pattern "/u/") path of
  Just _ -> "/u/:slug"
  Nothing -> path

-- | Incoming request dispatcher. Wraps every request in metrics/logging and
-- | catches unhandled errors.
handleRequest :: ServerEnv -> Request -> Response -> Effect Unit
handleRequest env req res = do
  let method = IM.method req
  let rawUrl = IM.url req
  contexts <- Ref.read env.contextsRef
  case URL.fromRelative rawUrl "http://localhost" of
    Nothing ->
      serveNotFound res
    Just url -> do
      let path = URL.pathname url
      Metrics.wrapRequest method (normalizePath path) Log.info req res do
        launchAff_ $ do
          result <- try $ routeRequest env contexts req url path res
          case result of
            Left err -> do
              Log.error $ "Internal server error: " <> Exception.message err
              liftEffect $ serveInternalError res
            Right _ ->
              pure unit

-- | Public user list for the index page. Computed on demand so static asset
-- | and API requests do not pay for a list they never use.
userList :: Array UserContext -> Array { slug :: String, name :: String }
userList = map (\ctx -> { slug: ctx.slug, name: ctx.displayName })

-- | Route a request to the appropriate handler.
routeRequest
  :: ServerEnv
  -> Array UserContext
  -> Request
  -> URL
  -> String
  -> Response
  -> Aff Unit
routeRequest env contexts req url path res = liftEffect $ case path of
  "/client.js" ->
    serveClientJs env.assetCacheRef res
  "/style.css" ->
    serveAsset env.assetCacheRef "text/css" "assets/style.css" res
  "/favicon.png" ->
    serveAsset env.assetCacheRef "image/png" "assets/favicon.png" res
  "/cover.webp" ->
    serveAsset env.assetCacheRef "image/webp" "assets/cover.webp" res
  "/gutter-left.webp" ->
    serveAsset env.assetCacheRef "image/webp" "assets/left.webp" res
  "/gutter-right.webp" ->
    serveAsset env.assetCacheRef "image/webp" "assets/right.webp" res
  "/" ->
    serveIndex regEnabled (userList contexts) "" res
  "/register" ->
    if IM.method req == "POST" then
      launchAff_ $ serveRegister env req res
    else
      serveIndex regEnabled (userList contexts) "" res
  "/admin" ->
    serveIndex regEnabled (userList contexts) "" res
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
    withUser url \ctx -> launchAff_ $ serveCover serveNotFound ctx.config
      ctx.slug
      url
      res
  "/similar" ->
    withUser url \ctx -> serveSimilar serveBadRequest serveError ctx.slug
      ctx.config
      url
      res
  "/healthz" ->
    withUser url \ctx -> serveHealthz ctx.conn res
  "/1/validate-token" ->
    if IM.method req == "GET" then
      launchAff_ $ serveValidateToken env.tokenCacheRef contexts req res
    else
      liftEffect $ serveBadRequest res "Method not allowed"
  "/1/submit-listens" ->
    if IM.method req == "POST" then
      launchAff_ $ withUserFromToken env.tokenCacheRef contexts req res \ctx ->
        serveSubmitListens ctx.slug ctx.conn ctx.writeLock req res
    else
      liftEffect $ serveBadRequest res "Method not allowed"
  _ ->
    case stripPrefix (Pattern "/u/") path of
      Just slug ->
        serveIndex regEnabled (userList contexts) slug res
      Nothing -> do
        Log.warn $ "Path not found: " <> path
        serveNotFound res
  where
  regEnabled = env.appConfig.registrationEnabled
  withUser urlParam f =
    let
      slug = fromMaybe "" (getQueryParam "user" urlParam)
    in
      case Array.find (\c -> c.slug == slug) contexts of
        Nothing -> do
          Log.warn $ "Unknown user: " <> show slug
          serveNotFound res
        Just ctx ->
          f ctx

withUserFromToken
  :: Ref (Map String String)
  -> Array UserContext
  -> Request
  -> Response
  -> (UserContext -> Aff Unit)
  -> Aff Unit
withUserFromToken cacheRef contextsParam reqParam resParam f = do
  let
    mToken = parseAuthToken
      (Object.lookup "authorization" (IM.headers reqParam))
  case mToken of
    Nothing -> liftEffect $ do
      Log.warn "Missing or invalid Authorization header"
      serveUnauthorized resParam
    Just tokenValue -> do
      mCtx <- findUserByTokenCached cacheRef contextsParam tokenValue
      case mCtx of
        Nothing -> liftEffect $ do
          Log.warn $ "Unknown API token provided"
          serveUnauthorized resParam
        Just ctx ->
          f ctx

-- ListenBrainz `validate-token` endpoint.
serveValidateToken
  :: Ref (Map String String)
  -> Array UserContext
  -> Request
  -> Response
  -> Aff Unit
serveValidateToken cacheRef contextsParam reqParam resParam = do
  let
    mToken = parseAuthToken
      (Object.lookup "authorization" (IM.headers reqParam))
  case mToken of
    Nothing -> liftEffect $ do
      Log.warn "validate-token: missing or invalid Authorization header"
      respond "application/json" 401
        """{"code":401,"error":"You need to provide an Authorization header."}"""
        resParam
    Just tokenValue -> do
      mCtx <- findUserByTokenCached cacheRef contextsParam tokenValue
      liftEffect $ respond "application/json" 200
        (validateTokenJson (map _.displayName mCtx))
        resParam

serveIndex
  :: Boolean
  -> Array { slug :: String, name :: String }
  -> String
  -> Response
  -> Effect Unit
serveIndex registrationEnabled allUsers slug res = do
  setHeader "Content-Type" "text/html" (toOutgoingMessage res)
  setStatusCode 200 res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 (indexHtml registrationEnabled slug allUsers)
  end w

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

-- | Write a buffer as the full response body.
serveBuffer :: Response -> Buffer -> Effect Unit
serveBuffer res buf = do
  setStatusCode 200 res
  let w = toWriteable (toOutgoingMessage res)
  void $ write w buf
  end w

-- | Read a file once, then serve it from the in-memory cache. Cached entries
-- | live until restart; redeploys restart the server anyway.
serveCachedFile
  :: Ref (Map String Buffer)
  -> String
  -> Effect Unit
  -> Response
  -> Aff Unit
serveCachedFile cacheRef path serveNotFoundFn res = do
  cached <- liftEffect $ Ref.read cacheRef
  case Map.lookup path cached of
    Just buf -> liftEffect $ serveBuffer res buf
    Nothing -> do
      result <- try $ FSA.readFile path
      case result of
        Right buf -> liftEffect $ do
          Ref.modify_ (Map.insert path buf) cacheRef
          serveBuffer res buf
        Left _ ->
          liftEffect serveNotFoundFn

serveClientJs :: Ref (Map String Buffer) -> Response -> Effect Unit
serveClientJs cacheRef res = do
  setHeader "Content-Type" "application/javascript" (toOutgoingMessage res)
  setHeader "Cache-Control" "public, max-age=86400" (toOutgoingMessage res)
  launchAff_ $
    serveCachedFile cacheRef "client.js" (serveNotFound res) res

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

serveAsset
  :: Ref (Map String Buffer) -> String -> String -> Response -> Effect Unit
serveAsset cacheRef contentType path res = do
  setHeader "Content-Type" contentType (toOutgoingMessage res)
  setHeader "Cache-Control" "public, max-age=86400" (toOutgoingMessage res)
  launchAff_ $
    serveCachedFile cacheRef path (serveNotFound res) res

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
          void $ writeString w UTF8 $ """{"status":"error","message":"""
            <> show (Exception.message err)
            <> "}"
      end w

serveSubmitListens
  :: String -> Connection -> AVar Unit -> Request -> Response -> Aff Unit
serveSubmitListens slug db lock req res = do
  body <- readableToStringUtf8 (IM.toReadable req)
  case parseJson body >>= decodeJson of
    Left err ->
      liftEffect $ serveBadRequest res $ "Invalid JSON: " <> show err
    Right (ListenBrainzSubmitPayload { listenType, payload }) -> do
      let
        listens = Array.mapMaybe (submitListenToListen listenType) payload
      withTransaction db lock $ traverse_ (upsertScrobble db) listens
      liftEffect $ do
        Metrics.incSyncScrobbles slug "api" (Array.length listens)
        setHeader "Content-Type" "application/json" (toOutgoingMessage res)
        setStatusCode 200 res
        let w = toWriteable (toOutgoingMessage res)
        void $ writeString w UTF8 """{"status":"ok"}"""
        end w
