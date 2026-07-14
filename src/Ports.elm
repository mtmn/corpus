port module Ports exposing (saveAdminToken)

{-| Persists the admin token to localStorage; the initial value comes back via flags.
-}


port saveAdminToken : String -> Cmd msg
