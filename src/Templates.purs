module Templates where

import Prelude
import Data.String.Common (joinWith)

indexHtml :: String -> Array { slug :: String, name :: String } -> String
indexHtml userSlug allUsers =
  let
    encodeUser { slug, name } = "{\"slug\":\"" <> slug <> "\",\"name\":\"" <> name <> "\"}"
    usersJson = "[" <> joinWith "," (map encodeUser allUsers) <> "]"
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
        body {
            font-family: 'Intel One Mono', 'Courier New', 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            background: #000000;
            color: #ffffff;
            margin: 0;
            line-height: 1.6;
        }

        ::selection {
            background: #50447f;
            color: #ffffff;
        }

        .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 24px 20px;
        }

        h1 {
            color: #ffffff;
            margin: 0 0 20px 0;
            font-size: 24px;
            border-bottom: 2px solid #50447f;
            padding-bottom: 8px;
        }

        ul {
            list-style: none;
            padding: 0;
            margin: 0 0 20px 0;
        }

        li {
            background: #521e40;
            border: 1px solid #50447f;
            border-radius: 4px;
            padding: 5px 15px 5px 15px;
            margin-bottom: 5px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            box-shadow: 4px 4px 0px #50447f;
        }

        li.success {
            background: #521e40;
            border-color: #50447f;
            box-shadow: 4px 4px 0px #50447f;
        }

        .track-info {
            flex: 1;
        }

        .track-name {
            font-weight: bold;
            font-size: 16px;
            color: #ffffff;
        }

        .track-artist {
            font-size: 14px;
            color: #a0c0d0;
            margin-top: 1px;
        }

        .track-time {
            font-size: 12px;
            color: #9fbfe7;
            margin-top: 2px;
        }

        .album-link {
            color: #9fbfe7;
            text-decoration: underline;
        }

        .album-link:hover {
            color: #ffffff;
        }

        .label-link {
            background: none;
            border: none;
            padding: 0;
            color: #9fbfe7;
            text-decoration: underline;
            font-family: inherit;
            font-size: inherit;
            cursor: pointer;
        }

        .label-link:hover {
            color: #ffffff;
        }

        .track-cover {
            width: 60px;
            height: 60px;
            border-radius: 4px;
            object-fit: cover;
            background: rgba(255, 255, 255, 0.05);
            transition: transform 0.2s ease-in-out;
            cursor: pointer;
        }

        .track-cover.zoomed {
            transform: scale(5.0);
            z-index: 10;
            position: relative;
            box-shadow: 0 8px 16px rgba(0, 0, 0, 0.5);
        }

        .loading {
            padding: 20px;
            color: #9fbfe7;
            text-align: center;
        }

        .error {
            padding: 20px;
            color: #eca28f;
            text-align: center;
        }

        .small {
            font-size: 12px;
            color: #9fbfe7;
            margin-top: 20px;
        }

        .small a {
            color: #a0c0d0;
            text-decoration: none;
        }

        .small a:hover {
            color: #ffffff;
            text-decoration: underline;
        }

        .pagination {
            display: flex;
            justify-content: center;
            gap: 20px;
            margin-top: 20px;
        }

        .page-btn {
            background: #521e40;
            border: 1px solid #50447f;
            color: #ffffff;
            padding: 8px 16px;
            border-radius: 4px;
            cursor: pointer;
            font-family: inherit;
            box-shadow: 2px 2px 0px #50447f;
        }

        .page-btn:hover {
            background: #50447f;
            border-color: #50447f;
        }

        .page-btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }

        .page-indicator {
            display: flex;
            align-items: center;
            font-size: 14px;
            color: #9fbfe7;
        }

        .tabs {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
        }

        .tab-btn {
            background: none;
            border: 1px solid #50447f;
            color: #9fbfe7;
            padding: 6px 14px;
            border-radius: 4px;
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
            text-decoration: none;
            display: inline-block;
        }

        .tab-btn.active {
            background: #521e40;
            color: #ffffff;
            box-shadow: 2px 2px 0px #50447f;
        }

        .tab-btn:hover {
            color: #ffffff;
            background: #50447f;
        }

        .stats-section {
            margin-bottom: 30px;
        }

        .stats-section h2 {
            font-size: 11px;
            color: #9fbfe7;
            text-transform: uppercase;
            letter-spacing: 3px;
            margin: 0 0 10px 0;
            border-bottom: 1px solid #50447f;
            padding-bottom: 5px;
        }

        .stat-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 5px 8px;
            margin-bottom: 3px;
            position: relative;
            border-radius: 2px;
            overflow: hidden;
            font-size: 13px;
        }

        .stat-bar {
            position: absolute;
            left: 0;
            top: 0;
            height: 100%;
            background: #521e40;
            border-right: 1px solid #50447f;
            z-index: 0;
        }

        .stat-name {
            position: relative;
            z-index: 1;
            color: #ffffff;
            flex: 1;
            padding-right: 10px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .stat-count {
            position: relative;
            z-index: 1;
            color: #9fbfe7;
            font-size: 12px;
            flex-shrink: 0;
        }

        .stats-empty {
            color: #9fbfe7;
            font-size: 13px;
            padding: 10px 0;
        }

        .cover-wrapper {
            display: flex;
            flex-direction: column;
            align-items: center;
	    padding-top: 5px;
            margin-left: 15px;
            gap: 4px;
            flex-shrink: 0;
            position: relative;
        }

        .genre-tag {
            display: none;
        }



        .stat-row.clickable {
            cursor: pointer;
        }

        .stat-row.clickable:hover .stat-name {
            color: #a0c0d0;
        }

        .filter-banner {
            display: flex;
            align-items: center;
            gap: 10px;
            background: #521e40;
            border: 1px solid #50447f;
            border-radius: 4px;
            padding: 8px 12px;
            margin-bottom: 12px;
            font-size: 13px;
            color: #9fbfe7;
        }

        .filter-label {
            flex: 1;
        }

        .filter-label strong {
            color: #ffffff;
        }

        .filter-clear {
            background: none;
            border: 1px solid #50447f;
            color: #9fbfe7;
            padding: 2px 8px;
            border-radius: 3px;
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
        }

        .filter-clear:hover {
            color: #ffffff;
            border-color: #ffffff;
            background: #50447f;
        }

        .show-all-btn {
            background: none;
            border: none;
            color: #9fbfe7;
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
            padding: 4px 0;
            text-decoration: underline;
        }

        .show-all-btn:hover {
            color: #ffffff;
            background: #50447f;
        }

        .period-selector {
            display: flex;
            gap: 6px;
            margin-bottom: 16px;
        }

        .period-btn {
            background: none;
            border: 1px solid #50447f;
            color: #9fbfe7;
            padding: 4px 12px;
            border-radius: 3px;
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
        }

        .period-btn:hover {
            color: #ffffff;
            border-color: #ffffff;
        }

        .period-btn.active {
            background: #50447f;
            color: #ffffff;
        }

        .custom-range {
            display: flex;
            gap: 8px;
            margin-top: 8px;
            align-items: center;
        }

        .custom-range-input {
            background: #521e40;
            border: 1px solid #50447f;
            color: #ffffff;
            padding: 4px 8px;
            border-radius: 3px;
            font-family: inherit;
            font-size: 12px;
            width: 220px;
        }

        .custom-range-input::placeholder {
            color: #9fbfe7;
            opacity: 0.7;
        }

        .custom-range-input:focus {
            outline: none;
            border-color: #ffffff;
        }

        .custom-range-input.error {
            border-color: #ff6b6b;
        }

        .custom-range-error {
            color: #ff6b6b;
            font-size: 12px;
            margin-top: 4px;
        }

        .similar-btn {
            background: none;
            border: 1px solid #50447f;
            color: #9fbfe7;
            padding: 2px 8px;
            border-radius: 3px;
            cursor: pointer;
            font-family: inherit;
            font-size: 10px;
            margin-top: 4px;
            transition: all 0.2s ease;
        }

        .similar-btn:hover {
            background: #50447f;
            color: #ffffff;
            border-color: #ffffff;
        }

        .similar-btn.active {
            background: #521e40;
            color: #ffffff;
            border-color: #50447f;
            box-shadow: 2px 2px 0px #50447f;
        }

        .similar-panel {
            margin-top: 10px;
            background: #521e40;
            border: 1px solid #50447f;
            border-radius: 4px;
            padding: 10px;
            box-shadow: 2px 2px 0px #50447f;
        }

        .similar-panel-header {
            font-size: 11px;
            color: #9fbfe7;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 8px;
            font-weight: bold;
        }

        .similar-loading {
            color: #9fbfe7;
            font-size: 12px;
            text-align: center;
            padding: 8px;
        }

        .similar-error {
            color: #eca28f;
            font-size: 12px;
            text-align: center;
            padding: 8px;
        }

        .similar-empty {
            color: #9fbfe7;
            font-size: 12px;
            text-align: center;
            padding: 8px;
        }

        .similar-track {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 6px 8px;
            margin-bottom: 4px;
            background: #521e40;
            border-radius: 3px;
            border-left: 2px solid #50447f;
        }

        .similar-track:last-child {
            margin-bottom: 0;
        }

        .similar-track-info {
            flex: 1;
            min-width: 0;
        }

        .similar-track-name {
            font-size: 12px;
            color: #ffffff;
            font-weight: 500;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .similar-track-artist {
            font-size: 11px;
            color: #a0c0d0;
            margin-top: 1px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .similar-score {
            font-size: 10px;
            color: #9fbfe7;
            background: #521e40;
            border: 1px solid #50447f;
            padding: 2px 6px;
            border-radius: 2px;
            margin-right: 8px;
            font-weight: 500;
        }

        .similar-link {
            color: #9fbfe7;
            text-decoration: none;
            font-size: 12px;
            background: #521e40;
            border: 1px solid #50447f;
            padding: 2px 6px;
            border-radius: 2px;
            transition: all 0.2s ease;
        }

        .similar-link:hover {
            color: #ffffff;
            background: #50447f;
        }

        .tracks-with-similar {
            display: flex;
            flex-direction: column;
            gap: 10px;
        }

        .track-with-similar-container {
            display: flex;
            flex-direction: column;
            gap: 10px;
        }

        .track-item {
            list-style: none;
            padding: 0;
            margin: 0;
        }

        .track-item li {
            margin: 0;
        }

        .search-bar {
            display: flex;
            gap: 8px;
            margin-bottom: 12px;
            align-items: center;
        }

        .search-input {
            flex: 1;
            background: #521e40;
            border: 1px solid #50447f;
            color: #ffffff;
            padding: 6px 10px;
            border-radius: 4px;
            font-family: inherit;
            font-size: 13px;
        }

        .search-input::placeholder {
            color: #9fbfe7;
            opacity: 0.7;
        }

        .search-input:focus {
            outline: none;
            border-color: #ffffff;
        }

        .search-btn {
            background: #50447f;
            border: 1px solid #50447f;
            color: #ffffff;
            padding: 6px 12px;
            border-radius: 4px;
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
        }

        .search-btn:hover {
            background: #6a5fa0;
            border-color: #6a5fa0;
        }

        .about-lead {
            color: #a0c0d0;
            font-size: 13px;
            line-height: 1.8;
            margin: 0 0 30px 0;
        }

        .about-link {
            color: #9fbfe7;
            text-decoration: underline;
        }

        .about-link:hover {
            color: #ffffff;
        }

        .about-list {
            list-style: none;
            padding: 0;
            margin: 0;
        }

        .about-list li {
            background: none;
            border: none;
            border-radius: 0;
            padding: 3px 0;
            margin-bottom: 0;
            display: block;
            box-shadow: none;
            font-size: 13px;
            color: #a0c0d0;
        }

        .about-list li::before {
            content: "→  ";
            color: #50447f;
        }

        .about-meta {
            font-size: 13px;
            margin: 0;
        }

        .about-users {
            list-style: none;
            padding: 0;
            margin: 0;
        }

        .about-users li {
            background: none;
            border: none;
            border-radius: 0;
            padding: 4px 0;
            margin-bottom: 0;
            display: block;
            box-shadow: none;
        }

        .about-users a {
            color: #9fbfe7;
            text-decoration: none;
            font-size: 13px;
        }

        .about-users a:hover {
            color: #ffffff;
            text-decoration: underline;
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
        var app = Elm.Client.init({
            node: document.getElementById('app'),
            flags: { search: window.location.search, userSlug: userSlug, allUsers: allUsers }
        });
        app.ports.pushUrl.subscribe(function(url) {
            var prefix = userSlug ? '/u/' + userSlug : '';
            history.pushState({}, '', prefix + url);
        });
    </script>
</body>
</html>"""
