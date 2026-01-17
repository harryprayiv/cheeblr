{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DeriveGeneric #-}
module API.Transaction where

import Data.UUID
import Servant
import Types.Transaction
import Data.Text
import Data.Aeson (ToJSON(..), FromJSON(..))
import Data.Time (UTCTime)
import GHC.Generics (Generic)

-- | Transaction API endpoints
type TransactionAPI =
  "transaction" :> Get '[JSON] [Transaction]
    :<|> "transaction" :> Capture "id" UUID :> Get '[JSON] Transaction
    :<|> "transaction" :> ReqBody '[JSON] Transaction :> Post '[JSON] Transaction
    :<|> "transaction" :> Capture "id" UUID :> ReqBody '[JSON] Transaction :> Put '[JSON] Transaction
    :<|> "transaction" :> "void" :> Capture "id" UUID :> ReqBody '[JSON] Text :> Post '[JSON] Transaction
    :<|> "transaction" :> "refund" :> Capture "id" UUID :> ReqBody '[JSON] Text :> Post '[JSON] Transaction
    :<|> "transaction" :> "item" :> ReqBody '[JSON] TransactionItem :> Post '[JSON] TransactionItem
    :<|> "transaction" :> "item" :> Capture "id" UUID :> Delete '[JSON] NoContent
    :<|> "transaction" :> "payment" :> ReqBody '[JSON] PaymentTransaction :> Post '[JSON] PaymentTransaction
    :<|> "transaction" :> "payment" :> Capture "id" UUID :> Delete '[JSON] NoContent
    :<|> "transaction" :> "finalize" :> Capture "id" UUID :> Post '[JSON] Transaction
    :<|> "transaction" :> "clear" :> Capture "id" UUID :> Post '[JSON] NoContent
    :<|> "inventory"   :> "available" :> Capture "sku" UUID :> Get '[JSON] AvailableInventory
    :<|> "inventory"   :> "reserve" :> ReqBody '[JSON] ReservationRequest :> Post '[JSON] InventoryReservation
    :<|> "inventory"   :> "release" :> Capture "id" UUID :> Delete '[JSON] NoContent

-- | Register API endpoints
type RegisterAPI =
  "register" :> Get '[JSON] [Register]
    :<|> "register" :> Capture "id" UUID :> Get '[JSON] Register
    :<|> "register" :> ReqBody '[JSON] Register :> Post '[JSON] Register
    :<|> "register" :> Capture "id" UUID :> ReqBody '[JSON] Register :> Put '[JSON] Register
    :<|> "register" :> "open" :> Capture "id" UUID :> ReqBody '[JSON] OpenRegisterRequest :> Post '[JSON] Register
    :<|> "register" :> "close" :> Capture "id" UUID :> ReqBody '[JSON] CloseRegisterRequest :> Post '[JSON] CloseRegisterResult

-- | Ledger API endpoints
type LedgerAPI =
  "ledger" :> "entry" :> Get '[JSON] [LedgerEntry]
    :<|> "ledger" :> "entry" :> Capture "id" UUID :> Get '[JSON] LedgerEntry
    :<|> "ledger" :> "account" :> Get '[JSON] [Account]
    :<|> "ledger" :> "account" :> Capture "id" UUID :> Get '[JSON] Account
    :<|> "ledger" :> "account" :> ReqBody '[JSON] Account :> Post '[JSON] Account
    :<|> "ledger" :> "report" :> "daily" :> ReqBody '[JSON] DailyReportRequest :> Post '[JSON] DailyReportResult

data AvailableInventory = AvailableInventory
  { availableTotal :: Int
  , availableReserved :: Int
  , availableActual :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON AvailableInventory
instance FromJSON AvailableInventory

data ReservationRequest = ReservationRequest
  { reserveItemSku :: UUID
  , reserveTransactionId :: UUID
  , reserveQuantity :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON ReservationRequest
instance FromJSON ReservationRequest

-- | Compliance API endpoints
type ComplianceAPI =
  "compliance" :> "verification" :> ReqBody '[JSON] CustomerVerification :> Post '[JSON] CustomerVerification
    :<|> "compliance" :> "record" :> Capture "transaction_id" UUID :> Get '[JSON] ComplianceRecord
    :<|> "compliance" :> "report" :> ReqBody '[JSON] ComplianceReportRequest :> Post '[JSON] ComplianceReportResult

-- | Combined API
type PosAPI =
  TransactionAPI
    :<|> RegisterAPI
    :<|> LedgerAPI
    :<|> ComplianceAPI

posAPI :: Proxy PosAPI
posAPI = Proxy

-- | Request/response types for register operations
data OpenRegisterRequest = OpenRegisterRequest
  { openRegisterEmployeeId :: UUID
  , openRegisterStartingCash :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON OpenRegisterRequest
instance FromJSON OpenRegisterRequest

data CloseRegisterRequest = CloseRegisterRequest
  { closeRegisterEmployeeId :: UUID
  , closeRegisterCountedCash :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON CloseRegisterRequest
instance FromJSON CloseRegisterRequest

data CloseRegisterResult = CloseRegisterResult
  { closeRegisterResultRegister :: Register
  , closeRegisterResultVariance :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON CloseRegisterResult
instance FromJSON CloseRegisterResult

-- | Request/response types for reports
data DailyReportRequest = DailyReportRequest
  { dailyReportDate :: UTCTime
  , dailyReportLocationId :: UUID
  } deriving (Show, Eq, Generic)

instance ToJSON DailyReportRequest
instance FromJSON DailyReportRequest

data DailyReportResult = DailyReportResult
  { dailyReportCash :: Int
  , dailyReportCard :: Int
  , dailyReportOther :: Int
  , dailyReportTotal :: Int
  , dailyReportTransactions :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON DailyReportResult
instance FromJSON DailyReportResult

data ComplianceReportRequest = ComplianceReportRequest
  { complianceReportStartDate :: UTCTime
  , complianceReportEndDate :: UTCTime
  , complianceReportLocationId :: UUID
  } deriving (Show, Eq, Generic)

instance ToJSON ComplianceReportRequest
instance FromJSON ComplianceReportRequest

newtype ComplianceReportResult = ComplianceReportResult
  { complianceReportContent :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON ComplianceReportResult
instance FromJSON ComplianceReportResult

-- | Register type
data Register = Register
  { registerId :: UUID
  , registerName :: Text
  , registerLocationId :: UUID
  , registerIsOpen :: Bool
  , registerCurrentDrawerAmount :: Int
  , registerExpectedDrawerAmount :: Int
  , registerOpenedAt :: Maybe UTCTime
  , registerOpenedBy :: Maybe UUID
  , registerLastTransactionTime :: Maybe UTCTime
  } deriving (Show, Eq, Generic)

instance ToJSON Register
instance FromJSON Register