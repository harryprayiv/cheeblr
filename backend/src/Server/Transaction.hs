{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications  #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant return" #-}

module Server.Transaction where

import API.Transaction
import Control.Monad.IO.Class (liftIO)
import Data.Text (Text, pack)
import qualified Data.Text as T
import Data.UUID (UUID)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Effectful (Eff, IOE, runEff)
import Effectful.Error.Static (Error, runErrorNoCallStack, throwError)
import Katip (LogEnv)
import Servant hiding (throwError)
import qualified Servant as Servant (throwError)
import Types.Transaction

import DB.Database (DBPool)
import Effect.Clock
import Effect.GenUUID
import Effect.RegisterDb
import Effect.TransactionDb
import Logging
import qualified Service.Register as SvcReg
import qualified Service.Transaction as SvcTx

type TxEffs =
  '[ GenUUID
   , Clock
   , TransactionDb
   , Error ServerError
   , IOE
   ]

type RegEffs =
  '[ GenUUID
   , Clock
   , RegisterDb
   , Error ServerError
   , IOE
   ]

runTxEff :: DBPool -> Eff TxEffs a -> Handler a
runTxEff pool action = do
  result <-
    liftIO
      . runEff
      . runErrorNoCallStack @ServerError
      . runTransactionDbIO pool
      . runClockIO
      . runGenUUIDIO
      $ action
  either Servant.throwError pure result

runRegEff :: DBPool -> Eff RegEffs a -> Handler a
runRegEff pool action = do
  result <-
    liftIO
      . runEff
      . runErrorNoCallStack @ServerError
      . runRegisterDbIO pool
      . runClockIO
      . runGenUUIDIO
      $ action
  either Servant.throwError pure result

-- | Run a Handler and fire the compliance log callback on both success and
-- failure.  On failure the error is re-thrown unchanged so the HTTP response
-- is unaffected; the compliance file gets a failure entry with the HTTP status
-- code recorded in the outcome field.
withComplianceLog
  :: (LogOutcome -> IO ())
  -> Handler a
  -> Handler a
withComplianceLog logIt action = do
  result <- liftIO (runHandler action)
  case result of
    Right val -> do
      liftIO $ logIt LogSuccess
      pure val
    Left err -> do
      liftIO $ logIt (LogFailure (T.pack (show (errHTTPCode err))))
      Servant.throwError err

stringToLBS :: String -> LBS.ByteString
stringToLBS = LBS.pack

-- ─────────────────────────────────────────────────────────────────────────────

transactionServer :: DBPool -> LogEnv -> Server TransactionAPI
transactionServer pool logEnv =
  getAllTransactionsHandler
    :<|> getTransactionHandler
    :<|> createTransactionHandler
    :<|> updateTransactionHandler
    :<|> voidTransactionHandler
    :<|> refundTransactionHandler
    :<|> addTransactionItemHandler
    :<|> removeTransactionItemHandler
    :<|> addPaymentTransactionHandler
    :<|> removePaymentTransactionHandler
    :<|> finalizeTransactionHandler
    :<|> clearTransactionHandler
    :<|> getAvailableInventoryHandler
    :<|> reserveInventoryHandler
    :<|> releaseInventoryHandler
  where
    -- ── Read-only ────────────────────────────────────────────────────────────

    getAllTransactionsHandler :: Handler [Transaction]
    getAllTransactionsHandler = do
      liftIO $ logHttpRequest logEnv "GET" "/transaction" "system"
      runTxEff pool getAllTransactions

    getTransactionHandler :: UUID -> Handler Transaction
    getTransactionHandler txId = do
      liftIO $ logHttpRequest logEnv "GET" ("/transaction/" <> showT txId) "system"
      runTxEff pool $ do
        maybeTx <- getTransactionById txId
        case maybeTx of
          Just tx -> pure tx
          Nothing -> throwError err404 { errBody = "Transaction not found" }

    -- ── Lifecycle ─────────────────────────────────────────────────────────────

    createTransactionHandler :: Transaction -> Handler Transaction
    createTransactionHandler tx = do
      let empId = transactionEmployeeId tx
          lctx  = empLogCtx logEnv empId
      liftIO $ logHttpRequest logEnv "POST" "/transaction" (showT empId)
      withComplianceLog (logTransactionCreate lctx (transactionId tx)) $
        runTxEff pool (createTransaction tx)

    updateTransactionHandler :: UUID -> Transaction -> Handler Transaction
    updateTransactionHandler txId tx = do
      liftIO $ logHttpRequest logEnv "PUT" ("/transaction/" <> showT txId) "system"
      runTxEff pool (updateTransaction txId tx)

    voidTransactionHandler :: UUID -> Text -> Handler Transaction
    voidTransactionHandler txId reason = do
      let lctx = LogCtx logEnv "system" "system"
      liftIO $ logHttpRequest logEnv "POST" ("/transaction/void/" <> showT txId) "system"
      withComplianceLog
        (\outcome -> logTransactionVoid lctx txId reason outcome) $
        runTxEff pool (SvcTx.voidTx txId reason)

    refundTransactionHandler :: UUID -> Text -> Handler Transaction
    refundTransactionHandler txId reason = do
      let lctx = LogCtx logEnv "system" "system"
      liftIO $ logHttpRequest logEnv "POST" ("/transaction/refund/" <> showT txId) "system"
      withComplianceLog
        (\outcome -> logTransactionRefund lctx txId reason outcome) $
        runTxEff pool (SvcTx.refundTx txId reason)

    finalizeTransactionHandler :: UUID -> Handler Transaction
    finalizeTransactionHandler txId = do
      liftIO $ logHttpRequest logEnv "POST" ("/transaction/finalize/" <> showT txId) "system"
      -- withComplianceLog catches any failure and records it.  On success we
      -- have the real totals so we emit a second richer compliance entry;
      -- the placeholder 0/0 entry from withComplianceLog is suppressed by
      -- only firing it on failure (we handle success ourselves below).
      result <- liftIO (runHandler (runTxEff pool (SvcTx.finalizeTx txId)))
      case result of
        Left err -> do
          liftIO $ logTransactionFinalize
            (LogCtx logEnv "system" "system") txId 0 0
            (LogFailure (T.pack (show (errHTTPCode err))))
          Servant.throwError err
        Right tx -> do
          liftIO $ logTransactionFinalize
            (empLogCtx logEnv (transactionEmployeeId tx))
            txId
            (transactionTotal tx)
            (length (transactionItems tx))
            LogSuccess
          pure tx

    clearTransactionHandler :: UUID -> Handler NoContent
    clearTransactionHandler txId = do
      liftIO $ logHttpRequest logEnv "POST" ("/transaction/clear/" <> showT txId) "system"
      mEmpId <- runTxEff pool $ do
        mTx <- getTransactionById txId
        pure $ fmap (showT . transactionEmployeeId) mTx
      let lctx = case mEmpId of
            Just empIdT -> LogCtx logEnv empIdT "employee"
            Nothing     -> LogCtx logEnv "system" "system"
      withComplianceLog (logTransactionClear lctx txId) $
        runTxEff pool (clearTransaction txId) >> pure NoContent

    -- ── Items ─────────────────────────────────────────────────────────────────

    addTransactionItemHandler :: TransactionItem -> Handler TransactionItem
    addTransactionItemHandler item = do
      let txId  = transactionItemTransactionId item
          skuId = transactionItemMenuItemSku item
          qty   = transactionItemQuantity item
      liftIO $ logHttpRequest logEnv "POST" "/transaction/item" "system"
      -- Fetch the parent transaction so we can log the actual employee ID.
      -- This is a cheap indexed lookup and worth it for compliance accuracy.
      mEmpId <- runTxEff pool $ do
        mTx <- getTransactionById txId
        pure $ fmap (showT . transactionEmployeeId) mTx
      let lctx = case mEmpId of
            Just empIdT -> LogCtx logEnv empIdT "employee"
            Nothing     -> LogCtx logEnv "system" "system"
      withComplianceLog
        (\outcome -> logTransactionAddItem lctx txId skuId qty outcome) $
        runTxEff pool (SvcTx.addItem item)

    removeTransactionItemHandler :: UUID -> Handler NoContent
    removeTransactionItemHandler itemId = do
      liftIO $ logHttpRequest logEnv "DELETE" ("/transaction/item/" <> showT itemId) "system"
      runTxEff pool (SvcTx.removeItem itemId) >> pure NoContent

    -- ── Payments ──────────────────────────────────────────────────────────────

    addPaymentTransactionHandler :: PaymentTransaction -> Handler PaymentTransaction
    addPaymentTransactionHandler payment = do
      let txId   = paymentTransactionId payment
          amt    = paymentAmount payment
          method = T.pack (show (paymentMethod payment))
      liftIO $ logHttpRequest logEnv "POST" "/transaction/payment" "system"
      mEmpId <- runTxEff pool $ do
        mTx <- getTransactionById txId
        pure $ fmap (showT . transactionEmployeeId) mTx
      let lctx = case mEmpId of
            Just empIdT -> LogCtx logEnv empIdT "employee"
            Nothing     -> LogCtx logEnv "system" "system"
      withComplianceLog
        (\outcome -> logTransactionAddPayment lctx txId amt method outcome) $
        runTxEff pool (SvcTx.addPayment payment)

    removePaymentTransactionHandler :: UUID -> Handler NoContent
    removePaymentTransactionHandler pymtId = do
      liftIO $ logHttpRequest logEnv "DELETE" ("/transaction/payment/" <> showT pymtId) "system"
      runTxEff pool (SvcTx.removePayment pymtId) >> pure NoContent

    -- ── Inventory reservation ─────────────────────────────────────────────────

    getAvailableInventoryHandler :: UUID -> Handler AvailableInventory
    getAvailableInventoryHandler sku = do
      liftIO $ logHttpRequest logEnv "GET" ("/inventory/available/" <> showT sku) "system"
      runTxEff pool $ do
        result <- getInventoryAvailability sku
        case result of
          Nothing -> throwError err404 { errBody = "Item not found" }
          Just (total, reserved) ->
            pure AvailableInventory
              { availableTotal    = total
              , availableReserved = reserved
              , availableActual   = total - reserved
              }

    reserveInventoryHandler :: ReservationRequest -> Handler InventoryReservation
    reserveInventoryHandler request = do
      liftIO $ logHttpRequest logEnv "POST" "/inventory/reserve" "system"
      runTxEff pool $ do
        result <- getInventoryAvailability (reserveItemSku request)
        case result of
          Nothing -> throwError err404 { errBody = "Item not found" }
          Just (total, reserved) -> do
            let available = total - reserved
            if available < reserveQuantity request
              then throwError err400
                     { errBody = stringToLBS $
                         "Insufficient inventory. Only " ++ show available ++ " available" }
              else do
                reservationId <- nextUUID
                now           <- currentTime
                createReservation
                  reservationId
                  (reserveItemSku request)
                  (reserveTransactionId request)
                  (reserveQuantity request)
                  now
                pure InventoryReservation
                  { reservationItemSku       = reserveItemSku request
                  , reservationTransactionId = reserveTransactionId request
                  , reservationQuantity      = reserveQuantity request
                  , reservationStatus        = "Reserved"
                  }

    releaseInventoryHandler :: UUID -> Handler NoContent
    releaseInventoryHandler reservationId = do
      liftIO $ logHttpRequest logEnv "DELETE" ("/inventory/release/" <> showT reservationId) "system"
      runTxEff pool $ do
        released <- releaseReservation reservationId
        if released
          then pure NoContent
          else throwError err404 { errBody = "Reservation not found or already released" }

-- ─────────────────────────────────────────────────────────────────────────────

registerServer :: DBPool -> LogEnv -> Server RegisterAPI
registerServer pool logEnv =
  getAllRegistersHandler
    :<|> getRegisterHandler
    :<|> createRegisterHandler
    :<|> updateRegisterHandler
    :<|> openRegisterHandler
    :<|> closeRegisterHandler
  where
    getAllRegistersHandler :: Handler [Register]
    getAllRegistersHandler = do
      liftIO $ logHttpRequest logEnv "GET" "/register" "system"
      runRegEff pool getAllRegisters

    getRegisterHandler :: UUID -> Handler Register
    getRegisterHandler regId = do
      liftIO $ logHttpRequest logEnv "GET" ("/register/" <> showT regId) "system"
      runRegEff pool $ do
        maybeReg <- getRegisterById regId
        case maybeReg of
          Just reg -> pure reg
          Nothing  -> throwError err404 { errBody = "Register not found" }

    createRegisterHandler :: Register -> Handler Register
    createRegisterHandler register = do
      let lctx = LogCtx logEnv "system" "system"
      liftIO $ logHttpRequest logEnv "POST" "/register" "system"
      withComplianceLog
        (logRegisterCreate lctx (registerId register)) $
        runRegEff pool (createRegister register)

    updateRegisterHandler :: UUID -> Register -> Handler Register
    updateRegisterHandler regId register = do
      liftIO $ logHttpRequest logEnv "PUT" ("/register/" <> showT regId) "system"
      runRegEff pool (updateRegister regId register)

    openRegisterHandler :: UUID -> OpenRegisterRequest -> Handler Register
    openRegisterHandler regId request = do
      let empId     = openRegisterEmployeeId request
          startCash = openRegisterStartingCash request
          lctx      = empLogCtx logEnv empId
      liftIO $ logHttpRequest logEnv "POST" ("/register/open/" <> showT regId) (showT empId)
      withComplianceLog
        (\outcome -> logRegisterOpen lctx regId startCash outcome) $
        runRegEff pool (SvcReg.openRegister regId request)

    closeRegisterHandler :: UUID -> CloseRegisterRequest -> Handler CloseRegisterResult
    closeRegisterHandler regId request = do
      let empId       = closeRegisterEmployeeId request
          countedCash = closeRegisterCountedCash request
          lctx        = empLogCtx logEnv empId
      liftIO $ logHttpRequest logEnv "POST" ("/register/close/" <> showT regId) (showT empId)
      -- Same pattern as finalize: handle both branches explicitly so the
      -- success path carries the real variance rather than a placeholder 0.
      result <- liftIO (runHandler (runRegEff pool (SvcReg.closeRegister regId request)))
      case result of
        Left err -> do
          liftIO $ logRegisterClose lctx regId countedCash 0
            (LogFailure (T.pack (show (errHTTPCode err))))
          Servant.throwError err
        Right closeResult -> do
          liftIO $ logRegisterClose lctx regId countedCash
            (closeRegisterResultVariance closeResult)
            LogSuccess
          pure closeResult

-- ─────────────────────────────────────────────────────────────────────────────

ledgerServer :: DBPool -> Server LedgerAPI
ledgerServer _ =
  getEntriesHandler
    :<|> getEntryHandler
    :<|> getAccountsHandler
    :<|> getAccountHandler
    :<|> createAccountHandler
    :<|> dailyReportHandler
  where
    getEntriesHandler :: Handler [LedgerEntry]
    getEntriesHandler = pure []

    getEntryHandler :: UUID -> Handler LedgerEntry
    getEntryHandler _ = Servant.throwError err501 { errBody = "Not implemented" }

    getAccountsHandler :: Handler [Account]
    getAccountsHandler = pure []

    getAccountHandler :: UUID -> Handler Account
    getAccountHandler _ = Servant.throwError err501 { errBody = "Not implemented" }

    createAccountHandler :: Account -> Handler Account
    createAccountHandler _ = Servant.throwError err501 { errBody = "Not implemented" }

    dailyReportHandler :: DailyReportRequest -> Handler DailyReportResult
    dailyReportHandler _ = pure $ DailyReportResult 0 0 0 0 0

complianceServer :: DBPool -> Server ComplianceAPI
complianceServer _ =
  verificationHandler
    :<|> getRecordHandler
    :<|> reportHandler
  where
    verificationHandler :: CustomerVerification -> Handler CustomerVerification
    verificationHandler v = pure v

    getRecordHandler :: UUID -> Handler ComplianceRecord
    getRecordHandler _ = Servant.throwError err501 { errBody = "Not implemented" }

    reportHandler :: ComplianceReportRequest -> Handler ComplianceReportResult
    reportHandler _ = pure $ ComplianceReportResult (pack "Not implemented")

posServerImpl :: DBPool -> LogEnv -> Server PosAPI
posServerImpl pool logEnv =
  transactionServer pool logEnv
    :<|> registerServer  pool logEnv
    :<|> ledgerServer    pool
    :<|> complianceServer pool

-- ─── Helpers ─────────────────────────────────────────────────────────────────

showT :: Show a => a -> Text
showT = T.pack . show