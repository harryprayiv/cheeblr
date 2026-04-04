module API.Stock where

import Prelude

import Config.Network (currentConfig)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Foreign (Foreign)
import Yoga.JSON (class ReadForeign, read_, writeJSON)
import Types.Inventory (MutationResponse)
import Types.Location (LocationId)
import Types.Stock (PullMessage, PullRequest)
import Types.UUID (UUID)

type UserId = String

-- FFI: see API/Stock.js. body is "" to signal no-body (GET / empty POST).
foreign import fetchCb
  :: String                   -- URL
  -> String                   -- method
  -> String                   -- auth token
  -> String                   -- body ("" = none)
  -> (Foreign -> Effect Unit) -- success
  -> (String -> Effect Unit)  -- error
  -> Effect Unit

-- | Core fetch wrapper using makeAff + callback FFI.
-- Matches the pattern of RegisterService and other modules in this codebase.
apiRequest :: forall a. ReadForeign a => String -> String -> String -> Maybe String -> Aff (Either String a)
apiRequest url method token mBody =
  makeAff \cb -> do
    fetchCb url method token (fromMaybe "" mBody)
      ( \f -> cb $ Right $ case read_ f of
          Nothing -> Left "Failed to decode response"
          Just a  -> Right a
      )
      (\err -> cb (Right (Left err)))
    pure nonCanceler

base :: String
base = currentConfig.apiBaseUrl

-- ---------------------------------------------------------------------------
-- Queue
-- ---------------------------------------------------------------------------

getQueue :: UserId -> Maybe LocationId -> Aff (Either String (Array PullRequest))
getQueue token _ =
  apiRequest (base <> "/stock/queue") "GET" token Nothing

-- ---------------------------------------------------------------------------
-- Transitions
-- ---------------------------------------------------------------------------

acceptPull :: UserId -> UUID -> Aff (Either String MutationResponse)
acceptPull token pullId =
  apiRequest (base <> "/stock/pull/" <> show pullId <> "/accept") "POST" token (Just "{}")

startPull :: UserId -> UUID -> Aff (Either String MutationResponse)
startPull token pullId =
  apiRequest (base <> "/stock/pull/" <> show pullId <> "/start") "POST" token (Just "{}")

fulfillPull :: UserId -> UUID -> Aff (Either String MutationResponse)
fulfillPull token pullId =
  apiRequest (base <> "/stock/pull/" <> show pullId <> "/fulfill") "POST" token (Just "{}")

retryPull :: UserId -> UUID -> Aff (Either String MutationResponse)
retryPull token pullId =
  apiRequest (base <> "/stock/pull/" <> show pullId <> "/retry") "POST" token (Just "{}")

reportIssue :: UserId -> UUID -> String -> Aff (Either String MutationResponse)
reportIssue token pullId note =
  apiRequest
    (base <> "/stock/pull/" <> show pullId <> "/issue")
    "POST"
    token
    (Just (writeJSON { irNote: note }))

-- ---------------------------------------------------------------------------
-- Messages (new)
-- ---------------------------------------------------------------------------

getMessages :: UserId -> UUID -> Aff (Either String (Array PullMessage))
getMessages token pullId =
  apiRequest
    (base <> "/stock/pull/" <> show pullId <> "/messages")
    "GET"
    token
    Nothing

sendMessage :: UserId -> UUID -> String -> Aff (Either String MutationResponse)
sendMessage token pullId msg =
  apiRequest
    (base <> "/stock/pull/" <> show pullId <> "/message")
    "POST"
    token
    (Just (writeJSON { nmMessage: msg }))