module Page.Common exposing (formatScrobbleCount, onEnter)

import Html exposing (Html)
import Html.Events exposing (on)
import Json.Decode as D


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


formatScrobbleCount : Int -> String
formatScrobbleCount count =
    String.fromList <|
        Tuple.second <|
            String.foldr
                (\digit ( index, formatted ) ->
                    ( index + 1
                    , if index > 0 && modBy 3 index == 0 then
                        digit :: ',' :: formatted

                      else
                        digit :: formatted
                    )
                )
                ( 0, [] )
                (String.fromInt count)
