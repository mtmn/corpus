module Auth
  ( findUserByToken
  , findUserByTokenCached
  , parseAuthToken
  , parseBearer
  , sanitizeDate
  , submitListenToListen
  , validateTokenJson
  ) where

import Prelude

import Data.Argonaut (encodeJson, stringify)
import Data.Array as Array
import Data.Either (hush)
import Data.Foldable (for_)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), stripPrefix)
import Data.String.Regex (Regex, parseFlags, regex, replace)
import Db (getTokenUser, sha256)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Server (UserContext)
import Types
  ( Listen(..)
  , ListenBrainzAdditionalInfo(..)
  , ListenBrainzSubmitListen(..)
  , ListenBrainzSubmitTrackMetadata(..)
  , MbidMapping(..)
  , TrackMetadata(..)
  )

-- Extract a token from the API's `Token` authorization scheme.
parseAuthToken :: Maybe String -> Maybe String
parseAuthToken mAuth = do
  token <- mAuth >>= stripPrefix (Pattern "Token ")
  if token == "" then Nothing else Just token

-- | Extract a token from the `Bearer` authorization scheme.
parseBearer :: Maybe String -> Maybe String
parseBearer mAuth = do
  token <- mAuth >>= stripPrefix (Pattern "Bearer ")
  if token == "" then Nothing else Just token

-- | Render a token-validation response body.
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

-- | Find the active user context that owns an API token.
findUserByToken :: Array UserContext -> String -> Aff (Maybe UserContext)
findUserByToken contexts tokenValue = case Array.uncons contexts of
  Nothing ->
    pure Nothing
  Just { head: ctx, tail: rest } -> do
    mSlug <- getTokenUser ctx.conn tokenValue
    case mSlug of
      Just slug | slug == ctx.slug ->
        pure (Just ctx)
      _ ->
        findUserByToken rest tokenValue

-- | Find the owning user for an API token, consulting a process-local cache
-- | of hashed-token to slug before falling back to the per-user database scan.
-- | Cache entries that point at a removed user miss the context lookup and
-- | fall through to the scan, so no explicit invalidation is needed.
findUserByTokenCached
  :: Ref (Map String String)
  -> Array UserContext
  -> String
  -> Aff (Maybe UserContext)
findUserByTokenCached cacheRef contexts tokenValue = do
  let hashed = sha256 tokenValue
  cache <- liftEffect $ Ref.read cacheRef
  case Map.lookup hashed cache of
    Just slug
      | Just ctx <- Array.find (\c -> c.slug == slug) contexts ->
          pure (Just ctx)
    _ -> do
      result <- findUserByToken contexts tokenValue
      for_ result \ctx ->
        liftEffect $ Ref.modify_ (Map.insert hashed ctx.slug) cacheRef
      pure result

-- | Retain only ISO-date characters accepted by the statistics API.
sanitizeDate :: String -> String
sanitizeDate s = case sanitizeDateRe of
  Nothing -> s
  Just re -> replace re "" s

sanitizeDateRe :: Maybe Regex
sanitizeDateRe = hush $ regex "[^0-9\\-]" (parseFlags "g")

-- | Convert an accepted ListenBrainz submission to a local listen.
submitListenToListen :: String -> ListenBrainzSubmitListen -> Maybe Listen
submitListenToListen
  "single"
  (ListenBrainzSubmitListen { listenedAt, trackMetadata }) =
  Just $ Listen
    { listenedAt
    , trackMetadata: submitTrackMetadataToTrackMetadata trackMetadata
    }
submitListenToListen
  "import"
  (ListenBrainzSubmitListen { listenedAt, trackMetadata }) =
  Just $ Listen
    { listenedAt
    , trackMetadata: submitTrackMetadataToTrackMetadata trackMetadata
    }
submitListenToListen "playing_now" _ = Nothing
submitListenToListen _ _ = Nothing

submitTrackMetadataToTrackMetadata
  :: ListenBrainzSubmitTrackMetadata -> TrackMetadata
submitTrackMetadataToTrackMetadata
  ( ListenBrainzSubmitTrackMetadata
      { trackName, artistName, releaseName, additionalInfo }
  ) =
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
