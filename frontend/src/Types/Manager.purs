module Types.Manager where

import Prelude

import Data.DateTime (DateTime)
import Data.Maybe (Maybe)
import Types.UUID (UUID)
import Types.Transaction (TransactionStatus)
import Types.Register (Register)

type TransactionSummary =
  { tsId          :: UUID
  , tsStatus      :: TransactionStatus
  , tsCreated     :: DateTime
  , tsElapsedSecs :: Int
  , tsItemCount   :: Int
  , tsTotal       :: Int
  , tsIsStale     :: Boolean
  }

type LocationDayStats =
  { ldsTxCount     :: Int
  , ldsRevenue     :: Int
  , ldsVoidCount   :: Int
  , ldsRefundCount :: Int
  , ldsAvgTxValue  :: Int
  }

data ManagerAlert
  = LowInventoryAlert     UUID String Int Int
  | StaleTransactionAlert UUID Int
  | RegisterVarianceAlert UUID Int

type ActivitySummary =
  { asSummaryTime      :: DateTime
  , asOpenRegisters    :: Array Register
  , asLiveTransactions :: Array TransactionSummary
  , asTodayStats       :: LocationDayStats
  , asAlerts           :: Array ManagerAlertRaw
  }

-- Raw record for JSON parsing since ADT needs custom instance
type ManagerAlertRaw =
  { tag      :: String
  , id       :: Maybe UUID
  , name     :: Maybe String
  , quantity :: Maybe Int
  , elapsed  :: Maybe Int
  , variance :: Maybe Int
  }

type DailyReportResult =
  { dailyReportCash         :: Int
  , dailyReportCard         :: Int
  , dailyReportOther        :: Int
  , dailyReportTotal        :: Int
  , dailyReportTransactions :: Int
  }