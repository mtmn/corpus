module Templates where

import Prelude

indexHtml :: String -> String
indexHtml userSlug =
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
            padding: 20px;
            line-height: 1.6;
        }

        ::selection {
            background: #50447f;
            color: #ffffff;
        }

        .container {
            max-width: 800px;
            margin: 0 auto;
        }

        h1 {
            color: #ffffff;
            margin-bottom: 20px;
            font-size: 24px;
            border-bottom: 2px solid #50447f;
            display: inline-block;
            padding-bottom: 5px;
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
            padding: 15px;
            margin-bottom: 10px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            box-shadow: 4px 4px 0px #50447f;
        }

        li.success {
            background: #521e40;
            border-color: #50447f;
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
            margin-left: 15px;
            gap: 4px;
            flex-shrink: 0;
            position: relative;
        }

        .genre-tag {
            position: absolute;
            top: 100%;
            left: 50%;
            transform: translateX(-50%);
            font-size: 10px;
            color: #9fbfe7;
            text-align: center;
            max-width: 60px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            opacity: 0.8;
        }

        .genre-tag:hover {
            max-width: none;
            overflow: visible;
            text-overflow: clip;
            background: #521e40;
            border: 1px solid #50447f;
            border-radius: 4px;
            padding: 2px 6px;
            z-index: 100;
            opacity: 1;
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
            border-color: #50447f;
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
    </style>
</head>
<body>
    <div id="app"></div>
    <script src="/client.js"></script>
    <script>
        var userSlug = '""" <> userSlug <>
    """';
        var app = Elm.Client.init({
            node: document.getElementById('app'),
            flags: { search: window.location.search, userSlug: userSlug }
        });
        app.ports.pushUrl.subscribe(function(url) {
            var prefix = userSlug ? '/~' + userSlug : '';
            history.pushState({}, '', prefix + url);
        });
    </script>
</body>
</html>"""
