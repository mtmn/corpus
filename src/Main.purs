module Main
  ( findUserByToken
  , main
  , parseAuthToken
  , parseBearer
  , sanitizeDate
  , submitListenToListen
  , validateTokenJson
  ) where

import Prelude

import Admin (registrationUserEntry)
import Auth as Auth
import Command as Command
import Config (AppConfig, loadConfig)
import Data.Array (drop, elem, filter, length, null, uncons) as Array
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Traversable (traverse)
import Data.Tuple (fst)
import Db (connect)
import Effect (Effect)
import Effect.Aff (Aff, launchAff_, try)
import Effect.Aff.AVar as Avar
import Effect.Class (liftEffect)
import Effect.Exception as Exception
import Effect.Ref as Ref
import Log as Log
import Node.EventEmitter (on_)
import Node.HTTP (createServer)
import Node.HTTP.Server as Server
import Node.Net.Server (listenTcp, listeningH)
import Node.Process (argv, lookupEnv)
import Registrations as Reg
import Router (handleRequest)
import Server (UserContext)
import Types (Listen, ListenBrainzSubmitListen)
import UserLifecycle (startUser)

-- | Re-export auth helpers so existing tests can keep importing them from Main.
findUserByToken :: Array UserContext -> String -> Aff (Maybe UserContext)
findUserByToken = Auth.findUserByToken

parseAuthToken :: Maybe String -> Maybe String
parseAuthToken = Auth.parseAuthToken

parseBearer :: Maybe String -> Maybe String
parseBearer = Auth.parseBearer

sanitizeDate :: String -> String
sanitizeDate = Auth.sanitizeDate

submitListenToListen :: String -> ListenBrainzSubmitListen -> Maybe Listen
submitListenToListen = Auth.submitListenToListen

validateTokenJson :: Maybe String -> String
validateTokenJson = Auth.validateTokenJson

foreign import dotenvConfig :: Effect Unit

-- | Load configuration and start the HTTP service.
main :: Effect Unit
main = do
  dotenvConfig
  launchAff_ do
    configFile <- liftEffect $ map (fromMaybe "users.json") $ lookupEnv
      "CORPUS_USERS_FILE"
    args <- liftEffect argv
    let commandArgs = Array.drop 2 args
    case Array.uncons commandArgs of
      Just _ ->
        Command.run configFile commandArgs
      Nothing -> do
        result <- try $ loadConfig configFile
        case result of
          Left err -> do
            Log.error $ "Failed to load " <> configFile <> ": " <>
              Exception.message err
            liftEffect $ Exception.throwException err
          Right (appConfig :: AppConfig) -> do
            Log.info $ "Loaded " <> show (Array.length appConfig.users)
              <> " user(s) from "
              <> configFile
            results <- traverse (startUser false) appConfig.users
            let jsonContexts = map fst results
            -- Also start approved registrations, skipping slugs already in users.json.
            regConn <- connect appConfig.registrationsDb
            Reg.initRegistrations regConn
            approved <- Reg.listByStatus regConn "approved"
            let jsonSlugs = map _.slug jsonContexts
            let
              toStart = Array.filter (\r -> not (Array.elem r.slug jsonSlugs))
                approved
            when (not (Array.null toStart))
              $ Log.info
              $ "Starting " <> show (Array.length toStart) <>
                  " approved registered user(s)"
            approvedEntries <- traverse registrationUserEntry toStart
            approvedResults <- traverse (startUser true) approvedEntries
            let contexts = jsonContexts <> map fst approvedResults
            contextsRef <- liftEffect $ Ref.new contexts
            regLock <- Avar.new unit
            let env = { contextsRef, regConn, regLock, appConfig }
            liftEffect $ do
              server <- createServer
              server # on_ Server.requestH (handleRequest env)
              let netServer = Server.toNetServer server

              netServer # on_ listeningH do
                Log.info $ "Server is running on " <> appConfig.host <> ":" <>
                  show appConfig.port

              listenTcp netServer
                { host: appConfig.host, port: appConfig.port, backlog: 128 }
