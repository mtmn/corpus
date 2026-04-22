module Client exposing (main)

import Browser
import State exposing (init, subscriptions, update)
import Types exposing (Flags, Model, Msg(..))
import View exposing (view)


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
