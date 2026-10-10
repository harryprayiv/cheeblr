module API.Stock where

import Prelude

import API.Request (ApiError)
import API.Request as Request
import Config.Network (currentConfig)
import Data.Either (Either)
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Types.Inventory (MutationResponse)
import Types.Location (LocationId(..))
import Types.Stock (PullMessage, PullRequest)
import Types.UUID (UUID)

pullUrl :: UUID -> String -> String
pullUrl pullId action = "/stock/pull/" <> show pullId <> "/" <> action

getQueue :: Maybe LocationId -> Aff (Either ApiError (Array PullRequest))
getQueue mLocId =
  Request.get $ "/stock/queue" <> case mLocId of
    Nothing -> ""
    Just (LocationId uid) -> "?locationId=" <> show uid

cancelPull :: UUID -> String -> Aff (Either ApiError MutationResponse)
cancelPull pullId reason =
  Request.post (pullUrl pullId "cancel") { irNote: reason }

acceptPull :: UUID -> Aff (Either ApiError MutationResponse)
acceptPull pullId = Request.postEmpty (pullUrl pullId "accept")

startPull :: UUID -> Aff (Either ApiError MutationResponse)
startPull pullId = Request.postEmpty (pullUrl pullId "start")

fulfillPull :: UUID -> Aff (Either ApiError MutationResponse)
fulfillPull pullId = Request.postEmpty (pullUrl pullId "fulfill")

retryPull :: UUID -> Aff (Either ApiError MutationResponse)
retryPull pullId = Request.postEmpty (pullUrl pullId "retry")

reportIssue :: UUID -> String -> Aff (Either ApiError MutationResponse)
reportIssue pullId note =
  Request.post (pullUrl pullId "issue") { irNote: note }

getMessages :: UUID -> Aff (Either ApiError (Array PullMessage))
getMessages pullId = Request.get (pullUrl pullId "messages")

sendMessage :: UUID -> String -> Aff (Either ApiError MutationResponse)
sendMessage pullId msg =
  Request.post (pullUrl pullId "message") { nmMessage: msg }

-- Authenticated by the session cookie. See Utils.SSE.
queueStreamUrl :: String
queueStreamUrl = currentConfig.apiBaseUrl <> "/stock/queue/stream"
