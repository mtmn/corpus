port module Client exposing (main)

import Browser
import Dict exposing (Dict)
import Html exposing (Html, a, button, div, h1, h2, img, input, li, p, span, strong, text, ul)
import Html.Attributes as Attr exposing (class, disabled, href, placeholder, src, style, target, type_, value)
import Html.Events exposing (on, onClick, onInput)
import Http
import Json.Decode as D exposing (Decoder)
import List
import Maybe
import Set exposing (Set)
import String
import Task
import Time
import Url


port pushUrl : String -> Cmd msg


type alias UserInfo =
    { slug : String
    , name : String
    }


type alias Flags =
    { search : String
    , userSlug : String
    , allUsers : List UserInfo
    }


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }



-- TYPES


type Tab
    = ListensTab
    | StatsTab
    | AboutTab


type Period
    = AllTime
    | LastDays Int
    | CustomRange String String


type alias ActiveFilter =
    { field : String
    , value : String
    }


type alias Listen =
    { trackName : Maybe String
    , artistName : Maybe String
    , releaseName : Maybe String
    , listenedAt : Maybe Int
    , genre : Maybe String
    , label : Maybe String
    , releaseMbid : Maybe String
    , caaReleaseMbid : Maybe String
    }


type alias StatsEntry =
    { name : String
    , count : Int
    }


type alias Stats =
    { genres : List StatsEntry
    , labels : List StatsEntry
    , years : List StatsEntry
    , artists : List StatsEntry
    , tracks : List StatsEntry
    }


type alias SimilarTrack =
    { artist : String
    , track : String
    , score : Maybe Float
    , videoUri : Maybe String
    }


type SimilarState
    = SimilarLoading
    | SimilarLoaded (List SimilarTrack)
    | SimilarError String



-- MODEL


type alias Model =
    { listens : List Listen
    , stats : Maybe Stats
    , error : Maybe String
    , loading : Bool
    , currentTime : Maybe Time.Posix
    , failedCovers : Set String
    , hoveredCover : Maybe Int
    , expandedSections : Set String
    , loadedSections : Set String
    , offset : Int
    , limit : Int
    , activeTab : Tab
    , activeFilter : Maybe ActiveFilter
    , statsPeriod : Period
    , customInput : String
    , showCustomInput : Bool
    , customError : Maybe String
    , userSlug : String
    , similarStates : Dict String SimilarState
    , allUsers : List UserInfo
    , searchInput : String
    , activeSearch : Maybe String
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        page =
            parsePageParam flags.search

        offset =
            max 0 ((page - 1) * 25)
    in
    ( { listens = []
      , stats = Nothing
      , error = Nothing
      , loading = True
      , currentTime = Nothing
      , failedCovers = Set.empty
      , hoveredCover = Nothing
      , expandedSections = Set.empty
      , loadedSections = Set.empty
      , offset = offset
      , limit = 25
      , activeTab = ListensTab
      , activeFilter = Nothing
      , statsPeriod = AllTime
      , customInput = ""
      , showCustomInput = False
      , customError = Nothing
      , userSlug = flags.userSlug
      , similarStates = Dict.empty
      , allUsers = flags.allUsers
      , searchInput = ""
      , activeSearch = Nothing
      }
    , Cmd.batch
        [ fetchListens flags.userSlug 25 offset Nothing Nothing
        , Task.perform GotTime Time.now
        ]
    )


parsePageParam : String -> Int
parsePageParam search =
    let
        s =
            if String.startsWith "?" search then
                String.dropLeft 1 search

            else
                search
    in
    s
        |> String.split "&"
        |> List.filterMap
            (\pair ->
                case String.split "=" pair of
                    [ "page", v ] ->
                        String.toInt v

                    _ ->
                        Nothing
            )
        |> List.head
        |> Maybe.withDefault 1



-- MSG


type Msg
    = GotListens (Result Http.Error (List Listen))
    | GotStats (Result Http.Error Stats)
    | GotSectionData String (Result Http.Error (List StatsEntry))
    | Tick Time.Posix
    | GotTime Time.Posix
    | ImageError String
    | NextPage
    | PrevPage
    | SwitchTab Tab
    | SetStatsPeriod Period
    | OpenCustomInput
    | UpdateCustomInput String
    | ApplyCustomPeriod
    | FilterBy String String
    | ClearFilter
    | HoverCover Int
    | UnhoverCover
    | ExpandSection String
    | ShowAllSection String
    | CollapseSection String
    | FetchSimilar String String
    | FetchSimilarTracks String String (Result Http.Error (List SimilarTrack))
    | UpdateSearchInput String
    | SubmitSearch
    | ClearSearch



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick time ->
            if not model.loading then
                ( { model | currentTime = Just time, loading = True }
                , fetchListens model.userSlug model.limit model.offset model.activeFilter model.activeSearch
                )

            else
                ( { model | currentTime = Just time }, Cmd.none )

        GotTime time ->
            ( { model | currentTime = Just time }, Cmd.none )

        GotListens result ->
            let
                newModel =
                    case result of
                        Err err ->
                            { model | loading = False, error = Just (httpErrorToString err) }

                        Ok listens ->
                            { model | loading = False, listens = listens, error = Nothing }
            in
            ( newModel, Task.perform GotTime Time.now )

        GotStats result ->
            case result of
                Err err ->
                    ( { model | error = Just (httpErrorToString err) }, Cmd.none )

                Ok stats ->
                    ( { model | stats = Just stats }, Cmd.none )

        GotSectionData section result ->
            case result of
                Err err ->
                    ( { model | error = Just (httpErrorToString err) }, Cmd.none )

                Ok entries ->
                    ( { model
                        | expandedSections = Set.insert section model.expandedSections
                        , loadedSections = Set.insert section model.loadedSections
                        , stats = Maybe.map (patchStatSection section entries) model.stats
                      }
                    , Cmd.none
                    )

        ImageError url ->
            ( { model | failedCovers = Set.insert url model.failedCovers }, Cmd.none )

        NextPage ->
            let
                newOffset =
                    model.offset + model.limit

                page =
                    newOffset // model.limit + 1
            in
            ( { model | offset = newOffset, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit newOffset model.activeFilter model.activeSearch
                , pushUrl ("?page=" ++ String.fromInt page)
                ]
            )

        PrevPage ->
            let
                newOffset =
                    max 0 (model.offset - model.limit)

                page =
                    newOffset // model.limit + 1
            in
            ( { model | offset = newOffset, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit newOffset model.activeFilter model.activeSearch
                , pushUrl ("?page=" ++ String.fromInt page)
                ]
            )

        SwitchTab tab ->
            ( { model | activeTab = tab }
            , case tab of
                StatsTab ->
                    if model.stats == Nothing then
                        fetchStats model.userSlug model.statsPeriod

                    else
                        Cmd.none

                ListensTab ->
                    Cmd.none

                AboutTab ->
                    Cmd.none
            )

        SetStatsPeriod period ->
            ( { model
                | statsPeriod = period
                , stats = Nothing
                , expandedSections = Set.empty
                , loadedSections = Set.empty
                , showCustomInput = False
              }
            , fetchStats model.userSlug period
            )

        OpenCustomInput ->
            let
                prefill =
                    case model.statsPeriod of
                        CustomRange from to ->
                            from ++ " " ++ to

                        _ ->
                            model.customInput
            in
            ( { model | showCustomInput = True, customInput = prefill, customError = Nothing }
            , Cmd.none
            )

        UpdateCustomInput str ->
            ( { model | customInput = str, customError = Nothing }, Cmd.none )

        ApplyCustomPeriod ->
            let
                parts =
                    model.customInput
                        |> String.split " "
                        |> List.filter (not << String.isEmpty)
            in
            case parts of
                [ from, to ] ->
                    if String.length from /= 10 || String.length to /= 10 then
                        ( { model | customError = Just "Dates must be in YYYY-MM-DD format" }, Cmd.none )

                    else if from > to then
                        ( { model | customError = Just "'from' must be before 'to'" }, Cmd.none )

                    else
                        let
                            period =
                                CustomRange from to
                        in
                        ( { model
                            | statsPeriod = period
                            , stats = Nothing
                            , expandedSections = Set.empty
                            , loadedSections = Set.empty
                            , showCustomInput = False
                            , customError = Nothing
                          }
                        , fetchStats model.userSlug period
                        )

                _ ->
                    ( { model | customError = Just "Enter two dates separated by a space" }, Cmd.none )

        FilterBy field value ->
            let
                filter =
                    Just { field = field, value = value }
            in
            ( { model | activeFilter = filter, activeSearch = Nothing, searchInput = "", offset = 0, activeTab = ListensTab, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit 0 filter Nothing
                , pushUrl "?page=1"
                ]
            )

        ClearFilter ->
            ( { model | activeFilter = Nothing, offset = 0, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit 0 Nothing model.activeSearch
                , pushUrl "?page=1"
                ]
            )

        UpdateSearchInput str ->
            ( { model | searchInput = str }, Cmd.none )

        SubmitSearch ->
            let
                q =
                    String.trim model.searchInput
            in
            if String.isEmpty q then
                ( { model | activeSearch = Nothing, offset = 0, loading = True }
                , Cmd.batch
                    [ fetchListens model.userSlug model.limit 0 Nothing Nothing
                    , pushUrl "?page=1"
                    ]
                )

            else
                ( { model | activeSearch = Just q, activeFilter = Nothing, offset = 0, loading = True }
                , Cmd.batch
                    [ fetchListens model.userSlug model.limit 0 Nothing (Just q)
                    , pushUrl "?page=1"
                    ]
                )

        ClearSearch ->
            ( { model | searchInput = "", activeSearch = Nothing, offset = 0, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit 0 Nothing Nothing
                , pushUrl "?page=1"
                ]
            )

        HoverCover idx ->
            ( { model | hoveredCover = Just idx }, Cmd.none )

        UnhoverCover ->
            ( { model | hoveredCover = Nothing }, Cmd.none )

        ExpandSection section ->
            ( { model | expandedSections = Set.insert section model.expandedSections }, Cmd.none )

        ShowAllSection section ->
            ( model, fetchSectionData model.userSlug model.statsPeriod section )

        CollapseSection section ->
            ( { model
                | expandedSections = Set.remove section model.expandedSections
                , loadedSections = Set.remove section model.loadedSections
              }
            , Cmd.none
            )

        FetchSimilar artist track ->
            let
                key =
                    artist ++ "\t" ++ track
            in
            if Dict.member key model.similarStates then
                ( { model | similarStates = Dict.remove key model.similarStates }, Cmd.none )

            else
                ( { model | similarStates = Dict.insert key SimilarLoading model.similarStates }
                , fetchSimilarTracks artist track
                )

        FetchSimilarTracks artist track result ->
            let
                key =
                    artist ++ "\t" ++ track

                newStates =
                    case result of
                        Ok tracks ->
                            Dict.insert key (SimilarLoaded tracks) model.similarStates

                        Err err ->
                            Dict.insert key (SimilarError (httpErrorToString err)) model.similarStates
            in
            ( { model | similarStates = newStates }, Cmd.none )


patchStatSection : String -> List StatsEntry -> Stats -> Stats
patchStatSection section entries stats =
    case section of
        "artist" ->
            { stats | artists = entries }

        "track" ->
            { stats | tracks = entries }

        "genre" ->
            { stats | genres = entries }

        "label" ->
            { stats | labels = entries }

        "year" ->
            { stats | years = entries }

        _ ->
            stats



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Time.every 30000 Tick



-- HTTP


fetchListens : String -> Int -> Int -> Maybe ActiveFilter -> Maybe String -> Cmd Msg
fetchListens userSlug limit offset mFilter mSearch =
    let
        filterParams =
            case mFilter of
                Nothing ->
                    ""

                Just { field, value } ->
                    "&filterField=" ++ field ++ "&filterValue=" ++ Url.percentEncode value

        searchParam =
            case mSearch of
                Nothing ->
                    ""

                Just q ->
                    "&search=" ++ Url.percentEncode q

        url =
            "/proxy?user=" ++ userSlug ++ "&limit=" ++ String.fromInt limit ++ "&offset=" ++ String.fromInt offset ++ filterParams ++ searchParam
    in
    Http.get
        { url = url
        , expect = Http.expectJson GotListens listensDecoder
        }


fetchStats : String -> Period -> Cmd Msg
fetchStats userSlug period =
    Http.get
        { url = statsUrl userSlug period Nothing
        , expect = Http.expectJson GotStats statsDecoder
        }


fetchSectionData : String -> Period -> String -> Cmd Msg
fetchSectionData userSlug period section =
    Http.get
        { url = statsUrl userSlug period (Just section)
        , expect = Http.expectJson (GotSectionData section) (sectionEntriesDecoder section)
        }


statsUrl : String -> Period -> Maybe String -> String
statsUrl userSlug period mSection =
    let
        periodPart =
            case period of
                AllTime ->
                    ""

                LastDays n ->
                    "&period=" ++ String.fromInt n

                CustomRange from to ->
                    "&from=" ++ from ++ "&to=" ++ to

        sectionPart =
            case mSection of
                Nothing ->
                    ""

                Just sec ->
                    "&section=" ++ sec
    in
    "/stats?user=" ++ userSlug ++ periodPart ++ sectionPart


fetchSimilarTracks : String -> String -> Cmd Msg
fetchSimilarTracks artist track =
    Http.get
        { url = "/similar?artist=" ++ Url.percentEncode artist ++ "&track=" ++ Url.percentEncode track
        , expect = Http.expectJson (FetchSimilarTracks artist track) similarTracksDecoder
        }


httpErrorToString : Http.Error -> String
httpErrorToString err =
    case err of
        Http.BadUrl url ->
            "Bad URL: " ++ url

        Http.Timeout ->
            "Request timed out"

        Http.NetworkError ->
            "Network error"

        Http.BadStatus status ->
            "Server error: " ++ String.fromInt status

        Http.BadBody body ->
            "JSON decode error: " ++ body



-- DECODERS


listensDecoder : Decoder (List Listen)
listensDecoder =
    D.at [ "payload", "listens" ] (D.list listenDecoder)


listenDecoder : Decoder Listen
listenDecoder =
    D.map2
        (\meta listenedAt ->
            { trackName = meta.trackName
            , artistName = meta.artistName
            , releaseName = meta.releaseName
            , listenedAt = listenedAt
            , genre = meta.genre
            , label = meta.label
            , releaseMbid = meta.releaseMbid
            , caaReleaseMbid = meta.caaReleaseMbid
            }
        )
        (D.field "track_metadata" trackMetaDecoder)
        (D.maybe (D.field "listened_at" D.int))


type alias TrackMeta =
    { trackName : Maybe String
    , artistName : Maybe String
    , releaseName : Maybe String
    , genre : Maybe String
    , releaseMbid : Maybe String
    , caaReleaseMbid : Maybe String
    , label : Maybe String
    }


trackMetaDecoder : Decoder TrackMeta
trackMetaDecoder =
    D.map7 TrackMeta
        (D.maybe (D.field "track_name" D.string))
        (D.maybe (D.field "artist_name" D.string))
        (D.maybe (D.field "release_name" D.string))
        (D.maybe (D.field "genre" D.string))
        (D.maybe (D.at [ "mbid_mapping", "release_mbid" ] D.string))
        (D.maybe (D.at [ "mbid_mapping", "caa_release_mbid" ] D.string))
        (D.maybe (D.field "label" D.string))


statsDecoder : Decoder Stats
statsDecoder =
    D.map5 Stats
        (D.field "genres" (D.list entryDecoder))
        (D.field "labels" (D.list entryDecoder))
        (D.field "years" (D.list entryDecoder))
        (D.field "artists" (D.list entryDecoder))
        (D.field "tracks" (D.list entryDecoder))


entryDecoder : Decoder StatsEntry
entryDecoder =
    D.map2 StatsEntry
        (D.field "name" D.string)
        (D.field "count" D.int)


sectionEntriesDecoder : String -> Decoder (List StatsEntry)
sectionEntriesDecoder section =
    D.map
        (\stats ->
            case section of
                "artist" ->
                    stats.artists

                "track" ->
                    stats.tracks

                "genre" ->
                    stats.genres

                "label" ->
                    stats.labels

                "year" ->
                    stats.years

                _ ->
                    []
        )
        statsDecoder


similarTracksDecoder : Decoder (List SimilarTrack)
similarTracksDecoder =
    D.at [ "data", "similar_tracks" ] (D.list similarTrackDecoder)


similarTrackDecoder : Decoder SimilarTrack
similarTrackDecoder =
    D.map4 SimilarTrack
        (D.field "artist" D.string)
        (D.field "track" D.string)
        (D.maybe (D.field "score" D.float))
        (D.maybe (D.field "video_uri" D.string))



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "container" ]
        [ h1 [] [ text "scrobbler" ]
        , div [ class "tabs" ]
            [ a
                [ class
                    ("tab-btn"
                        ++ (if model.activeTab == ListensTab then
                                " active"

                            else
                                ""
                           )
                    )
                , href
                    (if model.userSlug == "" then
                        "/"

                     else
                        "/u/" ++ model.userSlug
                    )
                ]
                [ text "listens" ]
            , button
                [ class
                    ("tab-btn"
                        ++ (if model.activeTab == StatsTab then
                                " active"

                            else
                                ""
                           )
                    )
                , onClick (SwitchTab StatsTab)
                ]
                [ text "stats" ]
            , button
                [ class
                    ("tab-btn"
                        ++ (if model.activeTab == AboutTab then
                                " active"

                            else
                                ""
                           )
                    )
                , onClick (SwitchTab AboutTab)
                ]
                [ text "about" ]
            ]
        , case model.activeTab of
            ListensTab ->
                div []
                    [ div [ class "search-bar" ]
                        [ input
                            [ type_ "text"
                            , class "search-input"
                            , placeholder "search by track, artist, album or label"
                            , value model.searchInput
                            , onInput UpdateSearchInput
                            , onEnter SubmitSearch
                            ]
                            []
                        , button [ class "search-btn", onClick SubmitSearch ] [ text "search" ]
                        , case model.activeSearch of
                            Just _ ->
                                button [ class "filter-clear", onClick ClearSearch ] [ text "✕ clear" ]

                            Nothing ->
                                text ""
                        ]
                    , case model.activeFilter of
                        Nothing ->
                            text ""

                        Just { field, value } ->
                            div [ class "filter-banner" ]
                                [ span [ class "filter-label" ]
                                    [ text (field ++ ": ")
                                    , strong [] [ text value ]
                                    ]
                                , button [ class "filter-clear", onClick ClearFilter ]
                                    [ text "✕ clear" ]
                                ]
                    , renderContent model
                    , div [ class "pagination" ]
                        [ button
                            [ class "page-btn"
                            , disabled (model.offset == 0 || model.loading)
                            , onClick PrevPage
                            ]
                            [ text "Previous" ]
                        , div [ class "page-indicator" ]
                            [ text ("Page " ++ String.fromInt (model.offset // model.limit + 1)) ]
                        , button
                            [ class "page-btn"
                            , disabled (List.length model.listens < model.limit || model.loading)
                            , onClick NextPage
                            ]
                            [ text "Next" ]
                        ]
                    ]

            StatsTab ->
                div []
                    [ renderPeriodSelector model.statsPeriod model.showCustomInput model.customInput model.customError
                    , renderStatsView model.expandedSections model.loadedSections model.stats
                    ]

            AboutTab ->
                renderAboutView model.userSlug model.allUsers
        ]


renderContent : Model -> Html Msg
renderContent model =
    if model.loading && List.isEmpty model.listens then
        ul [] [ li [ class "loading" ] [ text "⏳" ] ]

    else
        case model.error of
            Just err ->
                ul [] [ li [ class "error" ] [ text err ] ]

            Nothing ->
                div [ class "tracks-with-similar" ]
                    (List.indexedMap
                        (\idx listen ->
                            let
                                artist =
                                    Maybe.withDefault "" listen.artistName

                                trackName =
                                    Maybe.withDefault "" listen.trackName

                                key =
                                    artist ++ "\t" ++ trackName
                            in
                            div [ class "track-with-similar-container" ]
                                [ ul [ class "track-item" ]
                                    [ renderListen model.userSlug model.currentTime model.failedCovers model.hoveredCover model.similarStates idx listen ]
                                , renderSimilarPanel model.similarStates key
                                ]
                        )
                        model.listens
                    )


renderListen : String -> Maybe Time.Posix -> Set String -> Maybe Int -> Dict String SimilarState -> Int -> Listen -> Html Msg
renderListen userSlug currentTime failedCovers hoveredCover similarStates idx listen =
    let
        artist =
            Maybe.withDefault "" listen.artistName

        trackName =
            Maybe.withDefault "" listen.trackName

        release =
            Maybe.withDefault "" listen.releaseName

        key =
            artist ++ "\t" ++ trackName

        mbid =
            case listen.caaReleaseMbid of
                Just m ->
                    Just m

                Nothing ->
                    listen.releaseMbid

        coverUrl =
            "/cover?user="
                ++ userSlug
                ++ "&artist="
                ++ Url.percentEncode artist
                ++ "&release="
                ++ Url.percentEncode release
                ++ (case mbid of
                        Just m ->
                            "&mbid=" ++ m

                        Nothing ->
                            ""
                   )

        isZoomed =
            hoveredCover == Just idx

        isActive =
            Dict.member key similarStates
    in
    li [ class "success" ]
        [ div [ class "track-info" ]
            [ div [ class "track-name" ]
                [ text (Maybe.withDefault "Unknown Track" listen.trackName) ]
            , div [ class "track-artist" ] [ text artist ]
            , div [ class "track-time" ]
                [ span []
                    (a
                        [ href ("https://www.discogs.com/search/?q=" ++ Url.percentEncode (artist ++ " " ++ release) ++ "&type=release")
                        , target "_blank"
                        , class "album-link"
                        ]
                        [ text release ]
                        :: (case listen.label of
                                Just l ->
                                    [ text " • "
                                    , button [ class "label-link", onClick (FilterBy "label" l) ] [ text l ]
                                    ]

                                Nothing ->
                                    []
                           )
                        ++ [ text (" • " ++ timeAgo currentTime listen.listenedAt) ]
                    )
                ]
            ]
        , div [ class "cover-wrapper" ]
            [ if Set.member coverUrl failedCovers then
                text ""

              else
                img
                    [ class
                        ("track-cover"
                            ++ (if isZoomed then
                                    " zoomed"

                                else
                                    ""
                               )
                        )
                    , src coverUrl
                    , Attr.alt release
                    , on "error" (D.succeed (ImageError coverUrl))
                    , onClick
                        (if isZoomed then
                            UnhoverCover

                         else
                            HoverCover idx
                        )
                    ]
                    []
            , case listen.genre of
                Just g ->
                    div [ class "genre-tag" ] [ text g ]

                Nothing ->
                    text ""
            , if artist /= "" && trackName /= "" then
                button
                    [ class
                        ("similar-btn"
                            ++ (if isActive then
                                    " active"

                                else
                                    ""
                               )
                        )
                    , onClick (FetchSimilar artist trackName)
                    ]
                    [ text "similar" ]

              else
                text ""
            ]
        ]


renderSimilarPanel : Dict String SimilarState -> String -> Html Msg
renderSimilarPanel similarStates key =
    case Dict.get key similarStates of
        Nothing ->
            text ""

        Just SimilarLoading ->
            div [ class "similar-panel" ]
                [ div [ class "similar-loading" ] [ text "⏳" ] ]

        Just (SimilarError err) ->
            div [ class "similar-panel" ]
                [ div [ class "similar-error" ] [ text err ] ]

        Just (SimilarLoaded tracks) ->
            div [ class "similar-panel" ]
                [ if List.isEmpty tracks then
                    div [ class "similar-empty" ] [ text "no similar songs found" ]

                  else
                    div [] (List.map renderSimilarTrack tracks)
                ]


renderSimilarTrack : SimilarTrack -> Html Msg
renderSimilarTrack track =
    div [ class "similar-track" ]
        [ div [ class "similar-track-info" ]
            [ div [ class "similar-track-name" ] [ text track.track ]
            , div [ class "similar-track-artist" ] [ text track.artist ]
            ]
        , case track.score of
            Just score ->
                span [ class "similar-score" ]
                    [ text (String.fromInt (round (score * 100)) ++ "%") ]

            Nothing ->
                text ""
        , case track.videoUri of
            Just link ->
                a [ class "similar-link", href link, target "_blank" ]
                    [ text "▶" ]

            Nothing ->
                text ""
        ]


renderStatsView : Set String -> Set String -> Maybe Stats -> Html Msg
renderStatsView expandedSections loadedSections mStats =
    case mStats of
        Nothing ->
            div [ class "loading" ] [ text "⏳" ]

        Just stats ->
            div []
                [ renderStatSection expandedSections loadedSections (Just "artist") "top artists" stats.artists
                , renderStatSection expandedSections loadedSections Nothing "top tracks" stats.tracks
                , renderStatSection expandedSections loadedSections (Just "genre") "genres" stats.genres
                , renderStatSection expandedSections loadedSections (Just "label") "labels" stats.labels
                , renderStatSection expandedSections loadedSections (Just "year") "years" stats.years
                ]


renderStatSection : Set String -> Set String -> Maybe String -> String -> List StatsEntry -> Html Msg
renderStatSection expandedSections loadedSections mField title entries =
    let
        sectionKey =
            Maybe.withDefault title mField

        expanded =
            Set.member sectionKey expandedSections

        loaded =
            Set.member sectionKey loadedSections

        visible =
            if loaded then
                entries

            else if expanded then
                List.take 50 entries

            else
                List.take 10 entries

        maxCount =
            entries
                |> List.map .count
                |> List.maximum
                |> Maybe.withDefault 1

        n =
            List.length entries

        footer =
            if loaded then
                if n > 10 then
                    button [ class "show-all-btn", onClick (CollapseSection sectionKey) ] [ text "show less" ]

                else
                    text ""

            else if expanded then
                if n >= 50 then
                    span []
                        [ button [ class "show-all-btn", onClick (ShowAllSection sectionKey) ] [ text "show all" ]
                        , text " · "
                        , button [ class "show-all-btn", onClick (CollapseSection sectionKey) ] [ text "show less" ]
                        ]

                else
                    button [ class "show-all-btn", onClick (CollapseSection sectionKey) ] [ text "show less" ]

            else if n > 10 then
                button [ class "show-all-btn", onClick (ExpandSection sectionKey) ] [ text "show more" ]

            else
                text ""
    in
    div [ class "stats-section" ]
        [ h2 [] [ text title ]
        , if List.isEmpty entries then
            div [ class "stats-empty" ] [ text "beyond here lies nothing" ]

          else
            ul [] (List.map (renderStatEntry maxCount mField) visible)
        , footer
        ]


renderStatEntry : Int -> Maybe String -> StatsEntry -> Html Msg
renderStatEntry maxCount mField entry =
    let
        barPct =
            entry.count * 100 // maxCount

        rowAttrs =
            case mField of
                Just field ->
                    [ class "stat-row clickable", onClick (FilterBy field entry.name) ]

                Nothing ->
                    [ class "stat-row" ]
    in
    li rowAttrs
        [ div [ class "stat-bar", style "width" (String.fromInt barPct ++ "%") ] []
        , span [ class "stat-name" ] [ text entry.name ]
        , span [ class "stat-count" ] [ text (String.fromInt entry.count) ]
        ]


renderPeriodSelector : Period -> Bool -> String -> Maybe String -> Html Msg
renderPeriodSelector current showInput customVal mError =
    let
        isCustom =
            case current of
                CustomRange _ _ ->
                    True

                _ ->
                    False

        namedBtn target label =
            button
                [ class
                    ("period-btn"
                        ++ (if current == target then
                                " active"

                            else
                                ""
                           )
                    )
                , onClick (SetStatsPeriod target)
                ]
                [ text label ]

        customBtn =
            button
                [ class
                    ("period-btn"
                        ++ (if isCustom then
                                " active"

                            else
                                ""
                           )
                    )
                , onClick OpenCustomInput
                ]
                [ text "custom" ]

        daysBtn n =
            let
                label =
                    case n of
                        7 ->
                            "1w"

                        14 ->
                            "2w"

                        30 ->
                            "1m"

                        90 ->
                            "3m"

                        180 ->
                            "6m"

                        365 ->
                            "1y"

                        _ ->
                            String.fromInt n ++ "d"
            in
            button
                [ class
                    ("period-btn"
                        ++ (if current == LastDays n then
                                " active"

                            else
                                ""
                           )
                    )
                , onClick (SetStatsPeriod (LastDays n))
                ]
                [ text label ]
    in
    div []
        [ div [ class "period-selector" ]
            ([ namedBtn AllTime "all time", customBtn ]
                ++ List.map daysBtn [ 7, 14, 30, 90, 180, 365 ]
            )
        , if showInput || isCustom then
            div []
                [ div [ class "custom-range" ]
                    [ input
                        [ type_ "text"
                        , class
                            ("custom-range-input"
                                ++ (if mError /= Nothing then
                                        " error"

                                    else
                                        ""
                                   )
                            )
                        , placeholder "2023-01-01 2026-01-01"
                        , value customVal
                        , onInput UpdateCustomInput
                        ]
                        []
                    , button [ class "period-btn", onClick ApplyCustomPeriod ]
                        [ text "apply" ]
                    ]
                , case mError of
                    Just err ->
                        div [ class "custom-range-error" ] [ text err ]

                    Nothing ->
                        text ""
                ]

          else
            text ""
        ]


onEnter : msg -> Html.Attribute msg
onEnter msg =
    on "keydown"
        (D.field "key" D.string
            |> D.andThen
                (\key ->
                    if key == "Enter" then
                        D.succeed msg

                    else
                        D.fail "not enter"
                )
        )



-- HELPERS


timeAgo : Maybe Time.Posix -> Maybe Int -> String
timeAgo mNow mTimestamp =
    case ( mNow, mTimestamp ) of
        ( Just now, Just ts ) ->
            let
                nowSecs =
                    Time.posixToMillis now // 1000

                diff =
                    nowSecs - ts
            in
            if diff < 60 then
                "just now"

            else if diff < 3600 then
                let
                    mins =
                        diff // 60
                in
                String.fromInt mins
                    ++ " minute"
                    ++ (if mins > 1 then
                            "s"

                        else
                            ""
                       )
                    ++ " ago"

            else if diff < 86400 then
                let
                    hours =
                        diff // 3600
                in
                String.fromInt hours
                    ++ " hour"
                    ++ (if hours > 1 then
                            "s"

                        else
                            ""
                       )
                    ++ " ago"

            else
                let
                    days =
                        diff // 86400
                in
                String.fromInt days
                    ++ " day"
                    ++ (if days > 1 then
                            "s"

                        else
                            ""
                       )
                    ++ " ago"

        _ ->
            "unknown time"


renderAboutView : String -> List UserInfo -> Html Msg
renderAboutView currentSlug allUsers =
    let
        otherUsers =
            List.filter (\u -> u.slug /= currentSlug) allUsers

        userLink { slug, name } =
            let
                url =
                    if slug == "" then
                        "/"

                    else
                        "/u/" ++ slug
            in
            li [] [ a [ href url ] [ text name ] ]

        extLink url label =
            a [ href url, target "_blank", class "about-link" ] [ text label ]
    in
    div []
        [ p [ class "about-lead" ]
            [ text "corpus is a self-hosted listen history proxy that syncs scrobbles from "
            , extLink "https://listenbrainz.org" "ListenBrainz"
            , text " and "
            , extLink "https://www.last.fm" "Last.fm."
            ]
        , div [ class "stats-section" ]
            [ h2 [] [ text "features" ]
            , ul [ class "about-list" ]
                [ li [] [ text "searchable listen history with pagination" ]
                , li [] [ text "stats by artist, track, label, year, and genre" ]
                , li [] [ text "filter listens by label, artist, genre, or year" ]
                , li [] [ text "cover art from Cover Art Archive, Last.fm, and Discogs" ]
                , li [] [ text "similar track discovery via cosine.club" ]
                , li [] [ text "metadata enrichment via MusicBrainz, Last.fm, and Discogs" ]
                ]
            ]
        , div [ class "stats-section" ]
            [ h2 [] [ text "source" ]
            , p [ class "about-meta" ]
                [ div [] [ extLink "https://instagram.com/counterpoint303" "counterpoint" ]
                , div [] [ extLink "https://github.com/mtmn/corpus" "github repo" ]
                , div [] [ extLink "https://mtmn.name" "mtmn.name" ]
                ]
            ]
        , if List.isEmpty otherUsers then
            text ""

          else
            div [ class "stats-section" ]
                [ h2 [] [ text "friends" ]
                , ul [ class "about-users" ]
                    (List.map userLink otherUsers)
                ]
        ]
