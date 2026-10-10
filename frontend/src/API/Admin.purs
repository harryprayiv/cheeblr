module API.Admin where

import Prelude

import API.Request (ApiError)
import API.Request as Request
import Config.Network (currentConfig)
import Data.Either (Either)
import Effect.Aff (Aff)
import Types.Admin (AdminAction, AdminSnapshot, DomainEventPage, LogPage, Register, SessionInfo, TransactionPage)
import Types.Inventory (MutationResponse)
import Types.UUID (UUID)

getSnapshot :: Aff (Either ApiError AdminSnapshot)
getSnapshot = Request.get "/admin/snapshot"

getSessions :: Aff (Either ApiError (Array SessionInfo))
getSessions = Request.get "/admin/sessions"

revokeSession :: UUID -> Aff (Either ApiError Unit)
revokeSession sessionId =
  Request.deleteUnit ("/admin/sessions/" <> show sessionId)

getLogs :: Aff (Either ApiError LogPage)
getLogs = Request.get "/admin/logs"

getTransactions :: Aff (Either ApiError TransactionPage)
getTransactions = Request.get "/admin/transactions"

getRegisters :: Aff (Either ApiError (Array Register))
getRegisters = Request.get "/admin/registers"

getDomainEvents :: Aff (Either ApiError DomainEventPage)
getDomainEvents = Request.get "/admin/domain-events"

performAction :: AdminAction -> Aff (Either ApiError MutationResponse)
performAction action = Request.post "/admin/actions" action

-- The streams authenticate with the session cookie. Utils.SSE opens them
-- with credentials, so the URL carries no credential.

logStreamUrl :: String
logStreamUrl = currentConfig.apiBaseUrl <> "/admin/logs/stream"

eventStreamUrl :: String
eventStreamUrl = currentConfig.apiBaseUrl <> "/admin/events/stream"
