module Templates (indexHtml) where

import Prelude

import Data.String.Common (joinWith)

-- | Render the HTML shell and embed the initial frontend configuration.
indexHtml
  :: Boolean -> String -> Array { slug :: String, name :: String } -> String
indexHtml registrationEnabled userSlug allUsers =
  let
    encodeUser { slug, name } = "{\"slug\":\"" <> slug <> "\",\"name\":\""
      <> name
      <> "\"}"
    usersJson = "[" <> joinWith "," (map encodeUser allUsers) <> "]"
    registrationEnabledJson = if registrationEnabled then "true" else "false"
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
<body>
    <div id="app"></div>
    <script src="/client.js"></script>
    <script>
        var userSlug = '""" <> userSlug
      <>
        """';
        var allUsers = """
      <> usersJson
      <>
        """;
        var registrationEnabled = """
      <> registrationEnabledJson
      <>
        """;
        var adminToken = window.localStorage.getItem('corpusAdminToken') || '';
        var app = Elm.Client.init({
            flags: {
                userSlug: userSlug,
                allUsers: allUsers,
                registrationEnabled: registrationEnabled,
                adminToken: adminToken
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
