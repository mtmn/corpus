module Page.Listens exposing (renderContent, renderCoverOverlay, renderListen, renderMain, renderSimilarRow, renderSimilarTrack)

import Dict exposing (Dict)
import Html exposing (Html, a, button, div, img, input, p, span, strong, table, tbody, td, text, tr)
import Html.Attributes as Attr exposing (class, disabled, href, placeholder, src, target, type_, value)
import Html.Events exposing (on, onClick, onInput)
import Html.Lazy exposing (lazy6)
import Json.Decode as D
import Page.Common exposing (onEnter)
import Set exposing (Set)
import Types exposing (Listen, Model, Msg(..), SimilarState(..), SimilarTrack, Tab(..))
import Url


renderMain : Model -> Html Msg
renderMain model =
    div []
        [ case model.activeTab of
            Types.ListensTab ->
                div []
                    [ div [ class "bar" ]
                        [ input
                            [ type_ "search"
                            , class "search-input"
                            , placeholder ""
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
                    , renderCoverOverlay model.hoveredCover
                    , Html.node "nav" [ class "pagination", Attr.attribute "aria-label" "Pagination" ]
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

            _ ->
                text ""
        ]


renderCoverOverlay : Maybe Int -> Html Msg
renderCoverOverlay hovered =
    case hovered of
        Nothing ->
            text ""

        Just _ ->
            div [ class "cover-overlay", onClick CoverBackgroundClick ] []


renderContent : Model -> Html Msg
renderContent model =
    if model.loading && List.isEmpty model.listens then
        div [ class "loading" ] [ text "⏳" ]

    else
        case model.error of
            Just err ->
                div [ class "error" ] [ text err ]

            Nothing ->
                table []
                    [ tbody []
                        (List.indexedMap
                            (\idx listen ->
                                let
                                    artist =
                                        Maybe.withDefault "" listen.artistName

                                    trackName =
                                        Maybe.withDefault "" listen.trackName

                                    key =
                                        String.fromInt idx ++ "\t" ++ artist ++ "\t" ++ trackName
                                in
                                lazy6 renderListen model.userSlug model.failedCovers (model.hoveredCover == Just idx) (Dict.member key model.similarStates) idx listen
                                    :: renderSimilarRow key model.similarStates
                            )
                            model.listens
                            |> List.concat
                        )
                    ]


{-| Render one listen row. Kept lazy-friendly: only primitive or rarely
changing arguments, so hover and similar-track toggles re-render just the
affected rows instead of the whole table.
-}
renderListen : String -> Set String -> Bool -> Bool -> Int -> Listen -> Html Msg
renderListen userSlug failedCovers isZoomed isActive idx listen =
    let
        artist =
            Maybe.withDefault "" listen.artistName

        trackName =
            Maybe.withDefault "" listen.trackName

        release =
            Maybe.withDefault "" listen.releaseName

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
    in
    tr [ class "listen-row" ]
        [ td [ class "d" ]
            [ if Set.member coverUrl failedCovers then
                text ""

              else
                div [ class "cover-cell" ]
                    [ img
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
                        , Attr.attribute "loading" "lazy"
                        , on "error" (D.succeed (ImageError coverUrl))
                        , onClick
                            (if isZoomed then
                                UnhoverCover

                             else
                                HoverCover idx
                            )
                        ]
                        []
                    ]
            ]
        , td [ class "track-cell" ]
            [ div [ class "track-line" ]
                [ if artist /= "" && trackName /= "" then
                    button
                        [ class
                            ("similar-btn"
                                ++ (if isActive then
                                        " active"

                                    else
                                        ""
                                   )
                            )
                        , onClick (FetchSimilar idx artist trackName)
                        ]
                        [ text "similar" ]

                  else
                    text ""
                , button [ class "track-link", onClick (FilterBy "track" (Maybe.withDefault "Unknown Track" listen.trackName)) ] [ text (Maybe.withDefault "Unknown Track" listen.trackName) ]
                ]
            , div [ class "track-artist" ]
                [ button [ class "artist-link", onClick (FilterBy "artist" artist) ] [ text artist ] ]
            , div [ class "track-meta" ]
                [ div [ class "track-release" ]
                    (button [ class "album-link", onClick (FilterBy "album" release) ] [ text release ]
                        :: (case listen.label of
                                Just l ->
                                    [ text " • "
                                    , button [ class "label-link", onClick (FilterBy "label" l) ] [ text l ]
                                    ]

                                Nothing ->
                                    []
                           )
                    )
                , case listen.genre of
                    Just g ->
                        div [ class "genre-tag" ] [ text g ]

                    Nothing ->
                        text ""
                ]
            ]
        ]


renderSimilarRow : String -> Dict String SimilarState -> List (Html Msg)
renderSimilarRow key similarStates =
    case Dict.get key similarStates of
        Nothing ->
            []

        Just SimilarLoading ->
            [ tr [ class "similar-row" ]
                [ td [ class "d" ] []
                , td []
                    [ div [ class "similar-panel" ]
                        [ div [ class "similar-loading" ] [ text "⏳" ] ]
                    ]
                ]
            ]

        Just (SimilarError err) ->
            [ tr [ class "similar-row" ]
                [ td [ class "d" ] []
                , td []
                    [ div [ class "similar-panel" ]
                        [ div [ class "similar-error" ] [ text err ] ]
                    ]
                ]
            ]

        Just (SimilarLoaded tracks) ->
            [ tr [ class "similar-row" ]
                [ td [ class "d" ] []
                , td []
                    [ div [ class "similar-panel" ]
                        [ if List.isEmpty tracks then
                            div [ class "similar-empty" ] [ text "no similar songs found" ]

                          else
                            div [] (List.map renderSimilarTrack tracks)
                        ]
                    ]
                ]
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
                    [ text "play" ]

            Nothing ->
                text ""
        ]
