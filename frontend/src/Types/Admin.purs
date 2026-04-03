module Types.Admin where

import Prelude

import Data.DateTime (DateTime)
import Data.Maybe (Maybe)
import Foreign (ForeignError(..), fail)
import Foreign.Index (readProp)
import Types.Auth (UserCapabilities, UserRole)
import Types.Transaction (Transaction)
import Types.UUID (UUID)
import Yoga.JSON (class ReadForeign, class WriteForeign, readImpl, writeImpl)

type BuildInfo =
  { biGitSha    :: String
  , biBuildTime :: String
  , biVersion   :: String
  }

type InventorySummary =
  { invItemCount     :: Int
  , invTotalValue    :: Int
  , invLowStockCount :: Int
  , invTotalReserved :: Int
  }

type AvailabilitySummary =
  { avInStockCount    :: Int
  , avOutOfStockCount :: Int
  , avTotalItems      :: Int
  }

type DbStats =
  { dbPoolSize   :: Int
  , dbPoolIdle   :: Int
  , dbPoolInUse  :: Int
  , dbQueryCount :: Number
  , dbErrorCount :: Number
  }

type BroadcasterStats =
  { bcLogDepth          :: Int
  , bcDomainDepth       :: Int
  , bcStockDepth        :: Int
  , bcAvailabilityDepth :: Int
  , bcAvailabilitySeq   :: Number
  }

type SessionInfo =
  { siSessionId :: UUID
  , siUserId    :: UUID
  , siRole      :: UserRole
  , siCreatedAt :: DateTime
  , siLastSeen  :: DateTime
  }

type Register =
  { registerId                  :: UUID
  , registerName                :: String
  , registerLocationId          :: UUID
  , registerIsOpen              :: Boolean
  , registerCurrentDrawerAmount :: Int
  , registerExpectedDrawerAmount :: Int
  }

type AdminSnapshot =
  { snapshotTime                :: DateTime
  , snapshotEnvironment         :: String
  , snapshotUptimeSeconds       :: Int
  , snapshotActiveSessions      :: Array SessionInfo
  , snapshotOpenRegisters       :: Array Register
  , snapshotInventorySummary    :: InventorySummary
  , snapshotAvailabilitySummary :: AvailabilitySummary
  , snapshotDbStats             :: DbStats
  , snapshotBroadcasterStats    :: BroadcasterStats
  }

type LogEvent =
  { leTimestamp :: DateTime
  , leComponent :: String
  , leSeverity  :: String
  , leMessage   :: String
  , leTraceId   :: Maybe String
  }

type LogPage =
  { lpEntries    :: Array LogEvent
  , lpNextCursor :: Maybe Number
  , lpTotal      :: Int
  }

type DomainEventRow =
  { derSeq         :: Number
  , derId          :: UUID
  , derType        :: String
  , derAggregateId :: UUID
  , derTraceId     :: Maybe UUID
  , derActorId     :: Maybe UUID
  , derOccurredAt  :: DateTime
  }

type DomainEventPage =
  { depEvents     :: Array DomainEventRow
  , depNextCursor :: Maybe Number
  , depTotal      :: Int
  }

type TransactionPage =
  { tpTransactions :: Array Transaction
  , tpNextCursor   :: Maybe UUID
  , tpTotal        :: Int
  }

data AdminAction
  = RevokeSession       UUID
  | ForceCloseRegister  UUID String
  | ClearRateLimitForIp String
  | SetLowStockThreshold Int
  | TriggerSnapshotExport

instance WriteForeign AdminAction where
  writeImpl (RevokeSession uid) =
    writeImpl { tag: "RevokeSession", contents: show uid }
  writeImpl (ForceCloseRegister uid reason) =
    writeImpl { tag: "ForceCloseRegister", contents: [show uid, reason] }
  writeImpl (ClearRateLimitForIp ip) =
    writeImpl { tag: "ClearRateLimitForIp", contents: ip }
  writeImpl (SetLowStockThreshold n) =
    writeImpl { tag: "SetLowStockThreshold", contents: n }
  writeImpl TriggerSnapshotExport =
    writeImpl { tag: "TriggerSnapshotExport" :: String }