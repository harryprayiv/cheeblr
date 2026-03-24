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
import Types.Transaction

type AuthHeader = Header "Authorization" Text

type TransactionAPI =
       "transaction" :> AuthHeader :> Get '[JSON] [Transaction]
  :<|> "transaction" :> AuthHeader :> Capture "id" UUID :> Get '[JSON] Transaction
  :<|> "transaction" :> AuthHeader :> ReqBody '[JSON] Transaction :> Post '[JSON] Transaction
  :<|> "transaction" :> AuthHeader :> Capture "id" UUID :> ReqBody '[JSON] Transaction :> Put '[JSON] Transaction
  :<|> "transaction" :> "void"     :> AuthHeader :> Capture "id" UUID :> ReqBody '[JSON] Text :> Post '[JSON] Transaction
  :<|> "transaction" :> "refund"   :> AuthHeader :> Capture "id" UUID :> ReqBody '[JSON] Text :> Post '[JSON] Transaction
  :<|> "transaction" :> "item"     :> AuthHeader :> ReqBody '[JSON] TransactionItem :> Post '[JSON] TransactionItem
  :<|> "transaction" :> "item"     :> AuthHeader :> Capture "id" UUID :> Delete '[JSON] NoContent
  :<|> "transaction" :> "payment"  :> AuthHeader :> ReqBody '[JSON] PaymentTransaction :> Post '[JSON] PaymentTransaction
  :<|> "transaction" :> "payment"  :> AuthHeader :> Capture "id" UUID :> Delete '[JSON] NoContent
  :<|> "transaction" :> "finalize" :> AuthHeader :> Capture "id" UUID :> Post '[JSON] Transaction
  :<|> "transaction" :> "clear"    :> AuthHeader :> Capture "id" UUID :> Post '[JSON] NoContent
  :<|> "inventory"   :> "available" :> AuthHeader :> Capture "sku" UUID :> Get '[JSON] AvailableInventory
  :<|> "inventory"   :> "reserve"   :> AuthHeader :> ReqBody '[JSON] ReservationRequest :> Post '[JSON] InventoryReservation
  :<|> "inventory"   :> "release"   :> AuthHeader :> Capture "id" UUID :> Delete '[JSON] NoContent

type RegisterAPI =
       "register" :> AuthHeader :> Get '[JSON] [Register]
  :<|> "register" :> AuthHeader :> Capture "id" UUID :> Get '[JSON] Register
  :<|> "register" :> AuthHeader :> ReqBody '[JSON] Register :> Post '[JSON] Register
  :<|> "register" :> AuthHeader :> Capture "id" UUID :> ReqBody '[JSON] Register :> Put '[JSON] Register
  :<|> "register" :> "open"  :> AuthHeader :> Capture "id" UUID :> ReqBody '[JSON] OpenRegisterRequest :> Post '[JSON] Register
  :<|> "register" :> "close" :> AuthHeader :> Capture "id" UUID :> ReqBody '[JSON] CloseRegisterRequest :> Post '[JSON] CloseRegisterResult

type LedgerAPI =
       "ledger" :> "entry"          :> AuthHeader :> Get '[JSON] [LedgerEntry]
  :<|> "ledger" :> "entry"          :> AuthHeader :> Capture "id" UUID :> Get '[JSON] LedgerEntry
  :<|> "ledger" :> "account"        :> AuthHeader :> Get '[JSON] [Account]
  :<|> "ledger" :> "account"        :> AuthHeader :> Capture "id" UUID :> Get '[JSON] Account
  :<|> "ledger" :> "account"        :> AuthHeader :> ReqBody '[JSON] Account :> Post '[JSON] Account
  :<|> "ledger" :> "report" :> "daily" :> AuthHeader :> ReqBody '[JSON] DailyReportRequest :> Post '[JSON] DailyReportResult

type ComplianceAPI =
       "compliance" :> "verification" :> AuthHeader :> ReqBody '[JSON] CustomerVerification :> Post '[JSON] CustomerVerification
  :<|> "compliance" :> "record"       :> AuthHeader :> Capture "transaction_id" UUID :> Get '[JSON] ComplianceRecord
  :<|> "compliance" :> "report"       :> AuthHeader :> ReqBody '[JSON] ComplianceReportRequest :> Post '[JSON] ComplianceReportResult

type PosAPI =
       TransactionAPI
  :<|> RegisterAPI
  :<|> LedgerAPI
  :<|> ComplianceAPI

posAPI :: Proxy PosAPI
posAPI = Proxy

data AvailableInventory = AvailableInventory
  { availableTotal    :: Int
  , availableReserved :: Int
  , availableActual   :: Int
  } deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data ReservationRequest = ReservationRequest
  { reserveItemSku       :: UUID
  , reserveTransactionId :: UUID
  , reserveQuantity      :: Int
  } deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data Register = Register
  { registerId                   :: UUID
  , registerName                 :: Text
  , registerLocationId           :: UUID
  , registerIsOpen               :: Bool
  , registerCurrentDrawerAmount  :: Int
  , registerExpectedDrawerAmount :: Int
  , registerOpenedAt             :: Maybe UTCTime
  , registerOpenedBy             :: Maybe UUID
  , registerLastTransactionTime  :: Maybe UTCTime
  } deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data OpenRegisterRequest = OpenRegisterRequest
  { openRegisterEmployeeId   :: UUID
  , openRegisterStartingCash :: Int
  } deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data CloseRegisterRequest = CloseRegisterRequest
  { closeRegisterEmployeeId  :: UUID
  , closeRegisterCountedCash :: Int
  } deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data CloseRegisterResult = CloseRegisterResult
  { closeRegisterResultRegister :: Register
  , closeRegisterResultVariance :: Int
  } deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data DailyReportRequest = DailyReportRequest
  { dailyReportDate       :: UTCTime
  , dailyReportLocationId :: UUID
  } deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data DailyReportResult = DailyReportResult
  { dailyReportCash         :: Int
  , dailyReportCard         :: Int
  , dailyReportOther        :: Int
  , dailyReportTotal        :: Int
  , dailyReportTransactions :: Int
  } deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data ComplianceReportRequest = ComplianceReportRequest
  { complianceReportStartDate  :: UTCTime
  , complianceReportEndDate    :: UTCTime
  , complianceReportLocationId :: UUID
  } deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

newtype ComplianceReportResult = ComplianceReportResult
  { complianceReportContent :: Text
  } deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)