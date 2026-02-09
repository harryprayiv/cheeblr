module API.Request where

import Prelude

import Data.Either (Either(..))
import Effect.Aff (Aff, attempt, error, throwError)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import Fetch (Method(..), fetch)
import Fetch.Yoga.Json (fromJSON)
import Config.Network (currentConfig)
import Services.AuthService (AuthContext, getCurrentUserId)
import Yoga.JSON (class ReadForeign, class WriteForeign, writeJSON)

type URL = String

apiBaseUrl :: String
apiBaseUrl = currentConfig.apiBaseUrl

-- | Get the current user's ID as a string for the X-User-Id header.
getUserIdHeader :: Ref AuthContext -> Aff String
getUserIdHeader authRef = liftEffect $ show <$> getCurrentUserId authRef

-- | Wraps an Aff action with error handling. All request helpers use this
-- | so error handling is consistent across the app.
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

-- | GET with parsed JSON response.
-- | Used by: readInventory, getRegister, getTransaction, fetchInventoryFromHttp
authGet
  :: forall a
   . ReadForeign a
  => Ref AuthContext
  -> URL
  -> Aff (Either String a)
authGet authRef url = do
  userId <- getUserIdHeader authRef
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

-- | GET to a full URL (not prefixed with apiBaseUrl).
-- | Used by: fetchInventoryFromHttp when endpoint differs from apiBaseUrl.
authGetFullUrl
  :: forall a
   . ReadForeign a
  => Ref AuthContext
  -> String
  -> Aff (Either String a)
authGetFullUrl authRef fullUrl = do
  userId <- getUserIdHeader authRef
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

-- | POST with JSON body and parsed JSON response.
-- | Used by: writeInventory, createRegister, openRegister, closeRegister,
-- |          addPaymentTransaction, voidTransaction
authPost
  :: forall req res
   . WriteForeign req
  => ReadForeign res
  => Ref AuthContext
  -> URL
  -> req
  -> Aff (Either String res)
authPost authRef url body = do
  userId <- getUserIdHeader authRef
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

-- | PUT with JSON body and parsed JSON response.
-- | Used by: updateInventory
authPut
  :: forall req res
   . WriteForeign req
  => ReadForeign res
  => Ref AuthContext
  -> URL
  -> req
  -> Aff (Either String res)
authPut authRef url body = do
  userId <- getUserIdHeader authRef
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

-- | DELETE with parsed JSON response.
-- | Used by: deleteInventory
authDelete
  :: forall a
   . ReadForeign a
  => Ref AuthContext
  -> URL
  -> Aff (Either String a)
authDelete authRef url = do
  userId <- getUserIdHeader authRef
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

-- | DELETE that discards the response body.
-- | Used by: removeTransactionItem, removePaymentTransaction
authDeleteUnit
  :: Ref AuthContext
  -> URL
  -> Aff (Either String Unit)
authDeleteUnit authRef url = do
  userId <- getUserIdHeader authRef
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

-- | POST with no body, discards response. 
-- | Used by: clearTransaction
authPostUnit
  :: Ref AuthContext
  -> URL
  -> Aff (Either String Unit)
authPostUnit authRef url = do
  userId <- getUserIdHeader authRef
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

-- | POST with no body, parsed JSON response.
-- | Used by: finalizeTransaction
authPostEmpty
  :: forall a
   . ReadForeign a
  => Ref AuthContext
  -> URL
  -> Aff (Either String a)
authPostEmpty authRef url = do
  userId <- getUserIdHeader authRef
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

-- | POST with JSON body that checks HTTP status before parsing.
-- | On non-2xx responses, reads the error body as text and returns it as
-- | a Left. This gives callers the raw server error message.
-- | Used by: createTransaction, addTransactionItem
authPostChecked
  :: forall req res
   . WriteForeign req
  => ReadForeign res
  => Ref AuthContext
  -> URL
  -> req
  -> Aff (Either String res)
authPostChecked authRef url body = do
  userId <- getUserIdHeader authRef
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