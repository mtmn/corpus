module Templates (indexHtml) where

import Prelude

import Data.Argonaut.Core (stringify)
import Data.Argonaut.Encode (encodeJson)
import Data.String.Common (replaceAll)
import Data.String.Pattern (Pattern(..), Replacement(..))

-- | Render the HTML shell and embed the initial frontend configuration.
-- User-supplied values are JSON-encoded, then the angle brackets are escaped
-- as JSON escapes so the payload cannot close the containing script element
-- or open an HTML comment.
indexHtml
  :: Boolean -> String -> Array { slug :: String, name :: String } -> String
indexHtml registrationEnabled userSlug allUsers =
  let
    flagsJson = escapeForScript
      ( stringify
          ( encodeJson
              { userSlug: userSlug
              , allUsers: allUsers
              , registrationEnabled: registrationEnabled
              }
          )
      )
  in
    """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>scrobbler</title>
    <link rel="icon" type="image/png" href="/favicon.png">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Intel+One+Mono:wght@300;400;500;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="/style.css">
</head>
<body>
    <div id="app"></div>
    <script id="flags" type="application/json">""" <> flagsJson
      <>
        """</script>
    <script src="/client.js"></script>
    <script>
        var flags = JSON.parse(document.getElementById('flags').textContent);
        var app = Elm.Client.init({
            flags: {
                userSlug: flags.userSlug,
                allUsers: flags.allUsers,
                registrationEnabled: flags.registrationEnabled,
                adminToken: window.localStorage.getItem('corpusAdminToken') || ''
            }
        });
        if (app.ports && app.ports.saveAdminToken) {
            app.ports.saveAdminToken.subscribe(function (token) {
                window.localStorage.setItem('corpusAdminToken', token);
            });
        }
    </script>
</body>
</html>"""

-- | Neutralise the sequences that can terminate an inline script element.
escapeForScript :: String -> String
escapeForScript =
  replaceAll (Pattern ">") (Replacement "\\u003e")
    <<< replaceAll (Pattern "<") (Replacement "\\u003c")
