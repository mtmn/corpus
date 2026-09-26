module View exposing (view)

import Browser
import Html exposing (Html, a, button, div, h2, header, li, p, span, text, ul)
import Html.Attributes as Attr exposing (class, href, target)
import Html.Events exposing (onClick)
import Page.Admin
import Page.Listens
import Page.Register
import Page.Stats
import Types exposing (Model, Msg(..), Page(..), Tab(..), UserInfo)


view : Model -> Browser.Document Msg
view model =
    { title = "scrobbler"
    , body =
        [ div [ class "container" ]
            (header [] [ renderNav model ]
                :: (case model.page of
                        RegisterPage ->
                            [ Page.Register.renderRegister model ]

                        AdminPage ->
                            [ Page.Admin.renderAdmin model ]

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
                Page.Listens.renderMain model

            StatsTab ->
                div []
                    [ Page.Stats.renderPeriodSelector model.statsPeriod model.showCustomInput model.customInput model.customError model.stats
                    , Page.Stats.renderStatsView model.expandedSections model.loadedSections model.stats
                    ]

            AboutTab ->
                renderAboutView model.userSlug model.allUsers
        ]


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
