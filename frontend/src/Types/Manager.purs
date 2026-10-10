module Types.Manager where

import Prelude

import Data.DateTime (DateTime)
import Foreign (Foreign, ForeignError(..), fail)
import Types.Register (Register)
import Types.Transaction (TransactionStatus)
import Types.UUID (UUID)
import Yoga.JSON (class ReadForeign, readImpl)

type TransactionSummary =
  { tsId :: UUID
  , tsStatus :: TransactionStatus
  , tsCreated :: DateTime
  , tsElapsedSecs :: Int
  , tsItemCount :: Int
  , tsTotal :: Int
  , tsIsStale :: Boolean
  }

-- Backend Server.Manager.buildDayStats, for the UTC day: ldsTxCount counts
-- sales whose status is Completed or Refunded; ldsRevenue is net of returns;
-- ldsVoidCount counts sales flagged voided; ldsRefundCount counts sales
-- flagged refunded; ldsAvgTxValue is net revenue divided by the sale count.

type LocationDayStats =
  { ldsTxCount :: Int
  , ldsRevenue :: Int
  , ldsVoidCount :: Int
  , ldsRefundCount :: Int
  , ldsAvgTxValue :: Int
  }

-- The backend type is a sum with positional fields and a generic Aeson
-- instance, so an alert arrives as {"tag": <constructor>, "contents": [...]}.
--   LowInventoryAlert      sku, item name, quantity on hand, threshold
--   StaleTransactionAlert  sale id, seconds since the sale was created
--   RegisterVarianceAlert  register id, expected minus counted, in cents

data ManagerAlert
  = LowInventoryAlert
      { sku :: UUID, name :: String, quantity :: Int, threshold :: Int }
  | StaleTransactionAlert { saleId :: UUID, elapsedSecs :: Int }
  | RegisterVarianceAlert { registerId :: UUID, variance :: Int }

derive instance eqManagerAlert :: Eq ManagerAlert

instance showManagerAlert :: Show ManagerAlert where
  show (LowInventoryAlert r) = "LowInventoryAlert " <> show r
  show (StaleTransactionAlert r) = "StaleTransactionAlert " <> show r
  show (RegisterVarianceAlert r) = "RegisterVarianceAlert " <> show r

-- Decoding is strict. An unknown tag or a contents array of the wrong
-- length fails the whole response.
instance readForeignManagerAlert :: ReadForeign ManagerAlert where
  readImpl f = do
    alert :: { tag :: String, contents :: Array Foreign } <- readImpl f
    case alert.tag, alert.contents of
      "LowInventoryAlert", [ a, b, c, d ] -> do
        sku <- readImpl a
        name <- readImpl b
        quantity <- readImpl c
        threshold <- readImpl d
        pure (LowInventoryAlert { sku, name, quantity, threshold })
      "StaleTransactionAlert", [ a, b ] -> do
        saleId <- readImpl a
        elapsedSecs <- readImpl b
        pure (StaleTransactionAlert { saleId, elapsedSecs })
      "RegisterVarianceAlert", [ a, b ] -> do
        registerId <- readImpl a
        variance <- readImpl b
        pure (RegisterVarianceAlert { registerId, variance })
      tag, _ ->
        fail (ForeignError ("Unreadable ManagerAlert with tag " <> tag))

type ActivitySummary =
  { asSummaryTime :: DateTime
  , asOpenRegisters :: Array Register
  , asLiveTransactions :: Array TransactionSummary
  , asTodayStats :: LocationDayStats
  , asAlerts :: Array ManagerAlert
  }

-- The backend reads neither field yet, but it decodes the body, so both
-- must be well formed: an ISO 8601 time and a UUID.
type DailyReportRequest =
  { dailyReportDate :: DateTime
  , dailyReportLocationId :: UUID
  }

-- Only dailyReportTotal and dailyReportTransactions come from sales. The
-- backend does not compute the cash and card figures from payments.
type DailyReportResult =
  { dailyReportCash :: Int
  , dailyReportCard :: Int
  , dailyReportOther :: Int
  , dailyReportTotal :: Int
  , dailyReportTransactions :: Int
  }
