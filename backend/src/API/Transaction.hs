{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeOperators #-}

module API.Transaction where

import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.OpenApi (ToSchema)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import Servant

import Types.Location
import Types.Transaction
import qualified Types.Transaction.Refund as Refund
import qualified Types.Transaction.Sale as Sale

type AuthHeader = Header "Authorization" Text

type SaleAPI =
  "sale" :> AuthHeader :> Get '[JSON] [Sale.SaleTransaction]
    :<|> "sale" :> AuthHeader :> Capture "id" UUID :> Get '[JSON] Sale.SaleTransaction
    :<|> "sale" :> "void" :> AuthHeader :> Capture "id" UUID :> ReqBody '[JSON] Text :> Post '[JSON] Sale.SaleTransaction
    :<|> "sale" :> "refund" :> AuthHeader :> Capture "id" UUID :> ReqBody '[JSON] Text :> Post '[JSON] Refund.RefundTransaction

type RefundAPI =
  "refund" :> AuthHeader :> Get '[JSON] [Refund.RefundTransaction]
    :<|> "refund" :> AuthHeader :> Capture "id" UUID :> Get '[JSON] Refund.RefundTransaction

type ReservationAPI =
  "inventory" :> "available" :> AuthHeader :> Capture "sku" UUID :> Get '[JSON] AvailableInventory

type RegisterAPI =
  "register" :> AuthHeader :> Get '[JSON] [Register]
    :<|> "register" :> AuthHeader :> Capture "id" UUID :> Get '[JSON] Register
    :<|> "register" :> AuthHeader :> ReqBody '[JSON] Register :> Post '[JSON] Register
    :<|> "register" :> AuthHeader :> Capture "id" UUID :> ReqBody '[JSON] Register :> Put '[JSON] Register
    :<|> "register" :> "open" :> AuthHeader :> Capture "id" UUID :> ReqBody '[JSON] OpenRegisterRequest :> Post '[JSON] Register
    :<|> "register" :> "close" :> AuthHeader :> Capture "id" UUID :> ReqBody '[JSON] CloseRegisterRequest :> Post '[JSON] CloseRegisterResult

type LedgerAPI =
  "ledger" :> "entry" :> AuthHeader :> Get '[JSON] [LedgerEntry]
    :<|> "ledger" :> "entry" :> AuthHeader :> Capture "id" UUID :> Get '[JSON] LedgerEntry
    :<|> "ledger" :> "account" :> AuthHeader :> Get '[JSON] [Account]
    :<|> "ledger" :> "account" :> AuthHeader :> Capture "id" UUID :> Get '[JSON] Account
    :<|> "ledger" :> "account" :> AuthHeader :> ReqBody '[JSON] Account :> Post '[JSON] Account
    :<|> "ledger" :> "report" :> "daily" :> AuthHeader :> ReqBody '[JSON] DailyReportRequest :> Post '[JSON] DailyReportResult

type ComplianceAPI =
  "compliance" :> "verification" :> AuthHeader :> ReqBody '[JSON] CustomerVerification :> Post '[JSON] CustomerVerification
    :<|> "compliance" :> "record" :> AuthHeader :> Capture "transaction_id" UUID :> Get '[JSON] ComplianceRecord
    :<|> "compliance" :> "report" :> AuthHeader :> ReqBody '[JSON] ComplianceReportRequest :> Post '[JSON] ComplianceReportResult

type PosAPI =
  SaleAPI
    :<|> RefundAPI
    :<|> ReservationAPI
    :<|> RegisterAPI
    :<|> LedgerAPI
    :<|> ComplianceAPI

posAPI :: Proxy PosAPI
posAPI = Proxy

data AvailableInventory = AvailableInventory
  { availableTotal :: Int
  , availableReserved :: Int
  , availableActual :: Int
  }
  deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data Register = Register
  { registerId :: UUID
  , registerName :: Text
  , registerLocationId :: LocationId
  , registerIsOpen :: Bool
  , registerCurrentDrawerAmount :: Int
  , registerExpectedDrawerAmount :: Int
  , registerOpenedAt :: Maybe UTCTime
  , registerOpenedBy :: Maybe UUID
  , registerLastTransactionTime :: Maybe UTCTime
  }
  deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

-- The employee who opens or closes a register is the session user. Neither
-- request names one.
data OpenRegisterRequest = OpenRegisterRequest
  { openRegisterStartingCash :: Int
  }
  deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data CloseRegisterRequest = CloseRegisterRequest
  { closeRegisterCountedCash :: Int
  }
  deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data CloseRegisterResult = CloseRegisterResult
  { closeRegisterResultRegister :: Register
  , closeRegisterResultVariance :: Int
  }
  deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data DailyReportRequest = DailyReportRequest
  { dailyReportDate :: UTCTime
  , dailyReportLocationId :: UUID
  }
  deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data DailyReportResult = DailyReportResult
  { dailyReportCash :: Int
  , dailyReportCard :: Int
  , dailyReportOther :: Int
  , dailyReportTotal :: Int
  , dailyReportTransactions :: Int
  }
  deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data ComplianceReportRequest = ComplianceReportRequest
  { complianceReportStartDate :: UTCTime
  , complianceReportEndDate :: UTCTime
  , complianceReportLocationId :: UUID
  }
  deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

newtype ComplianceReportResult = ComplianceReportResult
  { complianceReportContent :: Text
  }
  deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)
