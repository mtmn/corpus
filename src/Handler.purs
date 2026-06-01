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
import Node.Stream (end, writeString)
import Node.HTTP.Types (ServerResponse, IncomingMessage, IMServer)

type Request = IncomingMessage IMServer

type Response = ServerResponse

respond :: String -> Int -> String -> Response -> Effect Unit
respond contentType statusCode body res = do
  setHeader "Content-Type" contentType (toOutgoingMessage res)
  setStatusCode statusCode res
  let w = toWriteable (toOutgoingMessage res)
  void $ writeString w UTF8 body
  end w

serveNotFound :: Response -> Effect Unit
serveNotFound = respond "text/plain" 404 "Not Found"

serveUnauthorized :: Response -> Effect Unit
serveUnauthorized = respond "text/plain" 401 "Unauthorized"

serveInternalError :: Response -> Effect Unit
serveInternalError = respond "text/plain" 500 "Internal Server Error"

serveBadRequest :: Response -> String -> Effect Unit
serveBadRequest res message = respond "text/plain" 400 message res

serveError :: Response -> Int -> String -> String -> Effect Unit
serveError res statusCode statusName message =
  respond "text/plain" statusCode (statusName <> ": " <> message) res
