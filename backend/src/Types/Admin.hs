{-# LANGUAGE DeriveGeneric     #-}

module Types.Admin
  ( AdminSnapshot (..)
  , InventorySummary (..)
  , AvailabilitySummary (..)
  , DbStats (..)
  , BroadcasterStats (..)
  , SessionInfo (..)
  , TransactionDetail (..)
  , AdminAction (..)
  , LogPage (..)
  , TransactionPage (..)
  , DomainEventPage (..)
  , DomainEventRow (..)
  ) where

import Data.Aeson   (FromJSON, ToJSON, Value)
import Data.Int     (Int64)
import Data.Text    (Text)
import Data.Time    (UTCTime)
import Data.UUID    (UUID)
import GHC.Generics (Generic)

import Config.App        (Environment)
import Config.BuildInfo  (BuildInfo)
import Types.Auth        (UserRole)
import Types.Events.Log  (LogEvent)
import Types.Transaction (Transaction)
import API.Transaction   (Register)

data AdminSnapshot = AdminSnapshot
  { snapshotTime                :: UTCTime
  , snapshotBuildInfo           :: BuildInfo
  , snapshotEnvironment         :: Environment
  , snapshotUptimeSeconds       :: Int
  , snapshotActiveSessions      :: [SessionInfo]
  , snapshotOpenRegisters       :: [Register]
  , snapshotLiveTransactions    :: [Transaction]
  , snapshotInventorySummary    :: InventorySummary
  , snapshotAvailabilitySummary :: AvailabilitySummary
  , snapshotDbStats             :: DbStats
  , snapshotBroadcasterStats    :: BroadcasterStats
  } deriving (Generic)

instance ToJSON AdminSnapshot

data InventorySummary = InventorySummary
  { invItemCount     :: Int
  , invTotalValue    :: Int
  , invLowStockCount :: Int
  , invTotalReserved :: Int
  } deriving (Generic)

instance ToJSON InventorySummary

data AvailabilitySummary = AvailabilitySummary
  { avInStockCount    :: Int
  , avOutOfStockCount :: Int
  , avTotalItems      :: Int
  } deriving (Generic)

instance ToJSON AvailabilitySummary

data DbStats = DbStats
  { dbPoolSize   :: Int
  , dbPoolIdle   :: Int
  , dbPoolInUse  :: Int
  , dbQueryCount :: Int64
  , dbErrorCount :: Int64
  } deriving (Generic)

instance ToJSON DbStats

data BroadcasterStats = BroadcasterStats
  { bcLogDepth          :: Int
  , bcDomainDepth       :: Int
  , bcStockDepth        :: Int
  , bcAvailabilityDepth :: Int
  , bcAvailabilitySeq   :: Int64
  } deriving (Generic)

instance ToJSON BroadcasterStats

data SessionInfo = SessionInfo
  { siSessionId :: UUID
  , siUserId    :: UUID
  , siRole      :: UserRole
  , siCreatedAt :: UTCTime
  , siLastSeen  :: UTCTime
  } deriving (Show, Eq, Generic)

instance ToJSON   SessionInfo
instance FromJSON SessionInfo

data DomainEventRow = DomainEventRow
  { derSeq         :: Int64
  , derId          :: UUID
  , derType        :: Text
  , derAggregateId :: UUID
  , derTraceId     :: Maybe UUID
  , derActorId     :: Maybe UUID
  , derLocationId  :: Maybe UUID
  , derPayload     :: Value
  , derOccurredAt  :: UTCTime
  } deriving (Show, Eq, Generic)

instance ToJSON   DomainEventRow
instance FromJSON DomainEventRow

data TransactionDetail = TransactionDetail
  { tdTransaction  :: Transaction
  , tdDomainEvents :: [DomainEventRow]
  } deriving (Generic)

instance ToJSON TransactionDetail

data LogPage = LogPage
  { lpEntries    :: [LogEvent]
  , lpNextCursor :: Maybe Int64
  , lpTotal      :: Int
  } deriving (Show, Generic)

instance FromJSON LogPage
instance ToJSON LogPage

data TransactionPage = TransactionPage
  { tpTransactions :: [Transaction]
  , tpNextCursor   :: Maybe UUID
  , tpTotal        :: Int
  } deriving (Show, Generic)

instance ToJSON TransactionPage
instance FromJSON TransactionPage

data DomainEventPage = DomainEventPage
  { depEvents     :: [DomainEventRow]
  , depNextCursor :: Maybe Int64
  , depTotal      :: Int
  } deriving (Show, Generic)

instance ToJSON DomainEventPage
instance FromJSON DomainEventPage

data AdminAction
  = RevokeSession       UUID
  | ForceCloseRegister  UUID Text
  | ClearRateLimitForIp Text
  | SetLowStockThreshold Int
  | TriggerSnapshotExport
  deriving (Show, Eq, Generic)

instance FromJSON AdminAction
instance ToJSON   AdminAction