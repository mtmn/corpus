module Handler
  ( Response
  , Request
  , serveNotFound
  , serveUnauthorized
  , serveInternalError
  , serveBadRequest
  , serveError
  , respond
  ) where

import Prelude

import Effect (Effect)
import Node.Encoding (Encoding(UTF8))
import Node.HTTP.OutgoingMessage (setHeader, toWriteable)
import Node.HTTP.ServerResponse (setStatusCode, toOutgoingMessage)
import Node.HTTP.Types (IMServer, IncomingMessage, ServerResponse)
import Node.Stream (end, writeString)

-- | Incoming HTTP request handled by the application server.
type Request = IncomingMessage IMServer

-- | Outgoing HTTP response written by route handlers.
type Response = ServerResponse

-- | Write a response with the supplied MIME type, status, and body.
respond :: String -> Int -> String -> Response -> Effect Unit
respond contentType statusCode body res = do
  setHeader "Content-Type" contentType (toOutgoingMessage res)
  setStatusCode statusCode res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 body
  end w

-- | Write the standard 404 response.
serveNotFound :: Response -> Effect Unit
serveNotFound = respond "text/plain" 404 "Not Found"

-- | Write the standard 401 response.
serveUnauthorized :: Response -> Effect Unit
serveUnauthorized = respond "text/plain" 401 "Unauthorized"

-- | Write the standard 500 response.
serveInternalError :: Response -> Effect Unit
serveInternalError = respond "text/plain" 500 "Internal Server Error"

-- | Write a 400 response with a caller-supplied message.
serveBadRequest :: Response -> String -> Effect Unit
serveBadRequest res message = respond "text/plain" 400 message res

-- | Write an error response with an explicit status and status name.
serveError :: Response -> Int -> String -> String -> Effect Unit
serveError res statusCode statusName message =
  respond "text/plain" statusCode (statusName <> ": " <> message) res
