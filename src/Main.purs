module Main where

import Prelude

import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Console as Console
import Node.HTTP (createServer)
import Node.HTTPS as HTTPS
import Node.HTTP.Server as Server
import Node.EventEmitter (on_, EventHandle(..))
import Effect.Uncurried (mkEffectFn1)
import Node.HTTP.ClientRequest as Client
import Node.HTTP.IncomingMessage as IM
import Node.HTTP.Types (ServerResponse, IncomingMessage, IMServer)
import Node.HTTP.ServerResponse (setStatusCode, toOutgoingMessage)
import Node.HTTP.OutgoingMessage (setHeader, toWriteable)
import Node.Stream (end, writeString)
import Node.Stream.Aff (readableToStringUtf8)
import Node.Encoding (Encoding(UTF8))
import Node.Net.Server (listenTcp, listeningH)
import Data.Either (Either(..))
import Effect.Exception as Exception
import Effect.Aff (Aff, launchAff_, makeAff, nonCanceler, try)
import Unsafe.Coerce (unsafeCoerce)

-- Types
type Request = IncomingMessage IMServer
type Response = ServerResponse

type ProxyConfig =
  { port :: Int
  , listenBrainzUrl :: String
  }

listenBrainzUrl :: String
listenBrainzUrl = "https://api.listenbrainz.org/1/user/mtmn/listens"

fetchListenBrainzData :: Aff String
fetchListenBrainzData = makeAff \callback -> do
  Console.log $ "Fetching from ListenBrainz: " <> listenBrainzUrl
  req <- HTTPS.get listenBrainzUrl

  req # on_ Client.responseH \res -> do
    let sc = IM.statusCode res
    Console.log $ "ListenBrainz response status: " <> show sc
    launchAff_ do
      body <- readableToStringUtf8 (IM.toReadable res)
      liftEffect $ callback (Right body)

  let errorH = EventHandle "error" mkEffectFn1
  on_ errorH
    ( \err -> do
        Console.log $ "ListenBrainz fetch error: " <> Exception.message err
        callback (Left err)
    )
    (unsafeCoerce req)

  pure nonCanceler

handleApiRequest :: Aff String
handleApiRequest = do
  result <- try fetchListenBrainzData
  case result of
    Right responseData -> do
      liftEffect $ Console.log $ "Successfully fetched bytes"
      pure responseData
    Left error -> do
      liftEffect $ Console.log $ "Error in handleApiRequest: " <> Exception.message error
      pure "{\"error\": \"ListenBrainz fetch failed\"}"

indexHtml :: String
indexHtml =
  """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>scrobbler.mtmn.name</title>
    <script src="https://unpkg.com/htmx.org@2.0.7"></script>
    <style>
        body {
            font-family: 'Courier New', 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            background: #332d38;
            color: #ffffff;
            margin: 0;
            padding: 20px;
            line-height: 1.6;
        }
        
        .container {
            max-width: 800px;
            margin: 0 auto;
        }
        
        h1 {
            color: #ffffff;
            margin-bottom: 20px;
            font-size: 24px;
        }
        
        ul {
            list-style: none;
            padding: 0;
            margin: 0 0 20px 0;
        }
        
        li {
            background: rgba(0, 0, 0, 0.3);
            border: 1px solid rgba(80, 68, 127, 0.5);
            border-radius: 4px;
            padding: 15px;
            margin-bottom: 10px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        li.success {
            background: rgba(185, 208, 170, 0.2);
            border-color: rgba(185, 208, 170, 0.3);
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
            margin-top: 4px;
        }
        
        .track-time {
            font-size: 12px;
            color: #9fbfe7;
            margin-top: 2px;
        }
        
        .status {
            color: #b9d0aa;
            font-weight: bold;
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
        
        .refresh-btn {
            background: none;
            border: none;
            color: #a0c0d0;
            cursor: pointer;
            font-size: 12px;
            text-decoration: underline;
        }
        
        .refresh-btn:hover {
            color: #ffffff;
        }
        
        .playing-indicator {
            display: inline-block;
            width: 8px;
            height: 8px;
            background: #b9d0aa;
            border-radius: 50%;
            margin-right: 8px;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.3; }
            100% { opacity: 1; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>History</h1>
        <ul id="tracks-container"
            hx-get="/proxy"
            hx-trigger="load, every 30s"
            hx-target="#tracks-container"
            hx-ext="listenbrainz">
            <li class="loading">Loading recent tracks...</li>
        </ul>
        
        <p class="small">
            <a href="https://listenbrainz.org/user/mtmn/">ListenBrainz</a>
        </p>
        
        <p class="small" id="last-updated"></p>
    </div>
    
    <script>
        // Update last updated time
        function updateLastUpdated() {
            const now = new Date();
            document.getElementById('last-updated').textContent = `${now.toISOString()}`;
        }
        
        // Handle ListenBrainz API response
        htmx.defineExtension('listenbrainz', {
            onEvent: function(name, evt) {
                if (name === 'htmx:afterRequest') {
                    const xhr = evt.detail.xhr;
                    if (xhr.status === 200) {
                        try {
                            const data = JSON.parse(xhr.responseText);
                            if (data.payload && data.payload.listens) {
                                const html = generateTracksHTML(data.payload.listens);
                                document.getElementById('tracks-container').innerHTML = html;
                            } else {
                                document.getElementById('tracks-container').innerHTML = '<li class="error">No tracks found</li>';
                            }
                        } catch (e) {
                            document.getElementById('tracks-container').innerHTML = '<li class="error">Error parsing response</li>';
                        }
                    } else {
                        document.getElementById('tracks-container').innerHTML = '<li class="error">Error loading tracks</li>';
                    }
                    updateLastUpdated();
                }
            }
        });
        
        function generateTracksHTML(listens) {
            let html = '';
            listens.forEach((listen, index) => {
                const track = listen.track_metadata;
                const listenedAt = formatTimeAgo(listen.listened_at);
                
                const trackName = track.track_name || 'Unknown Track';
                const artistName = track.artist_name || 'Unknown Artist';
                const releaseName = track.release_name || 'Unknown Album';
                
                const playingIndicator = index === 0 ? '<span class="playing-indicator"></span>' : '';
                
                html += `
                    <li class="success">
                        <div class="track-info">
                            <div class="track-name">${playingIndicator}${escapeHtml(trackName)}</div>
                            <div class="track-artist">${escapeHtml(artistName)}</div>
                            <div class="track-time">${escapeHtml(releaseName)} • ${listenedAt}</div>
                        </div>
                        <span class="status">Played</span>
                    </li>
                `;
            });
            return html;
        }
        
        function formatTimeAgo(timestamp) {
            const now = Math.floor(Date.now() / 1000);
            const diff = now - timestamp;
            
            if (diff < 60) {
                return 'just now';
            } else if (diff < 3600) {
                const minutes = Math.floor(diff / 60);
                return `${minutes} minute${minutes > 1 ? 's' : ''} ago`;
            } else if (diff < 86400) {
                const hours = Math.floor(diff / 3600);
                return `${hours} hour${hours > 1 ? 's' : ''} ago`;
            } else {
                const days = Math.floor(diff / 86400);
                return `${days} day${days > 1 ? 's' : ''} ago`;
            }
        }
        
        function escapeHtml(text) {
            const map = {
                '&': '&amp;',
                '<': '&lt;',
                '>': '&gt;',
                '"': '&quot;',
                "'": '&#39;'
            };
            return text.replace(/[&<>"']/g, m => map[m]);
        }
        
        // Initial update
        updateLastUpdated();
    </script>
</body>
</html>"""

-- Request handler
handleRequest :: Request -> Response -> Effect Unit
handleRequest req res = do
  let path = IM.url req
  Console.log $ "Request received: " <> path

  case path of
    "/" -> serveIndex res
    "/proxy" -> serveProxy res
    "/favicon.ico" -> serveFavicon res
    _ -> serveNotFound res

serveIndex :: Response -> Effect Unit
serveIndex res = do
  setHeader "Content-Type" "text/html" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Methods" "GET, POST, OPTIONS" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Headers" "*" (toOutgoingMessage res)
  setStatusCode 200 res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 indexHtml
  end w

serveProxy :: Response -> Effect Unit
serveProxy res = do
  setHeader "Content-Type" "application/json" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Methods" "GET, POST, OPTIONS" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Headers" "*" (toOutgoingMessage res)

  -- Launch the Aff action to fetch data from ListenBrainz
  launchAff_ do
    body <- handleApiRequest
    liftEffect $ do
      setStatusCode 200 res
      let w = toWriteable (toOutgoingMessage res)
      void $ writeString w UTF8 body
      end w

serveFavicon :: Response -> Effect Unit
serveFavicon res = do
  setHeader "Content-Type" "image/x-icon" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  setStatusCode 200 res
  end (toWriteable (toOutgoingMessage res))

serveNotFound :: Response -> Effect Unit
serveNotFound res = do
  setHeader "Content-Type" "text/plain" (toOutgoingMessage res)
  setHeader "Access-Control-Allow-Origin" "*" (toOutgoingMessage res)
  setStatusCode 404 res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 "Not Found"
  end w

startServer :: Int -> Effect Unit
startServer port = do
  server <- createServer
  server # on_ Server.requestH handleRequest
  let netServer = Server.toNetServer server

  netServer # on_ listeningH do
    Console.log $ "Server is running on port " <> show port

  listenTcp netServer { host: "127.0.0.1", port, backlog: 128 }

main :: Effect Unit
main = do
  startServer 8000
