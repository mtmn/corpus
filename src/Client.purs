module Client where

import Prelude

import Affjax.Web as AX
import Affjax.ResponseFormat as ResponseFormat
import Data.Argonaut (decodeJson)
import Data.Array (mapWithIndex)
import Data.DateTime.Instant (unInstant)
import Data.Either (Either(..))
import Data.Int (floor)
import Data.Maybe (Maybe(..), fromMaybe)
import Effect (Effect)
import Effect.Console as Console
import Effect.Aff (Aff, delay)
import Effect.Aff.Class (class MonadAff)
import Effect.Class (liftEffect)
import Effect.Now (now)
import Control.Monad.Rec.Class (forever)
import Halogen as H
import Halogen.Aff as HA
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)
import JSURI (encodeURIComponent)
import Web.DOM.ParentNode (QuerySelector(..))
import Types (Listen(..), ListenBrainzResponse(..), TrackMetadata(..), Payload(..), MbidMapping(..))
import Data.Time.Duration (Milliseconds(..))

import Data.Set (Set)
import Data.Set as Set

type State =
  { listens :: Array Listen
  , lastCheck :: Maybe String
  , error :: Maybe String
  , loading :: Boolean
  , currentTime :: Maybe Milliseconds
  , failedCovers :: Set String
  }

data Action
  = Initialize
  | Refresh
  | ReceiveResponse (Either String (Array Listen))
  | ImageError String

component :: forall query input output m. MonadAff m => H.Component query input output m
component =
  H.mkComponent
    { initialState
    , render
    , eval: H.mkEval $ H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        }
    }
  where
  initialState _ =
    { listens: []
    , lastCheck: Nothing
    , error: Nothing
    , loading: true
    , currentTime: Nothing
    , failedCovers: Set.empty
    }

  render state =
    HH.div
      [ HP.class_ (H.ClassName "container") ]
      [ HH.h1_ [ HH.text "Recent Tracks" ]
      , renderContent state
      , HH.p
          [ HP.id "last-updated"
          , HP.class_ (H.ClassName "small")
          ]
          [ HH.text $ fromMaybe "" state.lastCheck ]
      ]

  renderContent state
    | state.loading && state.listens == [] =
        HH.ul_ [ HH.li [ HP.class_ (H.ClassName "loading") ] [ HH.text "Loading recent tracks..." ] ]
    | Just err <- state.error =
        HH.ul_ [ HH.li [ HP.class_ (H.ClassName "error") ] [ HH.text err ] ]
    | otherwise =
        HH.ul [ HP.id "tracks-container" ]
          (mapWithIndex (renderListen state.currentTime state.failedCovers) state.listens)

  renderListen currentTime failedCovers _ (Listen { trackMetadata: TrackMetadata track, listenedAt }) =
    let 
      release = fromMaybe "" track.releaseName
      artist = fromMaybe "" track.artistName
      
      -- Priority:
      -- 1. CAA (CAA MBID)
      -- 2. CAA (Release MBID)
      -- 3. Last.fm proxy
      -- 4. Discogs proxy
      
      mbid = case track.mbidMapping of
        Just (MbidMapping { caaReleaseMbid: Just m }) -> Just m
        Just (MbidMapping { releaseMbid: Just m }) -> Just m
        _ -> Nothing
        
      lastfmId = "lastfm-" <> artist <> "-" <> release
      discogsId = "discogs-" <> artist <> "-" <> release
      
      coverInfo = case mbid of
        Just m -> 
          if Set.member m failedCovers then 
            -- Fallback 1: Last.fm
            if Set.member lastfmId failedCovers then
              -- Fallback 2: Discogs
              if Set.member discogsId failedCovers then Nothing
              else Just { id: discogsId, url: "/discogs?artist=" <> (fromMaybe "" $ encodeURIComponent artist) <> "&release=" <> (fromMaybe "" $ encodeURIComponent release) }
            else Just { id: lastfmId, url: "/lastfm?artist=" <> (fromMaybe "" $ encodeURIComponent artist) <> "&release=" <> (fromMaybe "" $ encodeURIComponent release) }
          else Just { id: m, url: "https://coverartarchive.org/release/" <> m <> "/front-250" }
        Nothing -> 
          -- No MBID, try Last.fm then Discogs
          if Set.member lastfmId failedCovers then
            if Set.member discogsId failedCovers then Nothing
            else Just { id: discogsId, url: "/discogs?artist=" <> (fromMaybe "" $ encodeURIComponent artist) <> "&release=" <> (fromMaybe "" $ encodeURIComponent release) }
          else Just { id: lastfmId, url: "/lastfm?artist=" <> (fromMaybe "" $ encodeURIComponent artist) <> "&release=" <> (fromMaybe "" $ encodeURIComponent release) }
    in
    HH.li
      [ HP.class_ (H.ClassName "success") ]
      [ HH.div
          [ HP.class_ (H.ClassName "track-info") ]
          [ HH.div
              [ HP.class_ (H.ClassName "track-name") ]
              [ HH.text $ fromMaybe "Unknown Track" track.trackName ]
          , HH.div
              [ HP.class_ (H.ClassName "track-artist") ]
              [ HH.text artist ]
          , HH.div
              [ HP.class_ (H.ClassName "track-time") ]
              [ let 
                  query = fromMaybe "" $ encodeURIComponent (artist <> " " <> release)
                in
                HH.span_
                  [ HH.a
                      [ HP.href $ "https://www.discogs.com/search/?q=" <> query <> "&type=release"
                      , HP.target "_blank"
                      , HP.class_ (H.ClassName "album-link")
                      ]
                      [ HH.text release ]
                  , HH.text $ " • " <> (fromMaybe "unknown time" $ formatTimeAgo currentTime listenedAt)
                  ]
              ]
          ]
      , case coverInfo of
          Just { id, url } -> 
            HH.img
              [ HP.class_ (H.ClassName "track-cover")
              , HP.src url
              , HP.alt release
              , HE.onError \_ -> ImageError id
              ]
          Nothing -> HH.text ""
      ]

  handleAction = case _ of
    Initialize -> do
      void $ H.fork $ forever (H.liftAff (delay (Milliseconds 30000.0)) *> handleAction Refresh)
      handleAction Refresh
    Refresh -> do
      H.modify_ _ { loading = true, error = Nothing }
      response <- H.liftAff fetchListens
      handleAction (ReceiveResponse response)
    ReceiveResponse result -> do
      nowInstant <- liftEffect now
      let nowMs = unInstant nowInstant
      let nowStr = "Last check: " <> show nowInstant
      case result of
        Left err -> H.modify_ _ { loading = false, error = Just err, lastCheck = Just nowStr, currentTime = Just nowMs }
        Right listens -> H.modify_ _ { loading = false, listens = listens, lastCheck = Just nowStr, currentTime = Just nowMs }
    ImageError mbid -> do
      liftEffect $ Console.log $ "Image load failed for: " <> mbid
      H.modify_ \state -> state { failedCovers = Set.insert mbid state.failedCovers }

  fetchListens :: Aff (Either String (Array Listen))
  fetchListens = do
    res <- AX.get ResponseFormat.json "/proxy"
    case res of
      Left err -> pure $ Left $ "Network error: " <> AX.printError err
      Right response ->
        case decodeJson response.body of
          Left err -> pure $ Left $ "JSON decode error: " <> show err
          Right (ListenBrainzResponse { payload: Payload { listens } }) -> pure $ Right listens

  formatTimeAgo :: Maybe Milliseconds -> Maybe Int -> Maybe String
  formatTimeAgo Nothing _ = Nothing
  formatTimeAgo _ Nothing = Nothing
  formatTimeAgo (Just (Milliseconds nowMs)) (Just timestamp) =
    let
      nowSecs = floor (nowMs / 1000.0)
      diff = nowSecs - timestamp
    in Just $
      if diff < 60 then "just now"
      else if diff < 3600 then
        let mins = diff / 60 in show mins <> " minute" <> (if mins > 1 then "s" else "") <> " ago"
      else if diff < 86400 then
        let hours = diff / 3600 in show hours <> " hour" <> (if hours > 1 then "s" else "") <> " ago"
      else
        let days = diff / 86400 in show days <> " day" <> (if days > 1 then "s" else "") <> " ago"

main :: Effect Unit
main = HA.runHalogenAff do
  maybeApp <- HA.selectElement (QuerySelector "#app")
  case maybeApp of
    Nothing -> HA.awaitBody >>= runUI component unit
    Just app -> runUI component unit app
