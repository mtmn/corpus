module Page.Admin exposing (renderAdmin)

import Html exposing (Html, a, button, div, h2, input, li, p, span, strong, text, ul)
import Html.Attributes as Attr exposing (class, type_, value)
import Html.Events exposing (onClick, onInput)
import Types exposing (Model, Msg(..), Registration)


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
