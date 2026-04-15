{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Types.Admin (
  AdminSnapshot (..),
  InventorySummary (..),
  AvailabilitySummary (..),
  DbStats (..),
  BroadcasterStats (..),
  SessionInfo (..),
  TransactionDetail (..),
  AdminAction (..),
  LogPage (..),
  TransactionPage (..),
  DomainEventPage (..),
  DomainEventRow (..),
  ActivitySummary (..),
  ManagerAlert (..),
  OverrideRequest (..),
  TransactionSummary (..),
  LocationDayStats (..),
) where

import Data.Aeson (FromJSON, ToJSON, Value)
import Data.Int (Int64)
import Data.OpenApi (NamedSchema (..), ToSchema (..))
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)

import API.Transaction (Register)
import Config.App (Environment)
import Config.BuildInfo (BuildInfo)
import Types.Auth (UserRole)
import Types.Events.Log (LogEvent)
import Types.Transaction (Transaction, TransactionStatus)

data AdminSnapshot = AdminSnapshot
  { snapshotTime :: UTCTime
  , snapshotBuildInfo :: BuildInfo
  , snapshotEnvironment :: Environment
  , snapshotUptimeSeconds :: Int
  , snapshotActiveSessions :: [SessionInfo]
  , snapshotOpenRegisters :: [Register]
  , snapshotLiveTransactions :: [Transaction]
  , snapshotInventorySummary :: InventorySummary
  , snapshotAvailabilitySummary :: AvailabilitySummary
  , snapshotDbStats :: DbStats
  , snapshotBroadcasterStats :: BroadcasterStats
  }
  deriving (Generic)

instance ToJSON AdminSnapshot

-- Manual stub: BuildInfo, Environment, and Register lack ToSchema instances.
instance ToSchema AdminSnapshot where
  declareNamedSchema _ = return $ NamedSchema (Just "AdminSnapshot") mempty

data InventorySummary = InventorySummary
  { invItemCount :: Int
  , invTotalValue :: Int
  , invLowStockCount :: Int
  , invTotalReserved :: Int
  }
  deriving (Generic)

instance ToJSON InventorySummary
instance ToSchema InventorySummary

data AvailabilitySummary = AvailabilitySummary
  { avInStockCount :: Int
  , avOutOfStockCount :: Int
  , avTotalItems :: Int
  }
  deriving (Generic)

instance ToJSON AvailabilitySummary
instance ToSchema AvailabilitySummary

data DbStats = DbStats
  { dbPoolSize :: Int
  , dbPoolIdle :: Int
  , dbPoolInUse :: Int
  , dbQueryCount :: Int64
  , dbErrorCount :: Int64
  }
  deriving (Generic)

instance ToJSON DbStats
instance ToSchema DbStats

data BroadcasterStats = BroadcasterStats
  { bcLogDepth :: Int
  , bcDomainDepth :: Int
  , bcStockDepth :: Int
  , bcAvailabilityDepth :: Int
  , bcAvailabilitySeq :: Int64
  }
  deriving (Generic)

instance ToJSON BroadcasterStats
instance ToSchema BroadcasterStats

data SessionInfo = SessionInfo
  { siSessionId :: UUID
  , siUserId :: UUID
  , siRole :: UserRole
  , siCreatedAt :: UTCTime
  , siLastSeen :: UTCTime
  }
  deriving (Show, Eq, Generic)

instance ToJSON SessionInfo
instance FromJSON SessionInfo
instance ToSchema SessionInfo

data DomainEventRow = DomainEventRow
  { derSeq :: Int64
  , derId :: UUID
  , derType :: Text
  , derAggregateId :: UUID
  , derTraceId :: Maybe UUID
  , derActorId :: Maybe UUID
  , derLocationId :: Maybe UUID
  , derPayload :: Value
  , derOccurredAt :: UTCTime
  }
  deriving (Show, Eq, Generic)

instance ToJSON DomainEventRow
instance FromJSON DomainEventRow

-- Manual stub: aeson Value lacks a ToSchema instance.
instance ToSchema DomainEventRow where
  declareNamedSchema _ = return $ NamedSchema (Just "DomainEventRow") mempty

data TransactionDetail = TransactionDetail
  { tdTransaction :: Transaction
  , tdDomainEvents :: [DomainEventRow]
  }
  deriving (Generic)

instance ToJSON TransactionDetail
instance ToSchema TransactionDetail

data LogPage = LogPage
  { lpEntries :: [LogEvent]
  , lpNextCursor :: Maybe Int64
  , lpTotal :: Int
  }
  deriving (Show, Generic)

instance FromJSON LogPage
instance ToJSON LogPage

-- Manual stub: LogEvent contains a Value field so has no ToSchema.
instance ToSchema LogPage where
  declareNamedSchema _ = return $ NamedSchema (Just "LogPage") mempty

data TransactionPage = TransactionPage
  { tpTransactions :: [Transaction]
  , tpNextCursor :: Maybe UUID
  , tpTotal :: Int
  }
  deriving (Show, Generic)

instance ToJSON TransactionPage
instance FromJSON TransactionPage
instance ToSchema TransactionPage

data DomainEventPage = DomainEventPage
  { depEvents :: [DomainEventRow]
  , depNextCursor :: Maybe Int64
  , depTotal :: Int
  }
  deriving (Show, Generic)

instance ToJSON DomainEventPage
instance FromJSON DomainEventPage
instance ToSchema DomainEventPage

data AdminAction
  = RevokeSession UUID
  | ForceCloseRegister UUID Text
  | ClearRateLimitForIp Text
  | SetLowStockThreshold Int
  | TriggerSnapshotExport
  deriving (Show, Eq, Generic)

instance FromJSON AdminAction
instance ToJSON AdminAction
instance ToSchema AdminAction

data ActivitySummary = ActivitySummary
  { asSummaryTime :: UTCTime
  , asOpenRegisters :: [Register]
  , asLiveTransactions :: [TransactionSummary]
  , asTodayStats :: LocationDayStats
  , asAlerts :: [ManagerAlert]
  }
  deriving (Show, Generic)

instance ToJSON ActivitySummary

-- Manual stub: Register lacks a ToSchema instance.
instance ToSchema ActivitySummary where
  declareNamedSchema _ = return $ NamedSchema (Just "ActivitySummary") mempty

data TransactionSummary = TransactionSummary
  { tsId :: UUID
  , tsStatus :: TransactionStatus
  , tsCreated :: UTCTime
  , tsElapsedSecs :: Int
  , tsItemCount :: Int
  , tsTotal :: Int
  , tsIsStale :: Bool
  }
  deriving (Show, Eq, Generic)

instance ToJSON TransactionSummary
instance FromJSON TransactionSummary
instance ToSchema TransactionSummary

data LocationDayStats = LocationDayStats
  { ldsTxCount :: Int
  , ldsRevenue :: Int
  , ldsVoidCount :: Int
  , ldsRefundCount :: Int
  , ldsAvgTxValue :: Int
  }
  deriving (Show, Eq, Generic)

instance ToJSON LocationDayStats
instance FromJSON LocationDayStats
instance ToSchema LocationDayStats

data ManagerAlert
  = LowInventoryAlert UUID Text Int Int
  | StaleTransactionAlert UUID Int
  | RegisterVarianceAlert UUID Int
  deriving (Show, Eq, Generic)

instance ToJSON ManagerAlert
instance FromJSON ManagerAlert
instance ToSchema ManagerAlert

data OverrideRequest = OverrideRequest
  { orActorId :: UUID
  , orReason :: Text
  }
  deriving (Show, Eq, Generic)

instance ToJSON OverrideRequest
instance FromJSON OverrideRequest
instance ToSchema OverrideRequest
