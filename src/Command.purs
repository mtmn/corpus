module Command where

import Prelude

import Control.Monad.Error.Class (throwError)
import Data.Argonaut (parseJson)
import Data.Argonaut.Core (Json, fromArray, fromBoolean, fromNumber, fromObject, fromString, toArray, toObject, toString)
import Data.Array (catMaybes, find, snoc)
import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Tuple (Tuple(..))
import Db as Db
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Effect.Exception (error)
import Foreign.Object as Object
import Node.Encoding (Encoding(UTF8))
import Node.FS.Aff as FSA
import Node.Process (cwd, exit, lookupEnv)
import Unsafe.Coerce (unsafeCoerce)

foreign import prettyStringify :: Json -> String

getFlag :: String -> Array String -> Maybe String
getFlag flag args = case Array.uncons args of
  Nothing -> Nothing
  Just { head: k, tail: rest } ->
    if k == flag then map _.head (Array.uncons rest)
    else getFlag flag rest

resolvePath :: String -> Maybe String -> String -> String
resolvePath defaultDir mDbPath file = case mDbPath of
  Nothing -> defaultDir <> "/" <> file
  Just dir -> dir <> "/" <> file

encodeUserEntry
  :: { slug :: String, name :: Maybe String, dbFile :: String, lbUser :: Maybe String, lfUser :: Maybe String }
  -> Json
encodeUserEntry e = fromObject $ Object.fromFoldable $ catMaybes
  [ Just $ Tuple "slug" (fromString e.slug)
  , map (\n -> Tuple "name" (fromString n)) e.name
  , Just $ Tuple "config" $ fromObject $ Object.fromFoldable $ catMaybes
      [ Just $ Tuple "databaseFile" (fromString e.dbFile)
      , map (\u -> Tuple "listenbrainzUser" (fromString u)) e.lbUser
      , map (\u -> Tuple "lastfmUser" (fromString u)) e.lfUser
      , Just $ Tuple "coverCacheEnabled" (fromBoolean false)
      , Just $ Tuple "backupEnabled" (fromBoolean false)
      , Just $ Tuple "backupIntervalHours" (fromNumber 24.0)
      ]
  ]

readUsersJson :: String -> Aff (Array Json)
readUsersJson configFile = do
  raw <- FSA.readTextFile UTF8 configFile
  json <- case parseJson raw of
    Left e -> throwError (error $ "Failed to parse " <> configFile <> ": " <> show e)
    Right j -> pure j
  case toObject json >>= Object.lookup "users" >>= toArray of
    Nothing -> throwError (error "Invalid users.json: expected { users: [...] }")
    Just arr -> pure arr

writeUsersJson :: String -> Array Json -> Aff Unit
writeUsersJson configFile users =
  FSA.writeTextFile UTF8 configFile
    $ prettyStringify
    $ fromObject
    $ Object.fromFoldable [ Tuple "users" (fromArray users) ]

run :: String -> Array String -> Aff Unit
run configFile args = case Array.uncons args of
  Just { head: "add-user", tail: rest } -> addUser configFile rest
  Just { head: "reset-token", tail: rest } -> resetToken configFile rest
  Just { head: "list-users" } -> listUsers configFile
  _ -> liftEffect do
    log "Usage:"
    log "  add-user --slug <slug> --db <file> [--name <name>] [--listenbrainz-user <user>] [--lastfm-user <user>]"
    log "  reset-token --slug <slug>"
    log "  list-users"
    exit 1

addUser :: String -> Array String -> Aff Unit
addUser configFile args = do
  let
    mSlug = getFlag "--slug" args
    mDb = getFlag "--db" args
    mName = getFlag "--name" args
    mLbUser = getFlag "--listenbrainz-user" args
    mLfUser = getFlag "--lastfm-user" args
  case mSlug, mDb of
    Nothing, _ -> liftEffect $ log "Error: --slug is required" *> exit 1
    _, Nothing -> liftEffect $ log "Error: --db is required" *> exit 1
    Just slug, Just dbFile -> do
      users <- readUsersJson configFile
      case find (\u -> (toObject u >>= Object.lookup "slug" >>= toString) == Just slug) users of
        Just _ -> liftEffect $ log ("Error: user '" <> slug <> "' already exists") *> exit 1
        Nothing -> do
          let newEntry = encodeUserEntry { slug, name: mName, dbFile, lbUser: mLbUser, lfUser: mLfUser }
          writeUsersJson configFile (snoc users newEntry)
          conn <- Db.connect dbFile
          Db.initDb conn
          Db.initReleaseMetadata conn
          mToken <- Db.getOrCreateToken conn slug
          liftEffect $ for_ mToken \token ->
            log $ "Created user '" <> slug <> "'. API token: " <> token

resetToken :: String -> Array String -> Aff Unit
resetToken configFile args = do
  let mSlug = getFlag "--slug" args
  case mSlug of
    Nothing -> liftEffect $ log "Error: --slug is required" *> exit 1
    Just slug -> do
      users <- readUsersJson configFile
      case find (\u -> (toObject u >>= Object.lookup "slug" >>= toString) == Just slug) users of
        Nothing -> liftEffect $ log ("Error: user '" <> slug <> "' not found") *> exit 1
        Just userJson -> do
          let mDbFile = toObject userJson >>= Object.lookup "config" >>= toObject >>= Object.lookup "databaseFile" >>= toString
          case mDbFile of
            Nothing -> throwError (error $ "Cannot read databaseFile for user '" <> slug <> "'")
            Just dbFile -> do
              defaultDir <- liftEffect cwd
              mDbPath <- liftEffect $ lookupEnv "DATABASE_PATH"
              let fullPath = resolvePath defaultDir mDbPath dbFile
              conn <- Db.connect fullPath
              Db.run conn "DELETE FROM api_tokens WHERE slug = ?" [ unsafeCoerce slug ]
              mToken <- Db.getOrCreateToken conn slug
              liftEffect $ for_ mToken \token ->
                log $ "New token for '" <> slug <> "': " <> token

listUsers :: String -> Aff Unit
listUsers configFile = do
  users <- readUsersJson configFile
  liftEffect $ for_ users \u -> do
    let slug = fromMaybe "(root)" (toObject u >>= Object.lookup "slug" >>= toString)
    let mName = toObject u >>= Object.lookup "name" >>= toString
    log $ case mName of
      Just name -> slug <> " (" <> name <> ")"
      Nothing -> slug
