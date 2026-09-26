module Page.Stats exposing (renderPeriodSelector, renderStatsView)

import Html exposing (Html, button, div, h2, input, span, table, tbody, td, text, th, thead, tr)
import Html.Attributes as Attr exposing (class, placeholder, style, type_, value)
import Html.Events exposing (onClick, onInput)
import Html.Lazy exposing (lazy3)
import Page.Common exposing (formatScrobbleCount)
import Set exposing (Set)
import Types exposing (Model, Msg(..), Period(..), Stats, StatsEntry)


renderStatsView : Set String -> Set String -> Maybe Stats -> Html Msg
renderStatsView expandedSections loadedSections mStats =
    case mStats of
        Nothing ->
            div [ class "loading" ] [ text "⏳" ]

        Just stats ->
            div []
                [ renderStatSection expandedSections loadedSections
                    { key = "artist", field = Just "artist", title = "top artists" }
                    stats.artists
                , renderStatSection expandedSections loadedSections
                    { key = "track", field = Nothing, title = "top tracks" }
                    stats.tracks
                , renderStatSection expandedSections loadedSections
                    { key = "genre", field = Just "genre", title = "genres" }
                    stats.genres
                , renderStatSection expandedSections loadedSections
                    { key = "label", field = Just "label", title = "labels" }
                    stats.labels
                , renderStatSection expandedSections loadedSections
                    { key = "year", field = Just "year", title = "years" }
                    stats.years
                ]


{-| Identifies a stats table: the key used for expand state and section
fetching, plus the filter field its rows link to. Rows show a composite label
for tracks, which no filter accepts, so their field stays absent.
-}
type alias SectionRef =
    { key : String
    , field : Maybe String
    , title : String
    }


renderStatSection : Set String -> Set String -> SectionRef -> List StatsEntry -> Html Msg
renderStatSection expandedSections loadedSections section entries =
    let
        sectionKey =
            section.key

        mField =
            section.field

        title =
            section.title

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
            table [ class "stats-table" ]
                [ thead []
                    [ tr []
                        [ th [] [ text "name" ]
                        , th [ class "stats-count-header" ] [ text "plays" ]
                        ]
                    ]
                , tbody [] (List.map (lazy3 renderStatEntry maxCount mField) visible)
                ]
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
    tr rowAttrs
        [ td [ class "stat-name-cell" ]
            [ div [ class "stat-bar", style "width" (String.fromInt barPct ++ "%") ] []
            , span [ class "stat-name" ] [ text entry.name ]
            ]
        , td [ class "stat-count" ] [ text (String.fromInt entry.count) ]
        ]


renderPeriodSelector : Period -> Bool -> String -> Maybe String -> Maybe Stats -> Html Msg
renderPeriodSelector current showInput customVal mError mStats =
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
        [ div [ class "period-picker-bar" ]
            [ div [ class "period-selector" ]
                ([ namedBtn AllTime "all time", customBtn ]
                    ++ List.map daysBtn [ 7, 14, 30, 90, 180, 365 ]
                )
            , case mStats of
                Just stats ->
                    div [ class "stats-total" ]
                        [ text (formatScrobbleCount stats.totalScrobbles ++ if stats.totalScrobbles == 1 then " scrobble" else " scrobbles") ]

                Nothing ->
                    text ""
            ]
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
