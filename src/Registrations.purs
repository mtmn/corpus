module Registrations
  ( NewRegistration
  , Registration
  , getById
  , initRegistrations
  , insertRegistration
  , isReservedSlug
  , listByStatus
  , setStatus
  , slugTaken
  , validSlugFormat
  ) where

import Prelude

import Data.Argonaut.Core (Json, toNumber, toObject, toString)
import Data.Array (elem, mapMaybe, null)
import Data.DateTime.Instant (unInstant)
import Data.Either (hush)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String.Regex (Regex, regex, test)
import Data.String.Regex.Flags (noFlags)
import Data.Time.Duration (Milliseconds(..))
import Data.UUID (genUUID, toString) as UUID
import Db (Connection, queryAll, run, toParam, withTransaction)
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Aff.AVar (AVar)
import Effect.Class (liftEffect)
import Effect.Now (now)
import Foreign.Object as Object

-- | A registration request; timestamps are Unix seconds.
type Registration =
  { id :: String
  , slug :: String
  , displayName :: String
  , email :: String
  , listenbrainzUser :: Maybe String
  , lastfmUser :: Maybe String
  , status :: String
  , createdAt :: Int
  }

-- | Fields supplied by the public registration form.
type NewRegistration =
  { slug :: String
  , displayName :: String
  , email :: String
  , listenbrainzUser :: Maybe String
  , lastfmUser :: Maybe String
  }

-- Paths/route names a slug must never collide with, plus "" (the root user).
reservedSlugs :: Array String
reservedSlugs =
  [ ""
  , "client.js"
  , "favicon.png"
  , "cover.webp"
  , "gutter-left.webp"
  , "gutter-right.webp"
  , "cover"
  , "metrics"
  , "proxy"
  , "stats"
  , "similar"
  , "healthz"
  , "register"
  , "admin"
  , "u"
  , "1"
  ]

slugRegex :: Maybe Regex
slugRegex = hush $ regex "^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$" noFlags

-- | Test whether a slug is lowercase alphanumeric/dashes and has valid edges.
validSlugFormat :: String -> Boolean
validSlugFormat slug = case slugRegex of
  Nothing -> false
  Just re -> test re slug

-- | Test whether a slug collides with a built-in route.
isReservedSlug :: String -> Boolean
isReservedSlug slug = elem slug reservedSlugs

-- | Create the registrations table when necessary.
initRegistrations :: Connection -> Aff Unit
initRegistrations conn =
  run conn
    "CREATE TABLE IF NOT EXISTS registrations (id VARCHAR PRIMARY KEY, slug VARCHAR, display_name VARCHAR, email VARCHAR, listenbrainz_user VARCHAR, lastfm_user VARCHAR, status VARCHAR, created_at BIGINT, decided_at BIGINT)"
    []

nowSeconds :: Effect Int
nowSeconds = do
  Milliseconds ms <- unInstant <$> now
  pure $ Int.round (ms / 1000.0)

-- True if a pending or approved registration already claims this slug (denied ones don't).
-- | Test whether a pending or approved registration owns a slug.
slugTaken :: Connection -> String -> Aff Boolean
slugTaken conn slug = do
  rows <- queryAll conn
    "SELECT 1 FROM registrations WHERE slug = ? AND status IN ('pending','approved')"
    [ toParam slug ]
  pure $ not (null rows)

-- | Insert a pending registration under the shared write lock.
insertRegistration :: Connection -> AVar Unit -> NewRegistration -> Aff Unit
insertRegistration conn lock r = do
  id <- liftEffect $ map UUID.toString UUID.genUUID
  createdAt <- liftEffect nowSeconds
  withTransaction conn lock $
    run conn
      "INSERT INTO registrations (id, slug, display_name, email, listenbrainz_user, lastfm_user, status, created_at, decided_at) VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, 0)"
      [ toParam id
      , toParam r.slug
      , toParam r.displayName
      , toParam r.email
      , toParam (fromMaybe "" r.listenbrainzUser)
      , toParam (fromMaybe "" r.lastfmUser)
      , toParam createdAt
      ]

-- | List registrations with a given status.
listByStatus :: Connection -> String -> Aff (Array Registration)
listByStatus conn status = do
  rows <- queryAll conn
    "SELECT id, slug, display_name, email, listenbrainz_user, lastfm_user, status, created_at FROM registrations WHERE status = ? ORDER BY created_at DESC"
    [ toParam status ]
  pure $ mapMaybe decodeRow rows

-- | Retrieve a registration by its generated ID.
getById :: Connection -> String -> Aff (Maybe Registration)
getById conn id = do
  rows <- queryAll conn
    "SELECT id, slug, display_name, email, listenbrainz_user, lastfm_user, status, created_at FROM registrations WHERE id = ?"
    [ toParam id ]
  pure $ case mapMaybe decodeRow rows of
    [ r ] -> Just r
    _ -> Nothing

-- | Update a registration status under the shared write lock.
setStatus :: Connection -> AVar Unit -> String -> String -> Aff Unit
setStatus conn lock id status = do
  decidedAt <- liftEffect nowSeconds
  withTransaction conn lock $
    run conn "UPDATE registrations SET status = ?, decided_at = ? WHERE id = ?"
      [ toParam status, toParam decidedAt, toParam id ]

decodeRow :: Json -> Maybe Registration
decodeRow json = do
  obj <- toObject json
  let str k = Object.lookup k obj >>= toString
  let
    strM k = case str k of
      Just "" -> Nothing
      other -> other
  id <- str "id"
  slug <- str "slug"
  status <- str "status"
  let
    createdAt = fromMaybe 0 $ Int.fromNumber =<<
      (Object.lookup "created_at" obj >>= toNumber)
  pure
    { id
    , slug
    , displayName: fromMaybe "" (str "display_name")
    , email: fromMaybe "" (str "email")
    , listenbrainzUser: strM "listenbrainz_user"
    , lastfmUser: strM "lastfm_user"
    , status
    , createdAt
    }
