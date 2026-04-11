module Client where

import Prelude

import Affjax.Web as AX
import Affjax.ResponseFormat as ResponseFormat
import Data.Argonaut (decodeJson)
import Data.Array (mapWithIndex, length)
import Data.Either (Either(..))
import Data.Int (floor, fromString)
import Data.Maybe (Maybe(..), fromMaybe)
import Effect (Effect)
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
import Data.DateTime.Instant (Instant, unInstant)
import Data.Set (Set)
import Data.Set as Set
import Web.HTML (window)
import Web.HTML.Window (location, history)
import Web.HTML.Location (search)
import Web.HTML.History (pushState, DocumentTitle(..), URL(..))
import Foreign (unsafeToForeign)
import Data.Nullable (Nullable, toMaybe)

type State =
  { listens :: Array Listen
  , lastCheck :: Maybe String
  , error :: Maybe String
  , loading :: Boolean
  , currentTime :: Maybe Milliseconds
  , failedCovers :: Set String
  , offset :: Int
  , limit :: Int
  }

data Action
  = Initialize
  | Refresh
  | ReceiveResponse (Either String (Array Listen))
  | ImageError String
  | NextPage
  | PrevPage

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
    , offset: 0
    , limit: 25
    }

  render state =
    HH.div
      [ HP.class_ (H.ClassName "container") ]
      [ HH.h1_ [ HH.text "scorpus" ]
      , renderContent state
      , HH.div
          [ HP.class_ (H.ClassName "pagination") ]
          [ HH.button
              [ HP.class_ (H.ClassName "page-btn")
              , HP.disabled (state.offset == 0 || state.loading)
              , HE.onClick \_ -> PrevPage
              ]
              [ HH.text "Previous" ]
          , HH.div [ HP.class_ (H.ClassName "page-indicator") ] [ HH.text $ "Page " <> show (state.offset / state.limit + 1) ]
          , HH.button
              [ HP.class_ (H.ClassName "page-btn")
              , HP.disabled (length state.listens < state.limit || state.loading)
              , HE.onClick \_ -> NextPage
              ]
              [ HH.text "Next" ]
          ]
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

      mbid = case track.mbidMapping of
        Just (MbidMapping { caaReleaseMbid: Just m }) -> Just m
        Just (MbidMapping { releaseMbid: Just m }) -> Just m
        _ -> Nothing

      coverUrl = "/cover?artist=" <> (fromMaybe "" $ encodeURIComponent artist) 
               <> "&release=" <> (fromMaybe "" $ encodeURIComponent release)
               <> (case mbid of 
                     Just m -> "&mbid=" <> m
                     Nothing -> "")
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
        , if Set.member coverUrl failedCovers then HH.text ""
          else HH.img
            [ HP.class_ (H.ClassName "track-cover")
            , HP.src coverUrl
            , HP.alt release
            , HE.onError \_ -> ImageError coverUrl
            ]
        ]


  handleAction = case _ of
    Initialize -> do
      w <- liftEffect window
      loc <- liftEffect $ location w
      qs <- liftEffect $ search loc
      let pageParam = toMaybe $ extractParam "page" qs
      let initialPage = fromMaybe 1 (pageParam >>= fromString)
      let initialOffset = max 0 ((initialPage - 1) * 25)

      H.modify_ _ { offset = initialOffset }

      void $ H.fork $ forever (H.liftAff (delay (Milliseconds 30000.0)) *> handleAction Refresh)
      handleAction Refresh
    Refresh -> do
      state <- H.get
      H.modify_ _ { loading = true, error = Nothing }
      response <- H.liftAff $ fetchListens state.limit state.offset
      handleAction (ReceiveResponse response)
    ReceiveResponse result -> do
      nowInstant <- liftEffect now
      let nowMs = unInstant nowInstant
      let nowStr = formatRFC3339 nowInstant
      case result of
        Left err -> H.modify_ _ { loading = false, error = Just err, lastCheck = Just nowStr, currentTime = Just nowMs }
        Right listens -> H.modify_ _ { loading = false, listens = listens, lastCheck = Just nowStr, currentTime = Just nowMs }
    ImageError url -> do
      H.modify_ \state -> state { failedCovers = Set.insert url state.failedCovers }
    NextPage -> do
      H.modify_ \state -> state { offset = state.offset + state.limit }
      updateUrl
      handleAction Refresh
    PrevPage -> do
      H.modify_ \state -> state { offset = max 0 (state.offset - state.limit) }
      updateUrl
      handleAction Refresh

  updateUrl = do
    state <- H.get
    let page = (state.offset / state.limit) + 1
    liftEffect do
      w <- window
      h <- history w
      pushState (unsafeToForeign {}) (DocumentTitle "") (URL $ "?page=" <> show page) h

  fetchListens :: Int -> Int -> Aff (Either String (Array Listen))
  fetchListens limit offset = do
    let url = "/proxy?limit=" <> show limit <> "&offset=" <> show offset
    res <- AX.get ResponseFormat.json url
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
    in
      Just $
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

foreign import extractParam :: String -> String -> Nullable String
foreign import formatRFC3339 :: Instant -> String
