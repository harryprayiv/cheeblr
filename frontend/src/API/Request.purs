module Cheeblr.API.Request where

import Prelude

import Cheeblr.API.Config (currentConfig)
import Data.Either (Either(..))
import Effect.Aff (Aff, attempt, error, throwError)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Fetch (Method(..), fetch)
import Fetch.Yoga.Json (fromJSON)
import Yoga.JSON (class ReadForeign, class WriteForeign, writeJSON)

type URL = String

----------------------------------------------------------------------
-- Core request runner
----------------------------------------------------------------------

-- | Execute an Aff action and catch errors into Either.
-- | All API calls go through this for uniform error handling.
runRequest :: forall a. String -> Aff a -> Aff (Either String a)
runRequest label action = do
  result <- attempt action
  case result of
    Left err -> do
      let msg = label <> " error: " <> show err
      liftEffect $ Console.error msg
      pure $ Left msg
    Right value ->
      pure $ Right value

----------------------------------------------------------------------
-- Headers
----------------------------------------------------------------------

type RequestHeaders =
  { "Content-Type" :: String
  , "Accept" :: String
  , "Origin" :: String
  , "X-User-Id" :: String
  }

mkHeaders :: String -> RequestHeaders
mkHeaders userId =
  { "Content-Type": "application/json"
  , "Accept": "application/json"
  , "Origin": currentConfig.appOrigin
  , "X-User-Id": userId
  }

----------------------------------------------------------------------
-- GET
----------------------------------------------------------------------

-- | GET request to a relative API path.
get :: forall a. ReadForeign a => String -> URL -> Aff (Either String a)
get userId url =
  runRequest ("GET " <> url) do
    response <- fetch (currentConfig.apiBaseUrl <> url)
      { method: GET, headers: mkHeaders userId }
    fromJSON response.json

-- | GET request to a full URL (for external endpoints).
getFullUrl :: forall a. ReadForeign a => String -> String -> Aff (Either String a)
getFullUrl userId fullUrl =
  runRequest ("GET " <> fullUrl) do
    response <- fetch fullUrl
      { method: GET, headers: mkHeaders userId }
    fromJSON response.json

----------------------------------------------------------------------
-- POST
----------------------------------------------------------------------

-- | POST with a JSON body, expecting a JSON response.
post :: forall req res. WriteForeign req => ReadForeign res
     => String -> URL -> req -> Aff (Either String res)
post userId url body =
  runRequest ("POST " <> url) do
    response <- fetch (currentConfig.apiBaseUrl <> url)
      { method: POST, body: writeJSON body, headers: mkHeaders userId }
    fromJSON response.json

-- | POST with no body, expecting a JSON response.
postEmpty :: forall a. ReadForeign a => String -> URL -> Aff (Either String a)
postEmpty userId url =
  runRequest ("POST " <> url) do
    response <- fetch (currentConfig.apiBaseUrl <> url)
      { method: POST, headers: mkHeaders userId }
    fromJSON response.json

-- | POST with no body, expecting no meaningful response.
postUnit :: String -> URL -> Aff (Either String Unit)
postUnit userId url =
  runRequest ("POST " <> url) do
    _ <- fetch (currentConfig.apiBaseUrl <> url)
      { method: POST, headers: mkHeaders userId }
    pure unit

-- | POST with body, checking HTTP status before parsing.
-- | Use this for endpoints that return error bodies on failure.
postChecked :: forall req res. WriteForeign req => ReadForeign res
            => String -> URL -> req -> Aff (Either String res)
postChecked userId url body = do
  result <- attempt do
    response <- fetch (currentConfig.apiBaseUrl <> url)
      { method: POST, body: writeJSON body, headers: mkHeaders userId }
    if response.status >= 200 && response.status < 300 then
      fromJSON response.json
    else do
      errorText <- response.text
      throwError
        ( error $ "Server returned status " <> show response.status
            <> ": " <> errorText
        )
  case result of
    Left err -> do
      liftEffect $ Console.error $ "POST " <> url <> " error: " <> show err
      pure $ Left $ show err
    Right value ->
      pure $ Right value

----------------------------------------------------------------------
-- PUT
----------------------------------------------------------------------

-- | PUT with a JSON body, expecting a JSON response.
put :: forall req res. WriteForeign req => ReadForeign res
    => String -> URL -> req -> Aff (Either String res)
put userId url body =
  runRequest ("PUT " <> url) do
    response <- fetch (currentConfig.apiBaseUrl <> url)
      { method: PUT, body: writeJSON body, headers: mkHeaders userId }
    fromJSON response.json

----------------------------------------------------------------------
-- DELETE
----------------------------------------------------------------------

-- | DELETE expecting a JSON response.
delete :: forall a. ReadForeign a => String -> URL -> Aff (Either String a)
delete userId url =
  runRequest ("DELETE " <> url) do
    response <- fetch (currentConfig.apiBaseUrl <> url)
      { method: DELETE, headers: mkHeaders userId }
    fromJSON response.json

-- | DELETE expecting no meaningful response.
deleteUnit :: String -> URL -> Aff (Either String Unit)
deleteUnit userId url =
  runRequest ("DELETE " <> url) do
    _ <- fetch (currentConfig.apiBaseUrl <> url)
      { method: DELETE, headers: mkHeaders userId }
    pure unit