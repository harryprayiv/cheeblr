module API.Stock where

import Prelude

import API.Request as Request
import Data.Either (Either)
import Effect.Aff (Aff)
import Services.AuthService (UserId)
import Types.Inventory (MutationResponse)
import Types.Stock (PullRequest, PullRequestDetail, PullMessage)
import Types.UUID (UUID)
import Data.Maybe (Maybe, fromMaybe)

getQueue :: UserId -> Maybe String -> Aff (Either String (Array PullRequest))
getQueue userId mLocId =
  let path = "/stock/queue" <> fromMaybe "" (map ("?locationId=" <> _) mLocId)
  in Request.authGet userId path

getPullDetail :: UserId -> UUID -> Aff (Either String PullRequestDetail)
getPullDetail userId pullId =
  Request.authGet userId ("/stock/pull/" <> show pullId)

acceptPull :: UserId -> UUID -> Aff (Either String MutationResponse)
acceptPull userId pullId =
  Request.authPostUnit userId ("/stock/pull/" <> show pullId <> "/accept")
    >>= \r -> pure (map (const { success: true, message: "Accepted" }) r)

startPull :: UserId -> UUID -> Aff (Either String MutationResponse)
startPull userId pullId =
  Request.authPostUnit userId ("/stock/pull/" <> show pullId <> "/start")
    >>= \r -> pure (map (const { success: true, message: "Started" }) r)

fulfillPull :: UserId -> UUID -> Aff (Either String MutationResponse)
fulfillPull userId pullId =
  Request.authPostUnit userId ("/stock/pull/" <> show pullId <> "/fulfill")
    >>= \r -> pure (map (const { success: true, message: "Fulfilled" }) r)

reportIssue :: UserId -> UUID -> String -> Aff (Either String MutationResponse)
reportIssue userId pullId note =
  Request.authPost userId ("/stock/pull/" <> show pullId <> "/issue") { irNote: note }

retryPull :: UserId -> UUID -> Aff (Either String MutationResponse)
retryPull userId pullId =
  Request.authPostUnit userId ("/stock/pull/" <> show pullId <> "/retry")
    >>= \r -> pure (map (const { success: true, message: "Retried" }) r)

sendMessage :: UserId -> UUID -> String -> Aff (Either String MutationResponse)
sendMessage userId pullId msg =
  Request.authPost userId ("/stock/pull/" <> show pullId <> "/message") { nmMessage: msg }

getMessages :: UserId -> UUID -> Aff (Either String (Array PullMessage))
getMessages userId pullId =
  Request.authGet userId ("/stock/pull/" <> show pullId <> "/messages")