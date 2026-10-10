module API.Request
  ( ApiError(..)
  , URL
  , status
  , describe
  , isRefusal
  , get
  , getAbsolute
  , post
  , postEmpty
  , postUnit
  , put
  , delete
  , deleteUnit
  ) where

import Prelude

import Config.Network (currentConfig)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff, attempt)
import Effect.Exception (message)
import Fetch (Method(..), RequestCredentials(..), fetch)
import Fetch.Yoga.Json (fromJSON)
import Foreign (Foreign)
import Yoga.JSON (class ReadForeign, class WriteForeign, writeJSON)

type URL = String

-- What can go wrong with one request.
--   Refused:     the server answered with a status outside 200 to 299. Carries
--                the status and the response body as text.
--   Unreachable: fetch itself failed (network, CORS, TLS).
--   Undecodable: the server answered 2xx and the body did not decode.
data ApiError
  = Refused Int String
  | Unreachable String
  | Undecodable String

derive instance eqApiError :: Eq ApiError

instance showApiError :: Show ApiError where
  show (Refused code body) = "Refused " <> show code <> " " <> show body
  show (Unreachable msg) = "Unreachable " <> show msg
  show (Undecodable msg) = "Undecodable " <> show msg

status :: ApiError -> Maybe Int
status = case _ of
  Refused code _ -> Just code
  _ -> Nothing

-- True when the error is a refusal with exactly this status.
isRefusal :: Int -> ApiError -> Boolean
isRefusal code err = status err == Just code

-- Text for showing to a person. A refusal shows the server's own message.
describe :: ApiError -> String
describe = case _ of
  Refused code "" ->
    "The server refused the request (HTTP " <> show code <> ")"
  Refused _ body -> body
  Unreachable msg -> "Could not reach the server: " <> msg
  Undecodable msg -> "The server's answer could not be read: " <> msg

-- The one place a request is sent. Authentication is the HttpOnly session
-- cookie, so credentials are always included and no Authorization header is
-- set. The status is checked before the body is decoded.
request
  :: forall a
   . Method
  -> String
  -> Maybe String
  -> (Aff Foreign -> Aff a)
  -> Aff (Either ApiError a)
request method fullUrl mBody decode = do
  sent <- attempt case mBody of
    Nothing ->
      fetch fullUrl
        { method
        , headers: { "Accept": "application/json" }
        , credentials: Include
        }
    Just body ->
      fetch fullUrl
        { method
        , body
        , headers:
            { "Content-Type": "application/json"
            , "Accept": "application/json"
            }
        , credentials: Include
        }
  case sent of
    Left err ->
      pure (Left (Unreachable (message err)))
    Right response ->
      if response.status >= 200 && response.status < 300 then do
        decoded <- attempt (decode response.json)
        pure case decoded of
          Left err -> Left (Undecodable (message err))
          Right value -> Right value
      else do
        body <- attempt response.text
        pure case body of
          Left _ -> Left (Refused response.status "")
          Right text -> Left (Refused response.status text)

url :: URL -> String
url path = currentConfig.apiBaseUrl <> path

get :: forall a. ReadForeign a => URL -> Aff (Either ApiError a)
get path = request GET (url path) Nothing fromJSON

getAbsolute :: forall a. ReadForeign a => String -> Aff (Either ApiError a)
getAbsolute fullUrl = request GET fullUrl Nothing fromJSON

post
  :: forall req res
   . WriteForeign req
  => ReadForeign res
  => URL
  -> req
  -> Aff (Either ApiError res)
post path body = request POST (url path) (Just (writeJSON body)) fromJSON

postEmpty :: forall a. ReadForeign a => URL -> Aff (Either ApiError a)
postEmpty path = request POST (url path) Nothing fromJSON

-- For routes that answer with no body.
postUnit :: URL -> Aff (Either ApiError Unit)
postUnit path = request POST (url path) Nothing (\_ -> pure unit)

put
  :: forall req res
   . WriteForeign req
  => ReadForeign res
  => URL
  -> req
  -> Aff (Either ApiError res)
put path body = request PUT (url path) (Just (writeJSON body)) fromJSON

delete :: forall a. ReadForeign a => URL -> Aff (Either ApiError a)
delete path = request DELETE (url path) Nothing fromJSON

-- For routes that answer with no body.
deleteUnit :: URL -> Aff (Either ApiError Unit)
deleteUnit path = request DELETE (url path) Nothing (\_ -> pure unit)
