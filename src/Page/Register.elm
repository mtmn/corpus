module Page.Register exposing (renderRegister)

import Html exposing (Html, a, button, div, h2, input, p, span, text)
import Html.Attributes as Attr exposing (class, disabled, href, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Types exposing (Model, Msg(..), RegField(..))


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
