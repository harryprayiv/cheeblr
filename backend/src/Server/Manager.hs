{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Server.Manager (
  managerServerImpl,
  toTransactionSummary,
  buildDayStats,
  isManagerEvent,
) where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.Int (Int64)
import Data.Text (Text)
import Data.Time (
  UTCTime,
  diffUTCTime,
  getCurrentTime,
  utctDay,
 )
import Data.UUID (UUID)
import qualified Data.Vector as V
import Network.HTTP.Types.Status (status401, status403)
import Network.Wai (responseLBS)
import Servant

import API.Manager
import API.Transaction (
  ComplianceReportRequest,
  ComplianceReportResult (..),
  DailyReportRequest (..),
  DailyReportResult (..),
  Register (..),
 )
import Auth.Session (SessionContext (..), resolveSession)
import Config.App (
  cfgLowStockThreshold,
  cfgStaleTransactionSecs,
 )
import qualified DB.Register as DBR
import qualified DB.Transaction as DBT
import Infrastructure.SSE (filteredSseStream)
import Server.Env (AppEnv (..))
import Server.Transaction (runTxEff)
import qualified Service.Transaction as SvcTx

import DB.Database (getAllMenuItems)
import Types.Admin (
  ActivitySummary (..),
  LocationDayStats (..),
  ManagerAlert (..),
  OverrideRequest (..),
  TransactionSummary (..),
 )
import Types.Auth (
  AuthenticatedUser (..),
  capCanApplyDiscount,
  capCanViewReports,
  capCanVoidTransaction,
  capabilitiesForRole,
 )
import Types.Events.Domain (DomainEvent (..))
import Types.Inventory (Inventory (..), MutationResponse (..))
import qualified Types.Inventory as TI
import Types.Transaction (
  Transaction (..),
  TransactionStatus (..),
  TransactionType (Return),
 )

authCtx :: AppEnv -> Maybe Text -> Handler SessionContext
authCtx env = resolveSession (envDbPool env)

requireManager :: SessionContext -> Handler ()
requireManager ctx =
  unless (capCanViewReports (capabilitiesForRole (auRole (scUser ctx)))) $
    throwError err403 {errBody = LBS.pack "Forbidden: manager access required"}

isManagerEvent :: DomainEvent -> Bool
isManagerEvent (TransactionEvt _) = True
isManagerEvent (RegisterEvt _)    = True
isManagerEvent _                  = False

toTransactionSummary :: Int -> UTCTime -> Transaction -> TransactionSummary
toTransactionSummary staleSecs now tx =
  let elapsedSecs = round (diffUTCTime now (transactionCreated tx)) :: Int
   in TransactionSummary
        { tsId          = transactionId tx
        , tsStatus      = transactionStatus tx
        , tsCreated     = transactionCreated tx
        , tsElapsedSecs = elapsedSecs
        , tsItemCount   = length (transactionItems tx)
        , tsTotal       = transactionTotal tx
        , tsIsStale     = elapsedSecs > staleSecs
        }

buildAlerts :: AppEnv -> [Transaction] -> [Register] -> Inventory -> IO [ManagerAlert]
buildAlerts env txs registers (Inventory invitems) = do
  now <- getCurrentTime
  let
    threshold = cfgLowStockThreshold (envConfig env)
    staleSecs = cfgStaleTransactionSecs (envConfig env)

  let lowStockAlerts =
        [ LowInventoryAlert (TI.sku i) (TI.name i) (TI.quantity i) threshold
        | i <- V.toList invitems
        , TI.quantity i > 0
        , TI.quantity i <= threshold
        ]

  let staleAlerts =
        [ StaleTransactionAlert (transactionId tx) elapsed
        | tx <- txs
        , transactionStatus tx `elem` [Created, InProgress]
        , let elapsed = round (diffUTCTime now (transactionCreated tx)) :: Int
        , elapsed > staleSecs
        ]

  let varianceAlerts =
        [ RegisterVarianceAlert (registerId r) variance
        | r <- registers
        , not (registerIsOpen r)
        , let variance = registerExpectedDrawerAmount r - registerCurrentDrawerAmount r
        , abs variance > 500
        ]

  pure (lowStockAlerts <> staleAlerts <> varianceAlerts)

-- | The figures for the day @now@ falls on, in UTC, from every transaction
-- created on that day.
--
-- A refund is stored as its own row of type 'Return' with negated amounts,
-- and the sale it refunds has status 'Refunded'. So the rows are split by
-- type:
--
-- * A sale counts when its status is 'Completed' or 'Refunded'. A refunded
--   sale did take place, and the money it took is cancelled by its return
--   row, not by leaving the sale out.
-- * A return counts when its status is 'Completed'.
--
-- Revenue is the sale totals plus the return totals. The return totals are
-- negative, so a sale refunded on the same day adds nothing to revenue. A
-- sale refunded on a later day keeps its revenue on the day of the sale
-- and the return lowers the revenue of the day of the refund.
--
-- The transaction count is the number of sales. A return row is not
-- counted as a transaction. The average is revenue divided by that count.
--
-- A voided sale has status 'Voided' and is in neither list.
buildDayStats :: [Transaction] -> UTCTime -> LocationDayStats
buildDayStats allTxs now =
  let
    today     = utctDay now
    todayTxs  = filter (\tx -> utctDay (transactionCreated tx) == today) allTxs
    isReturn tx = transactionType tx == Return
    sales     =
      filter
        (\tx -> not (isReturn tx) && transactionStatus tx `elem` [Completed, Refunded])
        todayTxs
    returns   =
      filter
        (\tx -> isReturn tx && transactionStatus tx == Completed)
        todayTxs
    voided    = filter transactionIsVoided todayTxs
    refunded  = filter (\tx -> not (isReturn tx) && transactionIsRefunded tx) todayTxs
    revenue   = sum (map transactionTotal sales) + sum (map transactionTotal returns)
    count     = length sales
    avg       = if count == 0 then 0 else revenue `div` count
   in
    LocationDayStats
      { ldsTxCount     = count
      , ldsRevenue     = revenue
      , ldsVoidCount   = length voided
      , ldsRefundCount = length refunded
      , ldsAvgTxValue  = avg
      }

activityHandler :: AppEnv -> Maybe Text -> Handler ActivitySummary
activityHandler env mHeader = do
  ctx       <- authCtx env mHeader
  requireManager ctx
  now       <- liftIO getCurrentTime
  txs       <- liftIO $ DBT.getAllTransactions (envDbPool env)
  registers <- liftIO $ DBR.getAllRegisters (envDbPool env)
  inventory <- liftIO $ getAllMenuItems (envDbPool env)

  let
    staleSecs = cfgStaleTransactionSecs (envConfig env)
    openRegs  = filter registerIsOpen registers
    liveTxs   = filter (\tx -> transactionStatus tx `elem` [Created, InProgress]) txs
    summaries = map (toTransactionSummary staleSecs now) liveTxs
    dayStats  = buildDayStats txs now

  alerts <- liftIO $ buildAlerts env txs registers inventory

  pure
    ActivitySummary
      { asSummaryTime      = now
      , asOpenRegisters    = openRegs
      , asLiveTransactions = summaries
      , asTodayStats       = dayStats
      , asAlerts           = alerts
      }

activityStreamHandler ::
  AppEnv -> Maybe Text -> Maybe Int64 -> Tagged Handler Application
activityStreamHandler env mHeader mCursor = Tagged $ \req sendResp -> do
  result <- runHandler (authCtx env mHeader)
  case result of
    Left err -> sendResp $ responseLBS status401 [] (errBody err)
    Right ctx ->
      if capCanViewReports (capabilitiesForRole (auRole (scUser ctx)))
        then
          filteredSseStream
            isManagerEvent
            (envDomainBroadcaster env)
            mCursor
            req
            sendResp
        else sendResp $ responseLBS status403 [] "Forbidden"

alertsHandler :: AppEnv -> Maybe Text -> Handler [ManagerAlert]
alertsHandler env mHeader = do
  ctx       <- authCtx env mHeader
  requireManager ctx
  txs       <- liftIO $ DBT.getAllTransactions (envDbPool env)
  registers <- liftIO $ DBR.getAllRegisters (envDbPool env)
  inventory <- liftIO $ getAllMenuItems (envDbPool env)
  liftIO $ buildAlerts env txs registers inventory

dailyReportHandler ::
  AppEnv -> Maybe Text -> DailyReportRequest -> Handler DailyReportResult
dailyReportHandler env mHeader _req = do
  ctx <- authCtx env mHeader
  requireManager ctx
  txs <- liftIO $ DBT.getAllTransactions (envDbPool env)
  now <- liftIO getCurrentTime
  let stats = buildDayStats txs now
  pure
    DailyReportResult
      { dailyReportCash         = ldsTxCount stats * ldsAvgTxValue stats `div` 2
      , dailyReportCard         = ldsTxCount stats * ldsAvgTxValue stats `div` 2
      , dailyReportOther        = 0
      , dailyReportTotal        = ldsRevenue stats
      , dailyReportTransactions = ldsTxCount stats
      }

complianceReportHandler ::
  AppEnv -> Maybe Text -> ComplianceReportRequest -> Handler ComplianceReportResult
complianceReportHandler env mHeader _req = do
  ctx <- authCtx env mHeader
  requireManager ctx
  pure (ComplianceReportResult "Compliance report generation not yet implemented")

-- | A manager's void goes through the same service as the void on the sale
-- routes. The sale state machine decides whether the sale can be voided,
-- the reservations are released, the pending stock pulls are cancelled and
-- the void event is emitted. A missing sale is a 404 and a sale that cannot
-- be voided is a 409.
overrideVoidHandler ::
  AppEnv -> UUID -> Maybe Text -> OverrideRequest -> Handler MutationResponse
overrideVoidHandler env txId mHeader req = do
  ctx <- authCtx env mHeader
  unless (capCanVoidTransaction (capabilitiesForRole (auRole (scUser ctx)))) $
    throwError err403 {errBody = LBS.pack "Forbidden: void transaction required"}
  _ <- runTxEff env (SvcTx.voidTx txId (orReason req))
  pure $ MutationResponse True ("Transaction voided: " <> orReason req)

overrideDiscountHandler ::
  AppEnv -> UUID -> Maybe Text -> OverrideRequest -> Handler MutationResponse
overrideDiscountHandler env _txId mHeader _req = do
  ctx <- authCtx env mHeader
  unless (capCanApplyDiscount (capabilitiesForRole (auRole (scUser ctx)))) $
    throwError err403 {errBody = LBS.pack "Forbidden: apply discount required"}
  pure $ MutationResponse False "Override discounts not yet implemented"

managerServerImpl :: AppEnv -> Server ManagerAPI
managerServerImpl env =
  activityHandler env
    :<|> activityStreamHandler env
    :<|> alertsHandler env
    :<|> dailyReportHandler env
    :<|> complianceReportHandler env
    :<|> overrideVoidHandler env
    :<|> overrideDiscountHandler env