{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications  #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant return" #-}

module Server.Transaction where

import API.Transaction
import Auth.Session               (resolveSession)
import Control.Monad.IO.Class     (liftIO)
import Control.Monad              (void, when)
import Data.Text                  (Text, pack)
import qualified Data.Text        as T
import Data.UUID                  (UUID)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Effectful                  (Eff, IOE, runEff)
import Effectful.Error.Static     (Error, runErrorNoCallStack, throwError)
import Katip                      (LogEnv)
import Servant                    hiding (throwError)
import qualified Servant          as Servant (throwError)
import Types.Transaction

import DB.Database                (DBPool)
import Effect.Clock
import Effect.GenUUID
import Effect.RegisterDb
import Effect.TransactionDb
import Logging
import qualified Service.Register    as SvcReg
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
    requireAuth :: Maybe Text -> Handler ()
    requireAuth mHeader = void $ resolveSession pool mHeader

    getAllTransactionsHandler :: Maybe Text -> Handler [Transaction]
    getAllTransactionsHandler mHeader = do
      requireAuth mHeader
      liftIO $ logHttpRequest logEnv "GET" "/transaction" "system"
      runTxEff pool getAllTransactions

    getTransactionHandler :: Maybe Text -> UUID -> Handler Transaction
    getTransactionHandler mHeader txId = do
      requireAuth mHeader
      liftIO $ logHttpRequest logEnv "GET" ("/transaction/" <> showT txId) "system"
      runTxEff pool $ do
        maybeTx <- getTransactionById txId
        case maybeTx of
          Just tx -> pure tx
          Nothing -> throwError err404 { errBody = "Transaction not found" }

    createTransactionHandler :: Maybe Text -> Transaction -> Handler Transaction
    createTransactionHandler mHeader tx = do
      requireAuth mHeader
      let empId = transactionEmployeeId tx
          lctx  = empLogCtx logEnv empId
      liftIO $ logHttpRequest logEnv "POST" "/transaction" (showT empId)
      withComplianceLog (logTransactionCreate lctx (transactionId tx)) $
        runTxEff pool (createTransaction tx)

    updateTransactionHandler :: Maybe Text -> UUID -> Transaction -> Handler Transaction
    updateTransactionHandler mHeader txId tx = do
      requireAuth mHeader
      liftIO $ logHttpRequest logEnv "PUT" ("/transaction/" <> showT txId) "system"
      runTxEff pool (updateTransaction txId tx)

    voidTransactionHandler :: Maybe Text -> UUID -> Text -> Handler Transaction
    voidTransactionHandler mHeader txId reason = do
      requireAuth mHeader
      let lctx = LogCtx logEnv "system" "system"
      liftIO $ logHttpRequest logEnv "POST" ("/transaction/void/" <> showT txId) "system"
      withComplianceLog
        (\outcome -> logTransactionVoid lctx txId reason outcome) $
        runTxEff pool (SvcTx.voidTx txId reason)

    refundTransactionHandler :: Maybe Text -> UUID -> Text -> Handler Transaction
    refundTransactionHandler mHeader txId reason = do
      requireAuth mHeader
      let lctx = LogCtx logEnv "system" "system"
      liftIO $ logHttpRequest logEnv "POST" ("/transaction/refund/" <> showT txId) "system"
      withComplianceLog
        (\outcome -> logTransactionRefund lctx txId reason outcome) $
        runTxEff pool (SvcTx.refundTx txId reason)

    addTransactionItemHandler :: Maybe Text -> TransactionItem -> Handler TransactionItem
    addTransactionItemHandler mHeader item = do
      requireAuth mHeader
      let txId  = transactionItemTransactionId item
          skuId = transactionItemMenuItemSku item
          qty   = transactionItemQuantity item
      liftIO $ logHttpRequest logEnv "POST" "/transaction/item" "system"
      mEmpId <- runTxEff pool $ do
        mTx <- getTransactionById txId
        pure $ fmap (showT . transactionEmployeeId) mTx
      let lctx = case mEmpId of
            Just empIdT -> LogCtx logEnv empIdT "employee"
            Nothing     -> LogCtx logEnv "system" "system"
      withComplianceLog
        (\outcome -> logTransactionAddItem lctx txId skuId qty outcome) $
        runTxEff pool (SvcTx.addItem item)

    removeTransactionItemHandler :: Maybe Text -> UUID -> Handler NoContent
    removeTransactionItemHandler mHeader itemId = do
      requireAuth mHeader
      liftIO $ logHttpRequest logEnv "DELETE" ("/transaction/item/" <> showT itemId) "system"
      runTxEff pool (SvcTx.removeItem itemId) >> pure NoContent

    addPaymentTransactionHandler :: Maybe Text -> PaymentTransaction -> Handler PaymentTransaction
    addPaymentTransactionHandler mHeader payment = do
      requireAuth mHeader
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

    removePaymentTransactionHandler :: Maybe Text -> UUID -> Handler NoContent
    removePaymentTransactionHandler mHeader pymtId = do
      requireAuth mHeader
      liftIO $ logHttpRequest logEnv "DELETE" ("/transaction/payment/" <> showT pymtId) "system"
      runTxEff pool (SvcTx.removePayment pymtId) >> pure NoContent

    finalizeTransactionHandler :: Maybe Text -> UUID -> Handler Transaction
    finalizeTransactionHandler mHeader txId = do
      requireAuth mHeader
      liftIO $ logHttpRequest logEnv "POST" ("/transaction/finalize/" <> showT txId) "system"
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

    clearTransactionHandler :: Maybe Text -> UUID -> Handler NoContent
    clearTransactionHandler mHeader txId = do
      requireAuth mHeader
      liftIO $ logHttpRequest logEnv "POST" ("/transaction/clear/" <> showT txId) "system"
      mEmpId <- runTxEff pool $ do
        mTx <- getTransactionById txId
        pure $ fmap (showT . transactionEmployeeId) mTx
      let lctx = case mEmpId of
            Just empIdT -> LogCtx logEnv empIdT "employee"
            Nothing     -> LogCtx logEnv "system" "system"
      withComplianceLog (logTransactionClear lctx txId) $
        runTxEff pool (clearTransaction txId) >> pure NoContent

    getAvailableInventoryHandler :: Maybe Text -> UUID -> Handler AvailableInventory
    getAvailableInventoryHandler mHeader sku = do
      requireAuth mHeader
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

    reserveInventoryHandler :: Maybe Text -> ReservationRequest -> Handler InventoryReservation
    reserveInventoryHandler mHeader request = do
      requireAuth mHeader
      liftIO $ logHttpRequest logEnv "POST" "/inventory/reserve" "system"
      runTxEff pool $ do
        result <- getInventoryAvailability (reserveItemSku request)
        case result of
          Nothing -> throwError err404 { errBody = "Item not found" }
          Just (total, reserved) -> do
            let available = total - reserved
            when (available < reserveQuantity request) $
              throwError err400
                { errBody = stringToLBS $
                    "Insufficient inventory. Only " ++ show available ++ " available" }
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

    releaseInventoryHandler :: Maybe Text -> UUID -> Handler NoContent
    releaseInventoryHandler mHeader reservationId = do
      requireAuth mHeader
      liftIO $ logHttpRequest logEnv "DELETE" ("/inventory/release/" <> showT reservationId) "system"
      runTxEff pool $ do
        released <- releaseReservation reservationId
        if released
          then pure NoContent
          else throwError err404 { errBody = "Reservation not found or already released" }

registerServer :: DBPool -> LogEnv -> Server RegisterAPI
registerServer pool logEnv =
  getAllRegistersHandler
    :<|> getRegisterHandler
    :<|> createRegisterHandler
    :<|> updateRegisterHandler
    :<|> openRegisterHandler
    :<|> closeRegisterHandler
  where
    requireAuth :: Maybe Text -> Handler ()
    requireAuth mHeader = void $ resolveSession pool mHeader

    getAllRegistersHandler :: Maybe Text -> Handler [Register]
    getAllRegistersHandler mHeader = do
      requireAuth mHeader
      liftIO $ logHttpRequest logEnv "GET" "/register" "system"
      runRegEff pool getAllRegisters

    getRegisterHandler :: Maybe Text -> UUID -> Handler Register
    getRegisterHandler mHeader regId = do
      requireAuth mHeader
      liftIO $ logHttpRequest logEnv "GET" ("/register/" <> showT regId) "system"
      runRegEff pool $ do
        maybeReg <- getRegisterById regId
        case maybeReg of
          Just reg -> pure reg
          Nothing  -> throwError err404 { errBody = "Register not found" }

    createRegisterHandler :: Maybe Text -> Register -> Handler Register
    createRegisterHandler mHeader register = do
      requireAuth mHeader
      let lctx = LogCtx logEnv "system" "system"
      liftIO $ logHttpRequest logEnv "POST" "/register" "system"
      withComplianceLog
        (logRegisterCreate lctx (registerId register)) $
        runRegEff pool (createRegister register)

    updateRegisterHandler :: Maybe Text -> UUID -> Register -> Handler Register
    updateRegisterHandler mHeader regId register = do
      requireAuth mHeader
      liftIO $ logHttpRequest logEnv "PUT" ("/register/" <> showT regId) "system"
      runRegEff pool (updateRegister regId register)

    openRegisterHandler :: Maybe Text -> UUID -> OpenRegisterRequest -> Handler Register
    openRegisterHandler mHeader regId request = do
      requireAuth mHeader
      let empId     = openRegisterEmployeeId request
          startCash = openRegisterStartingCash request
          lctx      = empLogCtx logEnv empId
      liftIO $ logHttpRequest logEnv "POST" ("/register/open/" <> showT regId) (showT empId)
      withComplianceLog
        (\outcome -> logRegisterOpen lctx regId startCash outcome) $
        runRegEff pool (SvcReg.openRegister regId request)

    closeRegisterHandler :: Maybe Text -> UUID -> CloseRegisterRequest -> Handler CloseRegisterResult
    closeRegisterHandler mHeader regId request = do
      requireAuth mHeader
      let empId       = closeRegisterEmployeeId request
          countedCash = closeRegisterCountedCash request
          lctx        = empLogCtx logEnv empId
      liftIO $ logHttpRequest logEnv "POST" ("/register/close/" <> showT regId) (showT empId)
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

ledgerServer :: DBPool -> Server LedgerAPI
ledgerServer pool =
  getEntriesHandler
    :<|> getEntryHandler
    :<|> getAccountsHandler
    :<|> getAccountHandler
    :<|> createAccountHandler
    :<|> dailyReportHandler
  where
    requireAuth :: Maybe Text -> Handler ()
    requireAuth mHeader = void $ resolveSession pool mHeader

    getEntriesHandler :: Maybe Text -> Handler [LedgerEntry]
    getEntriesHandler mHeader = requireAuth mHeader >> pure []

    getEntryHandler :: Maybe Text -> UUID -> Handler LedgerEntry
    getEntryHandler mHeader _ =
      requireAuth mHeader >> Servant.throwError err501 { errBody = "Not implemented" }

    getAccountsHandler :: Maybe Text -> Handler [Account]
    getAccountsHandler mHeader = requireAuth mHeader >> pure []

    getAccountHandler :: Maybe Text -> UUID -> Handler Account
    getAccountHandler mHeader _ =
      requireAuth mHeader >> Servant.throwError err501 { errBody = "Not implemented" }

    createAccountHandler :: Maybe Text -> Account -> Handler Account
    createAccountHandler mHeader _ =
      requireAuth mHeader >> Servant.throwError err501 { errBody = "Not implemented" }

    dailyReportHandler :: Maybe Text -> DailyReportRequest -> Handler DailyReportResult
    dailyReportHandler mHeader _ =
      requireAuth mHeader >> pure (DailyReportResult 0 0 0 0 0)

complianceServer :: DBPool -> Server ComplianceAPI
complianceServer pool =
  verificationHandler
    :<|> getRecordHandler
    :<|> reportHandler
  where
    requireAuth :: Maybe Text -> Handler ()
    requireAuth mHeader = void $ resolveSession pool mHeader

    verificationHandler :: Maybe Text -> CustomerVerification -> Handler CustomerVerification
    verificationHandler mHeader v = requireAuth mHeader >> pure v

    getRecordHandler :: Maybe Text -> UUID -> Handler ComplianceRecord
    getRecordHandler mHeader _ =
      requireAuth mHeader >> Servant.throwError err501 { errBody = "Not implemented" }

    reportHandler :: Maybe Text -> ComplianceReportRequest -> Handler ComplianceReportResult
    reportHandler mHeader _ =
      requireAuth mHeader >> pure (ComplianceReportResult (pack "Not implemented"))

posServerImpl :: DBPool -> LogEnv -> Server PosAPI
posServerImpl pool logEnv =
  transactionServer pool logEnv
    :<|> registerServer  pool logEnv
    :<|> ledgerServer    pool
    :<|> complianceServer pool

showT :: Show a => a -> Text
showT = T.pack . show