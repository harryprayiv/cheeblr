module API.Admin where

import Prelude

import API.Request as Request
import Data.Either (Either)
import Data.Maybe (Maybe)
import Effect.Aff (Aff)
import Services.AuthService (UserId)
import Types.Admin (AdminAction, AdminSnapshot, DomainEventPage, LogPage, Register, SessionInfo, TransactionPage)
import Types.Inventory (MutationResponse)
import Types.UUID (UUID)

getSnapshot :: UserId -> Aff (Either String AdminSnapshot)
getSnapshot userId = Request.authGet userId "/admin/snapshot"

getSessions :: UserId -> Aff (Either String (Array SessionInfo))
getSessions userId = Request.authGet userId "/admin/sessions"

revokeSession :: UserId -> UUID -> Aff (Either String Unit)
revokeSession userId sessionId =
  Request.authDeleteUnit userId ("/admin/sessions/" <> show sessionId)

getLogs
  :: UserId
  -> Maybe String  -- severity
  -> Maybe String  -- component
  -> Maybe String  -- traceId
  -> Maybe Int     -- limit
  -> Aff (Either String LogPage)
getLogs userId _ _ _ _ =
  Request.authGet userId "/admin/logs"

getTransactions
  :: UserId
  -> Maybe String  -- status filter
  -> Maybe Int     -- limit
  -> Aff (Either String TransactionPage)
getTransactions userId _ _ =
  Request.authGet userId "/admin/transactions"

getRegisters :: UserId -> Aff (Either String (Array Register))
getRegisters userId = Request.authGet userId "/admin/registers"

getDomainEvents
  :: UserId
  -> Maybe UUID    -- aggregateId
  -> Maybe String  -- traceId
  -> Aff (Either String DomainEventPage)
getDomainEvents userId _ _ =
  Request.authGet userId "/admin/domain-events"

performAction :: UserId -> AdminAction -> Aff (Either String MutationResponse)
performAction userId action =
  Request.authPost userId "/admin/actions" action

logStreamUrl :: String -> String -> String
logStreamUrl apiBase token =
  apiBase <> "/admin/logs/stream?authorization=" <> token

eventStreamUrl :: String -> String -> String
eventStreamUrl apiBase token =
  apiBase <> "/admin/events/stream?authorization=" <> token