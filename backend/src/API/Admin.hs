{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module API.Admin where

import Data.Int (Int64)
import Data.Text (Text)
import Data.UUID (UUID)
import Servant

import API.Transaction (Register)
import Types.Admin
import Types.Inventory (MutationResponse)
import Types.Transaction (TransactionStatus)

type AuthHeader = Header "Authorization" Text

type AdminAPI =
  "admin"
    :> ( "snapshot"
           :> AuthHeader
           :> Get '[JSON] AdminSnapshot
           :<|> "sessions"
             :> AuthHeader
             :> Get '[JSON] [SessionInfo]
           :<|> "sessions"
             :> Capture "sessionId" UUID
             :> AuthHeader
             :> DeleteNoContent
           :<|> "logs"
             :> AuthHeader
             :> QueryParam "severity" Text
             :> QueryParam "component" Text
             :> QueryParam "traceId" Text
             :> QueryParam "limit" Int
             :> QueryParam "cursor" Int64
             :> Get '[JSON] LogPage
           :<|> "logs"
             :> "stream"
             :> AuthHeader
             :> QueryParam "cursor" Int64
             :> Raw
           :<|> "events"
             :> "stream"
             :> AuthHeader
             :> QueryParam "cursor" Int64
             :> Raw
           :<|> "transactions"
             :> AuthHeader
             :> QueryParam "status" TransactionStatus
             :> QueryParam "limit" Int
             :> Get '[JSON] TransactionPage
           :<|> "transactions"
             :> Capture "txId" UUID
             :> AuthHeader
             :> Get '[JSON] TransactionDetail
           :<|> "registers"
             :> AuthHeader
             :> Get '[JSON] [Register]
           :<|> "domain-events"
             :> AuthHeader
             :> QueryParam "aggregateId" UUID
             :> QueryParam "traceId" Text
             :> QueryParam "cursor" Int64
             :> QueryParam "limit" Int
             :> Get '[JSON] DomainEventPage
           :<|> "actions"
             :> AuthHeader
             :> ReqBody '[JSON] AdminAction
             :> Post '[JSON] MutationResponse
       )

adminAPI :: Proxy AdminAPI
adminAPI = Proxy
