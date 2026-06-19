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
            background: oklch(0.194 0.0345 225.31);
            color: oklch(0.91 0.012 225.31);
            margin: 0;
            line-height: 1.6;
        }

        ::selection {
            background: oklch(0.42 0.04 225.31);
            color: oklch(0.91 0.012 225.31);
        }

        .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 24px 20px;
        }

        h1 {
            color: oklch(0.91 0.012 225.31);
            margin: 0 0 20px 0;
            font-size: 24px;
            border-bottom: 2px solid oklch(0.42 0.04 225.31);
            padding-bottom: 8px;
        }

        h1.site-header {
            border-bottom: none;
            padding-bottom: 0;
            line-height: 0;
            cursor: pointer;
        }

        h1.site-header img {
            display: block;
            width: 100%;
            height: 80px;
            object-fit: cover;
            border-radius: 4px;
            border: 1px solid oklch(0.42 0.04 225.31);
        }

        ul {
            list-style: none;
            padding: 0;
            margin: 0 0 20px 0;
        }

        li {
            background: oklch(0.27 0.038 225.31);
            border: 1px solid oklch(0.42 0.04 225.31);
            border-radius: 4px;
            padding: 5px 15px 5px 15px;
            margin-bottom: 5px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            box-shadow: 4px 4px 0px oklch(0.42 0.04 225.31);
        }

        li.success {
            background: oklch(0.27 0.038 225.31);
            border-color: oklch(0.42 0.04 225.31);
            box-shadow: 4px 4px 0px oklch(0.42 0.04 225.31);
        }

        .track-info {
            flex: 1;
        }

        .track-name {
            font-weight: bold;
            font-size: 16px;
            color: oklch(0.91 0.012 225.31);
        }

        .track-artist {
            font-size: 14px;
            color: oklch(0.70 0.035 225.31);
            margin-top: 1px;
        }

        .track-time {
            font-size: 12px;
            color: oklch(0.74 0.075 225.31);
            margin-top: 2px;
        }

        .track-link {
            background: none;
            border: none;
            padding: 0;
            color: oklch(0.91 0.012 225.31);
            font-weight: bold;
            font-size: 16px;
            font-family: inherit;
            cursor: pointer;
            text-align: left;
            user-select: text;
        }

        .artist-link {
            background: none;
            border: none;
            padding: 0;
            color: oklch(0.70 0.035 225.31);
            font-size: 14px;
            font-family: inherit;
            cursor: pointer;
            text-align: left;
            user-select: text;
        }

        .album-link {
            background: none;
            border: none;
            padding: 0;
            color: oklch(0.74 0.075 225.31);
            text-decoration: underline;
            font-family: inherit;
            font-size: inherit;
            cursor: pointer;
        }

        .album-link:hover {
            color: oklch(0.78 0.13 357.86);
        }

        .label-link {
            background: none;
            border: none;
            padding: 0;
            color: oklch(0.74 0.075 225.31);
            text-decoration: underline;
            font-family: inherit;
            font-size: inherit;
            cursor: pointer;
        }

        .label-link:hover {
            color: oklch(0.78 0.13 357.86);
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
            color: oklch(0.74 0.075 225.31);
            text-align: center;
        }

        .error {
            padding: 20px;
            color: oklch(0.78 0.085 225.31);
            text-align: center;
        }

        .small {
            font-size: 12px;
            color: oklch(0.74 0.075 225.31);
            margin-top: 20px;
        }

        .small a {
            color: oklch(0.70 0.035 225.31);
            text-decoration: none;
        }

        .small a:hover {
            color: oklch(0.78 0.13 357.86);
            text-decoration: underline;
        }

        .pagination {
            display: flex;
            justify-content: center;
            gap: 20px;
            margin-top: 20px;
        }

        .page-btn {
            background: oklch(0.27 0.038 225.31);
            border: 1px solid oklch(0.42 0.04 225.31);
            color: oklch(0.91 0.012 225.31);
            padding: 8px 16px;
            border-radius: 4px;
            cursor: pointer;
            font-family: inherit;
            box-shadow: 2px 2px 0px oklch(0.42 0.04 225.31);
        }

        .page-btn:hover {
            background: oklch(0.32 0.045 225.31);
            border-color: oklch(0.52 0.05 225.31);
        }

        .page-btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }

        .page-indicator {
            display: flex;
            align-items: center;
            font-size: 14px;
            color: oklch(0.74 0.075 225.31);
        }

        .tabs {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
        }

        .tab-btn {
            background: none;
            border: 1px solid oklch(0.42 0.04 225.31);
            color: oklch(0.74 0.075 225.31);
            padding: 6px 14px;
            border-radius: 4px;
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
            text-decoration: none;
            display: inline-block;
        }

        .tab-btn.active {
            background: oklch(0.27 0.038 225.31);
            color: oklch(0.91 0.012 225.31);
            box-shadow: 2px 2px 0px oklch(0.42 0.04 225.31);
        }

        .tab-btn:hover {
            color: oklch(0.91 0.012 225.31);
            background: oklch(0.42 0.04 225.31);
        }

        .stats-section {
            margin-bottom: 30px;
        }

        .stats-section h2 {
            font-size: 11px;
            color: oklch(0.74 0.075 225.31);
            text-transform: uppercase;
            letter-spacing: 3px;
            margin: 0 0 10px 0;
            border-bottom: 1px solid oklch(0.42 0.04 225.31);
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
            background: oklch(0.27 0.038 225.31);
            border-right: 1px solid oklch(0.42 0.04 225.31);
            z-index: 0;
        }

        .stat-name {
            position: relative;
            z-index: 1;
            color: oklch(0.91 0.012 225.31);
            flex: 1;
            padding-right: 10px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .stat-count {
            position: relative;
            z-index: 1;
            color: oklch(0.74 0.075 225.31);
            font-size: 12px;
            flex-shrink: 0;
        }

        .stats-empty {
            color: oklch(0.74 0.075 225.31);
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
            color: oklch(0.70 0.035 225.31);
        }

        .filter-banner {
            display: flex;
            align-items: center;
            gap: 10px;
            background: oklch(0.27 0.038 225.31);
            border: 1px solid oklch(0.42 0.04 225.31);
            border-radius: 4px;
            padding: 8px 12px;
            margin-bottom: 12px;
            font-size: 13px;
            color: oklch(0.74 0.075 225.31);
        }

        .filter-label {
            flex: 1;
        }

        .filter-label strong {
            color: oklch(0.91 0.012 225.31);
        }

        .filter-clear {
            background: none;
            border: 1px solid oklch(0.42 0.04 225.31);
            color: oklch(0.74 0.075 225.31);
            padding: 2px 8px;
            border-radius: 3px;
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
        }

        .filter-clear:hover {
            color: oklch(0.91 0.012 225.31);
            border-color: oklch(0.52 0.05 225.31);
            background: oklch(0.32 0.045 225.31);
        }

        .show-all-btn {
            background: none;
            border: none;
            color: oklch(0.74 0.075 225.31);
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
            padding: 4px 0;
            text-decoration: underline;
        }

        .show-all-btn:hover {
            color: oklch(0.91 0.012 225.31);
            background: oklch(0.32 0.045 225.31);
        }

        .period-selector {
            display: flex;
            gap: 6px;
            margin-bottom: 16px;
        }

        .period-btn {
            background: none;
            border: 1px solid oklch(0.42 0.04 225.31);
            color: oklch(0.74 0.075 225.31);
            padding: 4px 12px;
            border-radius: 3px;
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
        }

        .period-btn:hover {
            color: oklch(0.91 0.012 225.31);
            border-color: oklch(0.7 0.1274 357.86);
        }

        .period-btn.active {
            background: oklch(0.5 0.1274 357.86);
            border-color: oklch(0.7 0.1274 357.86);
            color: oklch(0.97 0.01 357.86);
        }

        .custom-range {
            display: flex;
            gap: 8px;
            margin-top: 8px;
            align-items: center;
        }

        .custom-range-input {
            background: oklch(0.27 0.038 225.31);
            border: 1px solid oklch(0.42 0.04 225.31);
            color: oklch(0.91 0.012 225.31);
            padding: 4px 8px;
            border-radius: 3px;
            font-family: inherit;
            font-size: 12px;
            width: 220px;
        }

        .custom-range-input::placeholder {
            color: oklch(0.74 0.075 225.31);
            opacity: 0.7;
        }

        .custom-range-input:focus {
            outline: none;
            border-color: oklch(0.91 0.012 225.31);
        }

        .custom-range-input.error {
            border-color: oklch(0.68 0.11 225.31);
        }

        .custom-range-error {
            color: oklch(0.68 0.11 225.31);
            font-size: 12px;
            margin-top: 4px;
        }

        .similar-btn {
            background: none;
            border: 1px solid oklch(0.42 0.04 225.31);
            color: oklch(0.74 0.075 225.31);
            padding: 2px 8px;
            border-radius: 3px;
            cursor: pointer;
            font-family: inherit;
            font-size: 10px;
            margin-top: 4px;
            transition: all 0.2s ease;
        }

        .similar-btn:hover {
            background: oklch(0.32 0.045 225.31);
            color: oklch(0.91 0.012 225.31);
            border-color: oklch(0.7 0.1274 357.86);
        }

        .similar-btn.active {
            background: oklch(0.5 0.1274 357.86);
            color: oklch(0.97 0.01 357.86);
            border-color: oklch(0.7 0.1274 357.86);
            box-shadow: 2px 2px 0px oklch(0.7 0.1274 357.86);
        }

        .similar-panel {
            margin-top: 10px;
            background: oklch(0.27 0.038 225.31);
            border: 1px solid oklch(0.42 0.04 225.31);
            border-radius: 4px;
            padding: 10px;
            box-shadow: 2px 2px 0px oklch(0.42 0.04 225.31);
        }

        .similar-panel-header {
            font-size: 11px;
            color: oklch(0.74 0.075 225.31);
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 8px;
            font-weight: bold;
        }

        .similar-loading {
            color: oklch(0.74 0.075 225.31);
            font-size: 12px;
            text-align: center;
            padding: 8px;
        }

        .similar-error {
            color: oklch(0.78 0.085 225.31);
            font-size: 12px;
            text-align: center;
            padding: 8px;
        }

        .similar-empty {
            color: oklch(0.74 0.075 225.31);
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
            background: oklch(0.27 0.038 225.31);
            border-radius: 3px;
            border-left: 2px solid oklch(0.42 0.04 225.31);
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
            color: oklch(0.91 0.012 225.31);
            font-weight: 500;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .similar-track-artist {
            font-size: 11px;
            color: oklch(0.70 0.035 225.31);
            margin-top: 1px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .similar-score {
            font-size: 10px;
            color: oklch(0.74 0.075 225.31);
            background: oklch(0.27 0.038 225.31);
            border: 1px solid oklch(0.42 0.04 225.31);
            padding: 2px 6px;
            border-radius: 2px;
            margin-right: 8px;
            font-weight: 500;
        }

        .similar-link {
            color: oklch(0.74 0.075 225.31);
            text-decoration: none;
            font-size: 12px;
            background: oklch(0.27 0.038 225.31);
            border: 1px solid oklch(0.42 0.04 225.31);
            padding: 2px 6px;
            border-radius: 2px;
            transition: all 0.2s ease;
        }

        .similar-link:hover {
            color: oklch(0.78 0.13 357.86);
            background: oklch(0.42 0.04 225.31);
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
            background: oklch(0.27 0.038 225.31);
            border: 1px solid oklch(0.42 0.04 225.31);
            color: oklch(0.91 0.012 225.31);
            padding: 6px 10px;
            border-radius: 4px;
            font-family: inherit;
            font-size: 13px;
        }

        .search-input::placeholder {
            color: oklch(0.74 0.075 225.31);
            opacity: 0.7;
        }

        .search-input:focus {
            outline: none;
            border-color: oklch(0.91 0.012 225.31);
        }

        .search-btn {
            background: oklch(0.32 0.045 225.31);
            border: 1px solid oklch(0.52 0.05 225.31);
            color: oklch(0.91 0.012 225.31);
            padding: 6px 12px;
            border-radius: 4px;
            cursor: pointer;
            font-family: inherit;
            font-size: 12px;
        }

        .search-btn:hover {
            background: oklch(0.42 0.05 225.31);
            border-color: oklch(0.52 0.05 225.31);
        }

        .search-bar:focus-within .search-btn {
            background: oklch(0.5 0.1274 357.86);
            border-color: oklch(0.7 0.1274 357.86);
            color: oklch(0.97 0.01 357.86);
        }

        .about-lead {
            color: oklch(0.70 0.035 225.31);
            font-size: 13px;
            line-height: 1.8;
            margin: 0 0 30px 0;
        }

        .about-link {
            color: oklch(0.74 0.075 225.31);
            text-decoration: underline;
        }

        .about-link:hover {
            color: oklch(0.78 0.13 357.86);
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
            color: oklch(0.70 0.035 225.31);
        }

        .about-list li::before {
            content: "→  ";
            color: oklch(0.42 0.04 225.31);
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
            color: oklch(0.74 0.075 225.31);
            text-decoration: none;
            font-size: 13px;
        }

        .about-users a:hover {
            color: oklch(0.78 0.13 357.86);
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
            flags: { userSlug: userSlug, allUsers: allUsers }
        });
    </script>
</body>
</html>"""
