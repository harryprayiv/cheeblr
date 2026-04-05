module API.Stock where

import Prelude

import Config.Network (currentConfig)
import Effect.Aff (Aff, attempt, throwError)
import Effect.Exception (error)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Fetch (Method(..), RequestCredentials(..), fetch)
import Fetch.Yoga.Json (fromJSON)
import Types.Inventory (MutationResponse)
import Types.Location (LocationId(..))
import Types.Stock (PullMessage, PullRequest)
import Types.UUID (UUID)
import Yoga.JSON (class ReadForeign, writeJSON)

type UserId = String

base :: String
base = currentConfig.apiBaseUrl

apiRequest
  :: forall a
   . ReadForeign a
  => String
  -> Method
  -> UserId
  -> Maybe String
  -> Aff (Either String a)
apiRequest url method token mBody = do
  result <- attempt do
    response <- case mBody of
      Nothing ->
        fetch url
          { method
          , headers:
              { "Content-Type":  "application/json"
              , "Accept":        "application/json"
              , "Authorization": "Bearer " <> token
              }
          , credentials: Include
          }
      Just body ->
        fetch url
          { method
          , body
          , headers:
              { "Content-Type":  "application/json"
              , "Accept":        "application/json"
              , "Authorization": "Bearer " <> token
              }
          , credentials: Include
          }
    if response.status >= 200 && response.status < 300
      then fromJSON response.json
      else do
        errText <- response.text
        throwError (error errText)
  pure $ case result of
    Left err -> Left $ show err
    Right v  -> Right v

apiRequestUnit
  :: String
  -> Method
  -> UserId
  -> Maybe String
  -> Aff (Either String Unit)
apiRequestUnit url method token mBody = do
  result <- attempt do
    response <- case mBody of
      Nothing ->
        fetch url
          { method
          , headers:
              { "Content-Type":  "application/json"
              , "Accept":        "application/json"
              , "Authorization": "Bearer " <> token
              }
          , credentials: Include
          }
      Just body ->
        fetch url
          { method
          , body
          , headers:
              { "Content-Type":  "application/json"
              , "Accept":        "application/json"
              , "Authorization": "Bearer " <> token
              }
          , credentials: Include
          }
    if response.status >= 200 && response.status < 300
      then pure unit
      else do
        errText <- response.text
        throwError (error errText)
  pure $ case result of
    Left err -> Left $ show err
    Right _  -> Right unit

getQueue :: UserId -> Maybe LocationId -> Aff (Either String (Array PullRequest))
getQueue token mLocId =
  let url = base <> "/stock/queue" <> case mLocId of
              Nothing              -> ""
              Just (LocationId uid) -> "?locationId=" <> show uid
  in apiRequest url GET token Nothing

cancelPull :: UserId -> UUID -> String -> Aff (Either String MutationResponse)
cancelPull token pullId reason =
  apiRequest
    (base <> "/stock/pull/" <> show pullId <> "/cancel")
    POST
    token
    (Just (writeJSON { irNote: reason }))

acceptPull :: UserId -> UUID -> Aff (Either String MutationResponse)
acceptPull token pullId =
  apiRequest (base <> "/stock/pull/" <> show pullId <> "/accept") POST token (Just "{}")

startPull :: UserId -> UUID -> Aff (Either String MutationResponse)
startPull token pullId =
  apiRequest (base <> "/stock/pull/" <> show pullId <> "/start") POST token (Just "{}")

fulfillPull :: UserId -> UUID -> Aff (Either String MutationResponse)
fulfillPull token pullId =
  apiRequest (base <> "/stock/pull/" <> show pullId <> "/fulfill") POST token (Just "{}")

retryPull :: UserId -> UUID -> Aff (Either String MutationResponse)
retryPull token pullId =
  apiRequest (base <> "/stock/pull/" <> show pullId <> "/retry") POST token (Just "{}")

reportIssue :: UserId -> UUID -> String -> Aff (Either String MutationResponse)
reportIssue token pullId note =
  apiRequest
    (base <> "/stock/pull/" <> show pullId <> "/issue")
    POST
    token
    (Just (writeJSON { irNote: note }))

getMessages :: UserId -> UUID -> Aff (Either String (Array PullMessage))
getMessages token pullId =
  apiRequest
    (base <> "/stock/pull/" <> show pullId <> "/messages")
    GET
    token
    Nothing

sendMessage :: UserId -> UUID -> String -> Aff (Either String MutationResponse)
sendMessage token pullId msg =
  apiRequest
    (base <> "/stock/pull/" <> show pullId <> "/message")
    POST
    token
    (Just (writeJSON { nmMessage: msg }))