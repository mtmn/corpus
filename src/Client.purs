module Client where

import Prelude

import Affjax.Web as AX
import Affjax.ResponseFormat as ResponseFormat
import Data.Argonaut (decodeJson)
import Data.Array (mapWithIndex, length)
import Data.Either (Either(..))
import Data.Int (floor, fromString, toNumber)
import Data.Foldable (maximum)
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
import Types (Listen(..), ListenBrainzResponse(..), TrackMetadata(..), Payload(..), MbidMapping(..), Stats(..), StatsEntry(..))
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

data Tab = ListensTab | StatsTab

derive instance eqTab :: Eq Tab

type ActiveFilter = { field :: String, value :: String }

type State =
  { listens :: Array Listen
  , stats :: Maybe Stats
  , lastCheck :: Maybe String
  , error :: Maybe String
  , loading :: Boolean
  , currentTime :: Maybe Milliseconds
  , failedCovers :: Set String
  , offset :: Int
  , limit :: Int
  , activeTab :: Tab
  , activeFilter :: Maybe ActiveFilter
  }

data Action
  = Initialize
  | Refresh
  | ReceiveResponse (Either String (Array Listen))
  | ReceiveStats (Either String Stats)
  | ImageError String
  | NextPage
  | PrevPage
  | SwitchTab Tab
  | FilterBy String String
  | ClearFilter

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
    , stats: Nothing
    , lastCheck: Nothing
    , error: Nothing
    , loading: true
    , currentTime: Nothing
    , failedCovers: Set.empty
    , offset: 0
    , limit: 25
    , activeTab: ListensTab
    , activeFilter: Nothing
    }

  render state =
    HH.div
      [ HP.class_ (H.ClassName "container") ]
      [ HH.h1_ [ HH.text "scrobbler" ]
      , HH.div
          [ HP.class_ (H.ClassName "tabs") ]
          [ HH.a
              [ HP.class_ (H.ClassName $ "tab-btn" <> if state.activeTab == ListensTab then " active" else "")
              , HP.href "/"
              ]
              [ HH.text "listens" ]
          , HH.button
              [ HP.class_ (H.ClassName $ "tab-btn" <> if state.activeTab == StatsTab then " active" else "")
              , HE.onClick \_ -> SwitchTab StatsTab
              ]
              [ HH.text "stats" ]
          ]
      , case state.activeTab of
          ListensTab ->
            HH.div_
              [ case state.activeFilter of
                  Nothing -> HH.text ""
                  Just { field, value } ->
                    HH.div [ HP.class_ (H.ClassName "filter-banner") ]
                      [ HH.span [ HP.class_ (H.ClassName "filter-label") ]
                          [ HH.text $ field <> ": "
                          , HH.strong_ [ HH.text value ]
                          ]
                      , HH.button
                          [ HP.class_ (H.ClassName "filter-clear")
                          , HE.onClick \_ -> ClearFilter
                          ]
                          [ HH.text "✕ clear" ]
                      ]
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
              ]
          StatsTab ->
            renderStatsView state.stats
      , HH.p
          [ HP.id "last-updated"
          , HP.class_ (H.ClassName "small")
          ]
          [ HH.text $ fromMaybe "" state.lastCheck ]
      ]

  renderStatsView Nothing =
    HH.div [ HP.class_ (H.ClassName "loading") ] [ HH.text "Loading stats..." ]
  renderStatsView (Just (Stats { genres, labels, years })) =
    HH.div_
      [ renderStatSection "genre" "genres" genres
      , renderStatSection "label" "labels" labels
      , renderStatSection "year" "years" years
      ]

  renderStatSection field title entries =
    let
      maxCount = fromMaybe 1 (maximum (map (\(StatsEntry e) -> e.count) entries))
    in
      HH.div [ HP.class_ (H.ClassName "stats-section") ]
        [ HH.h2_ [ HH.text title ]
        , if entries == [] then
            HH.div [ HP.class_ (H.ClassName "stats-empty") ] [ HH.text "no data yet — enrichment in progress" ]
          else
            HH.ul_ (map (renderStatEntry maxCount field) entries)
        ]

  renderStatEntry maxCount field (StatsEntry { name, count }) =
    let
      barPct = floor (toNumber count * 100.0 / toNumber maxCount)
    in
      HH.li
        [ HP.class_ (H.ClassName "stat-row")
        , HE.onClick \_ -> FilterBy field name
        ]
        [ HH.div
            [ HP.class_ (H.ClassName "stat-bar")
            , HP.style $ "width: " <> show barPct <> "%"
            ]
            []
        , HH.span [ HP.class_ (H.ClassName "stat-name") ] [ HH.text name ]
        , HH.span [ HP.class_ (H.ClassName "stat-count") ] [ HH.text $ show count ]
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
        <> "&release="
        <> (fromMaybe "" $ encodeURIComponent release)
        <>
          ( case mbid of
              Just m -> "&mbid=" <> m
              Nothing -> ""
          )
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
        , HH.div [ HP.class_ (H.ClassName "cover-wrapper") ]
            [ if Set.member coverUrl failedCovers then HH.text ""
              else HH.img
                [ HP.class_ (H.ClassName "track-cover")
                , HP.src coverUrl
                , HP.alt release
                , HE.onError \_ -> ImageError coverUrl
                ]
            , case track.genre of
                Just g -> HH.div [ HP.class_ (H.ClassName "genre-tag") ] [ HH.text g ]
                Nothing -> HH.text ""
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
      response <- H.liftAff $ fetchListens state.limit state.offset state.activeFilter
      handleAction (ReceiveResponse response)
    ReceiveResponse result -> do
      nowInstant <- liftEffect now
      let nowMs = unInstant nowInstant
      let nowStr = formatRFC3339 nowInstant
      case result of
        Left err -> H.modify_ _ { loading = false, error = Just err, lastCheck = Just nowStr, currentTime = Just nowMs }
        Right listens -> H.modify_ _ { loading = false, listens = listens, lastCheck = Just nowStr, currentTime = Just nowMs }
    ReceiveStats result -> case result of
      Left err -> H.modify_ _ { error = Just err }
      Right stats -> H.modify_ _ { stats = Just stats }
    FilterBy field value -> do
      H.modify_ _ { activeFilter = Just { field, value }, offset = 0, activeTab = ListensTab }
      updateUrl
      handleAction Refresh
    ClearFilter -> do
      H.modify_ _ { activeFilter = Nothing, offset = 0 }
      updateUrl
      handleAction Refresh
    SwitchTab tab -> do
      H.modify_ _ { activeTab = tab }
      case tab of
        StatsTab -> do
          state <- H.get
          when (state.stats == Nothing) do
            response <- H.liftAff fetchStats
            handleAction (ReceiveStats response)
        ListensTab -> pure unit
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

  fetchListens :: Int -> Int -> Maybe ActiveFilter -> Aff (Either String (Array Listen))
  fetchListens limit offset mFilter = do
    let
      filterParams = case mFilter of
        Nothing -> ""
        Just { field, value } -> "&filterField=" <> field <> "&filterValue=" <> (fromMaybe value (encodeURIComponent value))
    let url = "/proxy?limit=" <> show limit <> "&offset=" <> show offset <> filterParams
    res <- AX.get ResponseFormat.json url
    case res of
      Left err -> pure $ Left $ "Network error: " <> AX.printError err
      Right response ->
        case decodeJson response.body of
          Left err -> pure $ Left $ "JSON decode error: " <> show err
          Right (ListenBrainzResponse { payload: Payload { listens } }) -> pure $ Right listens

  fetchStats :: Aff (Either String Stats)
  fetchStats = do
    res <- AX.get ResponseFormat.json "/stats"
    case res of
      Left err -> pure $ Left $ "Network error: " <> AX.printError err
      Right response ->
        case decodeJson response.body of
          Left err -> pure $ Left $ "JSON decode error: " <> show err
          Right stats -> pure $ Right stats

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
