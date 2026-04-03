{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module API.Manager where

import Data.Int (Int64)
import Data.Text (Text)
import Data.UUID (UUID)
import Servant

import API.Transaction (
  ComplianceReportRequest,
  ComplianceReportResult,
  DailyReportRequest,
  DailyReportResult,
 )
import Types.Admin (ActivitySummary, ManagerAlert, OverrideRequest)
import Types.Inventory (MutationResponse)

type AuthHeader = Header "Authorization" Text

type ManagerAPI =
  "manager"
    :> ( "activity"
           :> AuthHeader
           :> Get '[JSON] ActivitySummary
           :<|> "activity"
             :> "stream"
             :> AuthHeader
             :> QueryParam "cursor" Int64
             :> Raw
           :<|> "alerts"
             :> AuthHeader
             :> Get '[JSON] [ManagerAlert]
           :<|> "reports"
             :> "daily"
             :> AuthHeader
             :> ReqBody '[JSON] DailyReportRequest
             :> Post '[JSON] DailyReportResult
           :<|> "reports"
             :> "compliance"
             :> AuthHeader
             :> ReqBody '[JSON] ComplianceReportRequest
             :> Post '[JSON] ComplianceReportResult
           :<|> "override"
             :> "void"
             :> Capture "txId" UUID
             :> AuthHeader
             :> ReqBody '[JSON] OverrideRequest
             :> Post '[JSON] MutationResponse
           :<|> "override"
             :> "discount"
             :> Capture "txId" UUID
             :> AuthHeader
             :> ReqBody '[JSON] OverrideRequest
             :> Post '[JSON] MutationResponse
       )

managerAPI :: Proxy ManagerAPI
managerAPI = Proxy
