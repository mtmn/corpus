module Templates where

import Prelude
import Data.String.Common (joinWith)

indexHtml :: Boolean -> String -> Array { slug :: String, name :: String } -> String
indexHtml registrationEnabled userSlug allUsers =
  let
    encodeUser { slug, name } = "{\"slug\":\"" <> slug <> "\",\"name\":\"" <> name <> "\"}"
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
    <style>
        :root {
            color-scheme: dark;
            --bg: #212529;
            --bg-alt: #2b3035;
            --bg-dark: #343a40;
            --bg-inactive: #343a40;
            --fg: #ced4da;
            --fg-alt: #6c757d;
            --fg-alt-dark: #adb5bd;
            --fg-light: #495057;
            --fg-intense: #f8f9fa;
            --highlight: #2b375c;
            --cyan: #9bf6ff;
            --red: #ffadad;
            --red-light: #4a2f33;
            --yellow: #fdffb6;
            --green: #caffbf;
            --green-light: #2f4a35;
            --blue: #9bb1ff;
            --purple: #ffc6ff;
            --border: var(--fg-light);
            --space-xs: 0.25em;
            --space-sm: 0.4em;
            --space-md: 0.6em;
            --space-lg: 1em;
            --window-pad: 0.5em 1.15em;
            --gutter: 25%;
            --radius: 0;
        }

        * {
            box-sizing: border-box;
        }

        html, body {
            height: 100%;
        }

        body {
            font-family: 'Intel One Mono', 'Courier New', 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 16px;
            line-height: 1.5;
            background-color: var(--bg);
            color: var(--fg);
            margin: 0;
            padding: 0 var(--gutter);
        }

        /* The app window: inset from the gutters so content never sits on an edge. */
        .container {
            padding: var(--window-pad);
        }

        /* Artwork filling the left and right gutters, pinned to the viewport. */
        body::before,
        body::after {
            content: "";
            position: fixed;
            top: 0;
            bottom: 0;
            width: var(--gutter);
            background-position: center;
            background-repeat: no-repeat;
            background-size: cover;
            pointer-events: none;
            z-index: -1;
        }

        body::before {
            left: 0;
            background-image: url("/gutter-left.webp");
        }

        body::after {
            right: 0;
            background-image: url("/gutter-right.webp");
        }

        /* Narrow viewports can't spare 30% a side; fall back to a flat gutter. */
        @media (max-width: 60em) {
            :root {
                --gutter: var(--space-lg);
            }

            body::before,
            body::after {
                display: none;
            }
        }

        a {
            color: var(--blue);
            text-decoration: none;
        }

        a:hover {
            text-decoration: underline;
        }

        a:visited {
            color: var(--purple);
        }

        h1 {
            font-size: 1.25em;
            margin: 0 0 var(--space-xs) 0;
            color: var(--fg);
        }

        h2 {
            font-size: 1em;
            margin: var(--space-md) 0 var(--space-sm) 0;
            color: var(--fg);
        }

        header {
            margin-bottom: var(--space-md);
            border-bottom: solid 0.1em var(--border);
            padding-bottom: var(--space-sm);
        }

        .bar {
            display: flex;
            flex-wrap: wrap;
            gap: var(--space-sm);
            align-items: center;
            margin-bottom: var(--space-md);
        }

        input,
        button,
        .tab-btn,
        .tab-btn:visited {
            background-color: var(--bg-alt);
            color: var(--fg);
            border: solid 0.1em var(--border);
            padding: var(--space-xs) var(--space-sm);
            font: inherit;
            border-radius: var(--radius);
            line-height: 1.4;
        }

        input {
            flex: 1;
            min-width: 12em;
        }

        input::placeholder {
            color: var(--fg-alt);
        }

        input:focus {
            outline: none;
            border-color: var(--cyan);
        }

        button,
        .tab-btn {
            cursor: pointer;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            gap: var(--space-xs);
        }

        button:hover,
        .tab-btn:hover {
            background-color: var(--highlight);
            border-color: var(--cyan);
            text-decoration: none;
        }

        button:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }

        button.active,
        button.on,
        .tab-btn.active,
        .tab-btn.on {
            background-color: var(--cyan);
            color: var(--bg);
            border-color: var(--cyan);
        }

        button .n,
        .tab-btn .n {
            color: var(--fg-alt);
        }

        button.active .n,
        button.on .n,
        .tab-btn.active .n,
        .tab-btn.on .n {
            color: var(--bg);
        }

        table {
            border-collapse: collapse;
            width: 100%;
            border: solid 0.1em var(--border);
        }

        th,
        td {
            border: solid 0.1em var(--border);
            padding: var(--space-sm) var(--space-md);
            text-align: left;
            vertical-align: top;
        }

        th {
            background-color: var(--bg-dark);
            color: var(--fg);
            cursor: pointer;
            user-select: none;
            position: sticky;
            top: 0;
            white-space: nowrap;
        }

        th:hover {
            background-color: var(--highlight);
        }

        tbody tr:nth-child(even) {
            background-color: var(--bg-alt);
        }

        tbody tr:hover {
            background-color: var(--highlight);
        }

        .d {
            color: var(--fg-alt);
            white-space: nowrap;
            width: 1%;
        }

        .track-cell {
            position: relative;
        }

        .track-line {
            display: flex;
            flex-wrap: wrap;
            align-items: baseline;
            gap: var(--space-sm);
        }

        .track-link,
        .artist-link,
        .album-link,
        .label-link {
            background: none;
            border: none;
            padding: 0;
            color: var(--fg);
            font: inherit;
            cursor: pointer;
            text-align: left;
            user-select: text;
        }

        .track-link {
            font-weight: bold;
        }

        .artist-link,
        .album-link,
        .label-link {
            color: var(--fg-alt);
        }

        .album-link,
        .label-link {
            text-decoration: underline;
        }

        .track-link:hover,
        .artist-link:hover,
        .album-link:hover,
        .label-link:hover {
            color: var(--blue);
        }

        .track-artist {
            margin-top: var(--space-xs);
        }

        .track-meta {
            display: flex;
            flex-wrap: wrap;
            align-items: baseline;
            gap: var(--space-sm);
            margin-top: var(--space-xs);
            color: var(--fg-alt);
            font-size: 0.9em;
            position: relative;
            padding-right: 8em;
        }

        .track-release {
            color: var(--fg-alt);
        }

        .genre-tag {
            display: inline-block;
            font-size: 0.85em;
            color: var(--green);
            position: absolute;
            bottom: 0;
            right: 0;
        }

        .cover-cell {
            width: 76px;
            padding: var(--space-sm);
            vertical-align: middle;
        }

        .cover-cell .track-cover {
            width: 60px;
            height: 60px;
            object-fit: cover;
            border: solid 0.1em var(--border);
            background: var(--bg-alt);
            cursor: pointer;
            display: block;
        }

        .cover-wrapper {
            display: none;
        }

        .cover-overlay {
            position: fixed;
            inset: 0;
            background-color: rgba(0, 0, 0, 0.75);
            z-index: 90;
        }

        .track-cover {
            width: 60px;
            height: 60px;
            object-fit: cover;
            border: solid 0.1em var(--border);
            background: var(--bg-alt);
            cursor: pointer;
        }

        .track-cover.zoomed {
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            width: 320px;
            height: 320px;
            z-index: 100;
            border-color: var(--cyan);
        }

        .similar-btn {
            font-size: 0.75em;
            padding: var(--space-xs) var(--space-sm);
        }

        .similar-row td {
            padding: 0;
        }

        .similar-panel {
            padding: var(--space-sm) var(--space-md);
            background-color: var(--bg-alt);
            border-top: solid 0.1em var(--border);
        }

        .similar-track {
            display: flex;
            align-items: center;
            gap: var(--space-sm);
            padding: var(--space-xs) 0;
        }

        .similar-track-info {
            flex: 1;
            min-width: 0;
        }

        .similar-track-name {
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .similar-track-artist {
            color: var(--fg-alt);
            font-size: 0.9em;
        }

        .similar-score {
            color: var(--fg-alt);
            font-size: 0.85em;
        }

        .similar-link {
            font-size: 0.85em;
            color: var(--blue);
        }

        .similar-link:hover {
            color: var(--cyan);
        }

        .similar-loading,
        .similar-error,
        .similar-empty {
            color: var(--fg-alt);
            font-size: 0.9em;
        }

        .loading,
        .error {
            padding: var(--space-md) 0;
            color: var(--fg-alt);
        }

        .pagination {
            display: flex;
            flex-wrap: wrap;
            gap: var(--space-sm);
            align-items: center;
            justify-content: center;
            margin: var(--space-md) 0;
        }

        .page-indicator {
            color: var(--fg-alt);
            font-size: 0.9em;
            padding: 0 var(--space-sm);
        }

        .filter-banner {
            display: flex;
            flex-wrap: wrap;
            gap: var(--space-sm);
            align-items: center;
            margin-bottom: var(--space-md);
            padding: var(--space-sm) var(--space-md);
            background-color: var(--bg-alt);
            border: solid 0.1em var(--border);
            color: var(--fg-alt);
        }

        .filter-label strong {
            color: var(--fg);
        }

        .stats-section {
            margin-bottom: var(--space-lg);
        }

        .stats-table {
            margin-bottom: var(--space-sm);
        }

        .stats-count-header,
        .stat-count {
            text-align: right;
            color: var(--fg-alt);
        }

        .stat-name-cell {
            position: relative;
            overflow: hidden;
        }

        .stat-bar {
            position: absolute;
            left: 0;
            top: 0;
            height: 100%;
            background-color: var(--bg-inactive);
            z-index: 0;
        }

        .stat-name {
            position: relative;
            z-index: 1;
        }

        .stat-row.clickable {
            cursor: pointer;
        }

        .stat-row.clickable:hover .stat-name {
            color: var(--blue);
        }

        .stats-empty {
            color: var(--fg-alt);
            font-size: 0.9em;
            padding: var(--space-sm) 0;
        }

        .period-selector {
            display: flex;
            flex-wrap: wrap;
            gap: var(--space-sm);
            margin-bottom: var(--space-md);
        }

        .custom-range {
            display: flex;
            flex-wrap: wrap;
            gap: var(--space-sm);
            align-items: center;
            margin-bottom: var(--space-md);
        }

        .custom-range-input {
            width: 16em;
        }

        .custom-range-input.error {
            border-color: var(--red);
        }

        .custom-range-error {
            color: var(--red);
            font-size: 0.9em;
        }

        .show-all-btn {
            background-color: var(--bg-alt);
            border: solid 0.1em var(--border);
            color: var(--fg);
            padding: var(--space-xs) var(--space-sm);
            cursor: pointer;
            font: inherit;
        }

        .show-all-btn:hover {
            background-color: var(--highlight);
            border-color: var(--cyan);
        }

        .about-lead {
            color: var(--fg-alt);
            font-size: 0.9em;
            line-height: 1.6;
        }

        .about-link {
            color: var(--blue);
        }

        .about-link:hover {
            color: var(--cyan);
        }

        .about-users {
            list-style: none;
            padding: 0;
            margin: 0;
        }

        .about-users li {
            padding: var(--space-xs) 0;
        }

        .reg-form {
            max-width: 32em;
        }

        .reg-field {
            display: flex;
            flex-direction: column;
            gap: var(--space-xs);
            margin-bottom: var(--space-md);
        }

        .reg-label {
            color: var(--fg-alt);
            font-size: 0.9em;
        }

        .reg-input {
            width: 100%;
        }

        .reg-btn,
        .approve-btn,
        .deny-btn {
            background-color: var(--bg-alt);
            border: solid 0.1em var(--border);
            color: var(--fg);
            padding: var(--space-xs) var(--space-sm);
            font: inherit;
            cursor: pointer;
        }

        .reg-btn:hover,
        .approve-btn:hover,
        .deny-btn:hover {
            background-color: var(--highlight);
            border-color: var(--cyan);
        }

        .approve-btn {
            background-color: var(--green-light);
            border-color: var(--green);
            color: var(--fg);
        }

        .approve-btn:hover {
            background-color: var(--green);
            border-color: var(--green);
            color: var(--bg);
        }

        .deny-btn {
            background-color: var(--red-light);
            border-color: var(--red);
            color: var(--fg);
        }

        .deny-btn:hover {
            background-color: var(--red);
            border-color: var(--red);
            color: var(--bg);
        }

        .reg-error {
            color: var(--red);
            font-size: 0.9em;
        }

        .reg-success {
            color: var(--green);
            font-size: 0.9em;
        }

        .admin-list {
            list-style: none;
            padding: 0;
            margin: var(--space-sm) 0 var(--space-md) 0;
        }

        .admin-item {
            display: flex;
            flex-wrap: wrap;
            gap: var(--space-sm);
            align-items: center;
            justify-content: space-between;
            padding: var(--space-sm) var(--space-md);
            border: solid 0.1em var(--border);
            background-color: var(--bg-alt);
        }

        .admin-item-slug {
            font-weight: bold;
            color: var(--fg);
        }

        .admin-item-sub {
            color: var(--fg-alt);
            font-size: 0.9em;
        }

        .token-box {
            border: solid 0.1em var(--border);
            padding: var(--space-sm);
            margin: var(--space-sm) 0;
            background-color: var(--bg-alt);
            font-size: 0.85em;
            word-break: break-all;
            color: var(--fg);
        }

        ::selection {
            background-color: var(--highlight);
            color: var(--fg-intense);
        }
    </style>
</head>
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
