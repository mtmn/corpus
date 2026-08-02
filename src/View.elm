module View exposing (view)

import Browser
import Dict exposing (Dict)
import Html exposing (Html, a, button, div, h2, header, img, input, li, p, span, strong, table, tbody, td, text, th, thead, tr, ul)
import Html.Attributes as Attr exposing (class, disabled, href, placeholder, src, style, target, type_, value)
import Html.Events exposing (on, onClick, onInput)
import Json.Decode as D
import Set exposing (Set)
import Types exposing (Listen, Model, Msg(..), Page(..), Period(..), RegField(..), Registration, SimilarState(..), SimilarTrack, Stats, StatsEntry, Tab(..), UserInfo)
import Url



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "scrobbler"
    , body =
        [ div [ class "container" ]
            (header [] [ renderNav model ]
                :: (case model.page of
                        RegisterPage ->
                            [ renderRegister model ]

                        AdminPage ->
                            [ renderAdmin model ]

                        MainPage ->
                            [ renderMain model ]
                   )
            )
        ]
    }


renderNav : Model -> Html Msg
renderNav model =
    let
        navClass : Bool -> Html.Attribute Msg
        navClass active =
            class
                (if active then
                    "tab-btn active"

                 else
                    "tab-btn"
                )

        navLink : String -> Bool -> String -> Html Msg
        navLink label active href_ =
            a [ navClass active, href href_ ] [ text label ]

        navTab : String -> Tab -> Html Msg
        navTab label tab =
            if model.page == MainPage then
                button [ navClass (model.activeTab == tab), onClick (SwitchTab tab) ] [ text label ]

            else
                navLink label False "/"
    in
    div [ class "bar" ]
        [ navTab "listens" ListensTab
        , navTab "stats" StatsTab
        , navTab "about" AboutTab
        , if model.registrationEnabled then
            navLink "join" (model.page == RegisterPage) "/register"

          else
            text ""
        ]


renderMain : Model -> Html Msg
renderMain model =
    div []
        [ case model.activeTab of
            ListensTab ->
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

            StatsTab ->
                div []
                    [ renderPeriodSelector model.statsPeriod model.showCustomInput model.customInput model.customError
                    , renderStatsView model.expandedSections model.loadedSections model.stats
                    ]

            AboutTab ->
                renderAboutView model.userSlug model.allUsers
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
                                renderListen model.userSlug model.failedCovers model.hoveredCover model.similarStates idx listen
                                    :: renderSimilarRow key model.similarStates
                            )
                            model.listens
                            |> List.concat
                        )
                    ]


renderListen : String -> Set String -> Maybe Int -> Dict String SimilarState -> Int -> Listen -> Html Msg
renderListen userSlug failedCovers hoveredCover similarStates idx listen =
    let
        artist =
            Maybe.withDefault "" listen.artistName

        trackName =
            Maybe.withDefault "" listen.trackName

        release =
            Maybe.withDefault "" listen.releaseName

        key =
            String.fromInt idx ++ "\t" ++ artist ++ "\t" ++ trackName

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
            table [ class "stats-table" ]
                [ thead []
                    [ tr []
                        [ th [] [ text "name" ]
                        , th [ class "stats-count-header" ] [ text "plays" ]
                        ]
                    ]
                , tbody [] (List.map (renderStatEntry maxCount mField) visible)
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
            [ extLink "https://github.com/mtmn/corpus" "corpus"
            , text " is a self-hosted proxy that syncs scrobbles from "
            , extLink "https://listenbrainz.org" "ListenBrainz"
            , text " and "
            , extLink "https://www.last.fm" "Last.fm."
            ]
        , if List.isEmpty otherUsers then
            text ""

          else
            div [ class "stats-section" ]
                [ h2 [] [ text "users" ]
                , ul [ class "about-users" ]
                    (List.map userLink otherUsers)
                ]
        ]



-- REGISTRATION


renderRegister : Model -> Html Msg
renderRegister model =
    div []
        [ h2 [] [ text "register" ]
        , if not model.registrationEnabled then
            p [ class "reg-error" ] [ text "Registration is currently closed." ]

          else if model.regSubmitted then
            div []
                [ p [ class "reg-success" ]
                    [ text "Thanks — your request has been submitted. You'll get an email once it's reviewed." ]
                , p [] [ a [ href "/", class "about-link" ] [ text "back home" ] ]
                ]

          else
            div [ class "reg-form" ]
                [ regField "username" "lowercase letters, numbers, dashes" FSlug model.regSlug
                , regField "name" "display name" FName model.regName
                , regField "email" "you will notified here" FEmail model.regEmail
                , regField "listenbrainz user (optional)" "" FLbUser model.regLbUser
                , regField "last.fm user (optional)" "" FLfUser model.regLfUser
                , case model.regError of
                    Just err ->
                        p [ class "reg-error" ] [ text err ]

                    Nothing ->
                        text ""
                , button
                    [ class "reg-btn"
                    , onClick SubmitRegistration
                    , disabled model.regSubmitting
                    ]
                    [ text
                        (if model.regSubmitting then
                            "submitting…"

                         else
                            "submit"
                        )
                    ]
                ]
        ]


regField : String -> String -> RegField -> String -> Html Msg
regField label placeholderText field val =
    div [ class "reg-field" ]
        [ span [ class "reg-label" ] [ text label ]
        , input
            [ type_ "text"
            , class "reg-input"
            , placeholder placeholderText
            , value val
            , onInput (UpdateRegField field)
            ]
            []
        ]



-- ADMIN


renderAdmin : Model -> Html Msg
renderAdmin model =
    div []
        [ div [ class "reg-field" ]
            [ input
                [ type_ "password"
                , class "reg-input"
                , value model.adminTokenInput
                , onInput UpdateAdminTokenInput
                ]
                []
            , button [ class "reg-btn", onClick SaveAdminToken ] [ text "load" ]
            ]
        , case model.approvedToken of
            Just token ->
                div [ class "token-box" ]
                    [ strong [] [ text "Approved. " ]
                    , text ("API token: " ++ token)
                    ]

            Nothing ->
                text ""
        , case model.adminError of
            Just err ->
                p [ class "reg-error" ] [ text err ]

            Nothing ->
                text ""
        , if String.isEmpty model.adminToken then
            text ""

          else
            div []
                [ h2 [] [ text "pending" ]
                , if List.isEmpty model.registrations then
                    p [] [ text "No pending registrations." ]

                  else
                    ul [ class "admin-list" ]
                        (List.map renderRegistrationItem model.registrations)
                , h2 [] [ text "users" ]
                , if List.isEmpty model.users then
                    p [] [ text "No registered users." ]

                  else
                    ul [ class "admin-list" ]
                        (List.map (renderUserItem model.confirmingRemoval) model.users)
                ]
        ]


renderRegistrationItem : Registration -> Html Msg
renderRegistrationItem reg =
    li [ class "admin-item" ]
        [ div [ class "admin-item-meta" ]
            [ div [ class "admin-item-slug" ] [ text reg.slug ]
            , div [ class "admin-item-sub" ] [ text (reg.name ++ " · " ++ reg.email) ]
            , div [ class "admin-item-sub" ] [ text (regSources reg) ]
            ]
        , div [ class "admin-actions" ]
            [ button [ class "approve-btn", onClick (ApproveRegistration reg.id) ] [ text "approve" ]
            , button [ class "deny-btn", onClick (DenyRegistration reg.id) ] [ text "deny" ]
            ]
        ]


renderUserItem : Maybe String -> Registration -> Html Msg
renderUserItem confirmingRemoval reg =
    li [ class "admin-item" ]
        [ div [ class "admin-item-meta" ]
            [ div [ class "admin-item-slug" ] [ text reg.slug ]
            , div [ class "admin-item-sub" ] [ text (reg.name ++ " · " ++ reg.email) ]
            , div [ class "admin-item-sub" ] [ text (regSources reg) ]
            ]
        , if confirmingRemoval == Just reg.id then
            div [ class "admin-actions" ]
                [ span [ class "admin-item-sub" ] [ text "delete this account and its data?" ]
                , button [ class "deny-btn", onClick (RemoveUser reg.id) ] [ text "confirm" ]
                , button [ class "approve-btn", onClick CancelRemoveUser ] [ text "cancel" ]
                ]

          else
            div [ class "admin-actions" ]
                [ button [ class "deny-btn", onClick (RequestRemoveUser reg.id) ] [ text "remove" ] ]
        ]


regSources : Registration -> String
regSources reg =
    let
        parts =
            List.filterMap identity
                [ Maybe.map (\u -> "ListenBrainz: " ++ u) reg.listenbrainzUser
                , Maybe.map (\u -> "Last.fm: " ++ u) reg.lastfmUser
                ]
    in
    if List.isEmpty parts then
        "no sync sources"

    else
        String.join " · " parts
