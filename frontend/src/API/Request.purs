module API.Request where

import Prelude

import Data.Either (Either(..))
import Effect.Aff (Aff, attempt, error, throwError)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Fetch (Method(..), fetch)
import Fetch.Yoga.Json (fromJSON)
import Config.Network (currentConfig)
import Services.AuthService (UserId)
import Yoga.JSON (class ReadForeign, class WriteForeign, writeJSON)
import Foreign (Foreign)

newtype ForeignRequestBody = ForeignRequestBody Foreign

data ServiceError
  = APIError String
  | ServiceValidationError String
  | NotFoundError String
  | AuthorizationError String
  | NetworkError String
  | UnknownError String

derive instance eqServiceError :: Eq ServiceError
derive instance ordServiceError :: Ord ServiceError

instance showServiceError :: Show ServiceError where
  show (APIError msg) = "API Error: " <> msg
  show (ServiceValidationError msg) = "Validation Error: " <> msg
  show (NotFoundError msg) = "Not Found: " <> msg
  show (AuthorizationError msg) = "Authorization Error: " <> msg
  show (NetworkError msg) = "Network Error: " <> msg
  show (UnknownError msg) = "Unknown Error: " <> msg

type URL = String

apiBaseUrl :: String
apiBaseUrl = currentConfig.apiBaseUrl

runRequest :: forall a. String -> Aff a -> Aff (Either String a)
runRequest label action = do
  result <- attempt action
  case result of
    Left err -> do
      let errorMsg = label <> " error: " <> show err
      liftEffect $ Console.error errorMsg
      pure $ Left errorMsg
    Right value ->
      pure $ Right value

authGet
  :: forall a
   . ReadForeign a
  => UserId
  -> URL
  -> Aff (Either String a)
authGet userId url =
  runRequest ("GET " <> url) do
    response <- fetch (apiBaseUrl <> url)
      { method: GET
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

authGetFullUrl
  :: forall a
   . ReadForeign a
  => UserId
  -> String
  -> Aff (Either String a)
authGetFullUrl userId fullUrl =
  runRequest ("GET " <> fullUrl) do
    response <- fetch fullUrl
      { method: GET
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

authPost
  :: forall req res
   . WriteForeign req
  => ReadForeign res
  => UserId
  -> URL
  -> req
  -> Aff (Either String res)
authPost userId url body =
  runRequest ("POST " <> url) do
    response <- fetch (apiBaseUrl <> url)
      { method: POST
      , body: writeJSON body
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

authPut
  :: forall req res
   . WriteForeign req
  => ReadForeign res
  => UserId
  -> URL
  -> req
  -> Aff (Either String res)
authPut userId url body =
  runRequest ("PUT " <> url) do
    response <- fetch (apiBaseUrl <> url)
      { method: PUT
      , body: writeJSON body
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

authDelete
  :: forall a
   . ReadForeign a
  => UserId
  -> URL
  -> Aff (Either String a)
authDelete userId url =
  runRequest ("DELETE " <> url) do
    response <- fetch (apiBaseUrl <> url)
      { method: DELETE
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

authDeleteUnit
  :: UserId
  -> URL
  -> Aff (Either String Unit)
authDeleteUnit userId url =
  runRequest ("DELETE " <> url) do
    _ <- fetch (apiBaseUrl <> url)
      { method: DELETE
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    pure unit

authPostUnit
  :: UserId
  -> URL
  -> Aff (Either String Unit)
authPostUnit userId url =
  runRequest ("POST " <> url) do
    _ <- fetch (apiBaseUrl <> url)
      { method: POST
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    pure unit

authPostEmpty
  :: forall a
   . ReadForeign a
  => UserId
  -> URL
  -> Aff (Either String a)
authPostEmpty userId url =
  runRequest ("POST " <> url) do
    response <- fetch (apiBaseUrl <> url)
      { method: POST
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

authPostChecked
  :: forall req res
   . WriteForeign req
  => ReadForeign res
  => UserId
  -> URL
  -> req
  -> Aff (Either String res)
authPostChecked userId url body = do
  result <- attempt do
    response <- fetch (apiBaseUrl <> url)
      { method: POST
      , body: writeJSON body
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    if response.status >= 200 && response.status < 300 then
      fromJSON response.json
    else do
      errorText <- response.text
      throwError
        ( error $ "Server returned status " <> show response.status
            <> ": "
            <> errorText
        )
  case result of
    Left err -> do
      liftEffect $ Console.error $ "POST " <> url <> " error: " <> show err
      pure $ Left $ show err
    Right value ->
      pure $ Right value