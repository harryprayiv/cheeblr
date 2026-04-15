{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Redundant return" #-}

module Server.Transaction where

import API.Transaction
import Auth.Session (SessionContext (..), resolveSession)
import Control.Monad (void, when)
import Control.Monad.Error.Class (catchError)
import Control.Monad.IO.Class (liftIO)
import Data.Text (Text, pack)
import qualified Data.Text as T

import qualified Data.ByteString.Lazy.Char8 as LBS
import Effectful (Eff, IOE, runEff)
import Effectful.Error.Static (Error, runErrorNoCallStack, throwError)
import Servant hiding (throwError)
import qualified Servant (throwError)
import Types.Transaction

import Data.UUID (UUID)
import Effect.Clock
import Effect.EventEmitter
import Effect.GenUUID
import Effect.InventoryDb (InventoryDb, runInventoryDbIO)
import Effect.RegisterDb
import Effect.StockDb (StockDb, runStockDbIO)
import Effect.TransactionDb
import Logging
import Server.Env (AppEnv (..))
import qualified Service.Register as SvcReg
import qualified Service.Transaction as SvcTx
import Types.Auth (AuthenticatedUser (..), auRole, auUserId)

type TxEffs =
  '[ GenUUID
   , Clock
   , TransactionDb
   , StockDb
   , InventoryDb
   , EventEmitter
   , Error ServerError
   , IOE
   ]

type RegEffs =
  '[ GenUUID
   , Clock
   , RegisterDb
   , EventEmitter
   , Error ServerError
   , IOE
   ]

runTxEff :: AppEnv -> Eff TxEffs a -> Handler a
runTxEff env action = do
  result <-
    liftIO
      . runEff
      . runErrorNoCallStack @ServerError
      . runEventEmitterProd
        (envDbPool env)
        (envDomainBroadcaster env)
        Nothing
        Nothing
        Nothing
      . runInventoryDbIO (envDbPool env)
      . runStockDbIO (envDbPool env)
      . runTransactionDbIO (envDbPool env)
      . runClockIO
      . runGenUUIDIO
      $ action
  either Servant.throwError pure result

runRegEff :: AppEnv -> Eff RegEffs a -> Handler a
runRegEff env action = do
  result <-
    liftIO
      . runEff
      . runErrorNoCallStack @ServerError
      . runEventEmitterProd
        (envDbPool env)
        (envDomainBroadcaster env)
        Nothing
        Nothing
        Nothing
      . runRegisterDbIO (envDbPool env)
      . runClockIO
      . runGenUUIDIO
      $ action
  either Servant.throwError pure result

{- | Resolve the session and return the context so handlers can use the real
user ID in logs instead of the former "system" placeholder.
-}
requireAuth :: AppEnv -> Maybe Text -> Handler SessionContext
requireAuth env mHeader = resolveSession (envDbPool env) mHeader

{- | Log the compliance outcome for an action.
Previously used `liftIO (runHandler action)` which re-ran the action in a
fresh Handler context. Now uses `catchError` so the Handler monad is
threaded correctly throughout.
-}
withComplianceLog ::
  (LogOutcome -> IO ()) ->
  Handler a ->
  Handler a
withComplianceLog logIt action = do
  val <-
    action `catchError` \err -> do
      liftIO $ logIt (LogFailure (T.pack (show (errHTTPCode err))))
      Servant.throwError err
  liftIO $ logIt LogSuccess
  pure val

showT :: (Show a) => a -> Text
showT = T.pack . show

transactionServer :: AppEnv -> Server TransactionAPI
transactionServer env =
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
    logEnv = envLogEnv env

    getAllTransactionsHandler :: Maybe Text -> Handler [Transaction]
    getAllTransactionsHandler mHeader = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "GET" "/transaction" (showT (auUserId (scUser ctx)))
      runTxEff env getAllTransactions

    getTransactionHandler :: Maybe Text -> UUID -> Handler Transaction
    getTransactionHandler mHeader txId = do
      ctx <- requireAuth env mHeader
      liftIO $
        logHttpRequest
          logEnv
          "GET"
          ("/transaction/" <> showT txId)
          (showT (auUserId (scUser ctx)))
      runTxEff env $ do
        maybeTx <- getTransactionById txId
        case maybeTx of
          Just tx -> pure tx
          Nothing -> throwError err404 {errBody = "Transaction not found"}

    createTransactionHandler :: Maybe Text -> Transaction -> Handler Transaction
    createTransactionHandler mHeader tx = do
      ctx <- requireAuth env mHeader
      let
        -- Use the employee ID embedded in the transaction for compliance logs
        -- (may differ from session user in manager-override scenarios).
        empId = transactionEmployeeId tx
        lctx = empLogCtx logEnv empId
      liftIO $
        logHttpRequest
          logEnv
          "POST"
          "/transaction"
          (showT (auUserId (scUser ctx)))
      withComplianceLog (logTransactionCreate lctx (transactionId tx)) $
        runTxEff env (SvcTx.createTransactionSvc tx)

    updateTransactionHandler :: Maybe Text -> UUID -> Transaction -> Handler Transaction
    updateTransactionHandler mHeader txId tx = do
      ctx <- requireAuth env mHeader
      liftIO $
        logHttpRequest
          logEnv
          "PUT"
          ("/transaction/" <> showT txId)
          (showT (auUserId (scUser ctx)))
      runTxEff env (updateTransaction txId tx)

    voidTransactionHandler :: Maybe Text -> UUID -> Text -> Handler Transaction
    voidTransactionHandler mHeader txId reason = do
      ctx <- requireAuth env mHeader
      let lctx =
            makeLogCtx
              logEnv
              (Just (showT (auUserId (scUser ctx))))
              (auRole (scUser ctx))
      liftIO $
        logHttpRequest
          logEnv
          "POST"
          ("/transaction/void/" <> showT txId)
          (showT (auUserId (scUser ctx)))
      withComplianceLog
        (\outcome -> logTransactionVoid lctx txId reason outcome)
        $ runTxEff env (SvcTx.voidTx txId reason)

    refundTransactionHandler :: Maybe Text -> UUID -> Text -> Handler Transaction
    refundTransactionHandler mHeader txId reason = do
      ctx <- requireAuth env mHeader
      let lctx =
            makeLogCtx
              logEnv
              (Just (showT (auUserId (scUser ctx))))
              (auRole (scUser ctx))
      liftIO $
        logHttpRequest
          logEnv
          "POST"
          ("/transaction/refund/" <> showT txId)
          (showT (auUserId (scUser ctx)))
      withComplianceLog
        (\outcome -> logTransactionRefund lctx txId reason outcome)
        $ runTxEff env (SvcTx.refundTx txId reason)

    addTransactionItemHandler :: Maybe Text -> TransactionItem -> Handler TransactionItem
    addTransactionItemHandler mHeader item = do
      ctx <- requireAuth env mHeader
      let
        txId = transactionItemTransactionId item
        skuId = transactionItemMenuItemSku item
        qty = transactionItemQuantity item
      liftIO $
        logHttpRequest
          logEnv
          "POST"
          "/transaction/item"
          (showT (auUserId (scUser ctx)))
      -- Fetch the transaction to get the employee ID for the compliance log.
      mEmpId <-
        runTxEff env $
          fmap
            (fmap (showT . transactionEmployeeId))
            (getTransactionById txId)
      let lctx = case mEmpId of
            Just eid -> LogCtx logEnv eid "employee"
            Nothing ->
              makeLogCtx
                logEnv
                (Just (showT (auUserId (scUser ctx))))
                (auRole (scUser ctx))
      withComplianceLog
        (\outcome -> logTransactionAddItem lctx txId skuId qty outcome)
        $ runTxEff env (SvcTx.addItem item)

    removeTransactionItemHandler :: Maybe Text -> UUID -> Handler NoContent
    removeTransactionItemHandler mHeader itemId = do
      ctx <- requireAuth env mHeader
      liftIO $
        logHttpRequest
          logEnv
          "DELETE"
          ("/transaction/item/" <> showT itemId)
          (showT (auUserId (scUser ctx)))
      runTxEff env (SvcTx.removeItem itemId) >> pure NoContent

    addPaymentTransactionHandler :: Maybe Text -> PaymentTransaction -> Handler PaymentTransaction
    addPaymentTransactionHandler mHeader payment = do
      ctx <- requireAuth env mHeader
      let
        txId = paymentTransactionId payment
        amt = paymentAmount payment
        method = T.pack (show (paymentMethod payment))
      liftIO $
        logHttpRequest
          logEnv
          "POST"
          "/transaction/payment"
          (showT (auUserId (scUser ctx)))
      mEmpId <-
        runTxEff env $
          fmap
            (fmap (showT . transactionEmployeeId))
            (getTransactionById txId)
      let lctx = case mEmpId of
            Just eid -> LogCtx logEnv eid "employee"
            Nothing ->
              makeLogCtx
                logEnv
                (Just (showT (auUserId (scUser ctx))))
                (auRole (scUser ctx))
      withComplianceLog
        (\outcome -> logTransactionAddPayment lctx txId amt method outcome)
        $ runTxEff env (SvcTx.addPayment payment)

    removePaymentTransactionHandler :: Maybe Text -> UUID -> Handler NoContent
    removePaymentTransactionHandler mHeader pymtId = do
      ctx <- requireAuth env mHeader
      liftIO $
        logHttpRequest
          logEnv
          "DELETE"
          ("/transaction/payment/" <> showT pymtId)
          (showT (auUserId (scUser ctx)))
      runTxEff env (SvcTx.removePayment pymtId) >> pure NoContent

    finalizeTransactionHandler :: Maybe Text -> UUID -> Handler Transaction
    finalizeTransactionHandler mHeader txId = do
      ctx <- requireAuth env mHeader
      liftIO $
        logHttpRequest
          logEnv
          "POST"
          ("/transaction/finalize/" <> showT txId)
          (showT (auUserId (scUser ctx)))
      withComplianceLog
        ( \outcome -> do
            -- On success the tx is available; on failure we still log with the
            -- session user rather than crashing.
            logTransactionFinalize
              ( makeLogCtx
                  logEnv
                  (Just (showT (auUserId (scUser ctx))))
                  (auRole (scUser ctx))
              )
              txId
              0
              0
              outcome
        )
        $ do
          tx <- runTxEff env (SvcTx.finalizeTx txId)
          -- Re-log with actual totals now that we have the result.
          liftIO $
            logTransactionFinalize
              (empLogCtx logEnv (transactionEmployeeId tx))
              txId
              (transactionTotal tx)
              (length (transactionItems tx))
              LogSuccess
          pure tx

    clearTransactionHandler :: Maybe Text -> UUID -> Handler NoContent
    clearTransactionHandler mHeader txId = do
      ctx <- requireAuth env mHeader
      liftIO $
        logHttpRequest
          logEnv
          "POST"
          ("/transaction/clear/" <> showT txId)
          (showT (auUserId (scUser ctx)))
      let lctx =
            makeLogCtx
              logEnv
              (Just (showT (auUserId (scUser ctx))))
              (auRole (scUser ctx))
      withComplianceLog (logTransactionClear lctx txId) $
        runTxEff env (clearTransaction txId) >> pure NoContent

    getAvailableInventoryHandler :: Maybe Text -> UUID -> Handler AvailableInventory
    getAvailableInventoryHandler mHeader sku = do
      ctx <- requireAuth env mHeader
      liftIO $
        logHttpRequest
          logEnv
          "GET"
          ("/inventory/available/" <> showT sku)
          (showT (auUserId (scUser ctx)))
      runTxEff env $ do
        result <- getInventoryAvailability sku
        case result of
          Nothing -> throwError err404 {errBody = "Item not found"}
          Just (total, reserved) ->
            pure
              AvailableInventory
                { availableTotal = total
                , availableReserved = reserved
                , availableActual = total - reserved
                }

    reserveInventoryHandler :: Maybe Text -> ReservationRequest -> Handler InventoryReservation
    reserveInventoryHandler mHeader request = do
      ctx <- requireAuth env mHeader
      liftIO $
        logHttpRequest
          logEnv
          "POST"
          "/inventory/reserve"
          (showT (auUserId (scUser ctx)))
      runTxEff env $ do
        result <- getInventoryAvailability (reserveItemSku request)
        case result of
          Nothing -> throwError err404 {errBody = "Item not found"}
          Just (total, reserved) -> do
            let available = total - reserved
            when (available < reserveQuantity request) $
              throwError
                err400
                  { errBody =
                      LBS.pack $
                        "Insufficient inventory. Only " ++ show available ++ " available"
                  }
            reservationId <- nextUUID
            now <- currentTime
            createReservation
              reservationId
              (reserveItemSku request)
              (reserveTransactionId request)
              (reserveQuantity request)
              now
            pure
              InventoryReservation
                { reservationItemSku = reserveItemSku request
                , reservationTransactionId = reserveTransactionId request
                , reservationQuantity = reserveQuantity request
                , reservationStatus = "Reserved"
                }

    releaseInventoryHandler :: Maybe Text -> UUID -> Handler NoContent
    releaseInventoryHandler mHeader reservationId = do
      ctx <- requireAuth env mHeader
      liftIO $
        logHttpRequest
          logEnv
          "DELETE"
          ("/inventory/release/" <> showT reservationId)
          (showT (auUserId (scUser ctx)))
      runTxEff env $ do
        released <- releaseReservation reservationId
        if released
          then pure NoContent
          else throwError err404 {errBody = "Reservation not found or already released"}

registerServer :: AppEnv -> Server RegisterAPI
registerServer env =
  getAllRegistersHandler
    :<|> getRegisterHandler
    :<|> createRegisterHandler
    :<|> updateRegisterHandler
    :<|> openRegisterHandler
    :<|> closeRegisterHandler
  where
    logEnv = envLogEnv env

    getAllRegistersHandler :: Maybe Text -> Handler [Register]
    getAllRegistersHandler mHeader = do
      ctx <- requireAuth env mHeader
      liftIO $
        logHttpRequest
          logEnv
          "GET"
          "/register"
          (showT (auUserId (scUser ctx)))
      runRegEff env getAllRegisters

    getRegisterHandler :: Maybe Text -> UUID -> Handler Register
    getRegisterHandler mHeader regId = do
      ctx <- requireAuth env mHeader
      liftIO $
        logHttpRequest
          logEnv
          "GET"
          ("/register/" <> showT regId)
          (showT (auUserId (scUser ctx)))
      runRegEff env $ do
        maybeReg <- getRegisterById regId
        case maybeReg of
          Just reg -> pure reg
          Nothing -> throwError err404 {errBody = "Register not found"}

    createRegisterHandler :: Maybe Text -> Register -> Handler Register
    createRegisterHandler mHeader register = do
      ctx <- requireAuth env mHeader
      let lctx =
            makeLogCtx
              logEnv
              (Just (showT (auUserId (scUser ctx))))
              (auRole (scUser ctx))
      liftIO $
        logHttpRequest
          logEnv
          "POST"
          "/register"
          (showT (auUserId (scUser ctx)))
      withComplianceLog
        (logRegisterCreate lctx (registerId register))
        $ runRegEff env (createRegister register)

    updateRegisterHandler :: Maybe Text -> UUID -> Register -> Handler Register
    updateRegisterHandler mHeader regId register = do
      ctx <- requireAuth env mHeader
      liftIO $
        logHttpRequest
          logEnv
          "PUT"
          ("/register/" <> showT regId)
          (showT (auUserId (scUser ctx)))
      runRegEff env (updateRegister regId register)

    openRegisterHandler :: Maybe Text -> UUID -> OpenRegisterRequest -> Handler Register
    openRegisterHandler mHeader regId request = do
      ctx <- requireAuth env mHeader
      let
        empId = openRegisterEmployeeId request
        startCash = openRegisterStartingCash request
        lctx = empLogCtx logEnv empId
      liftIO $
        logHttpRequest
          logEnv
          "POST"
          ("/register/open/" <> showT regId)
          (showT (auUserId (scUser ctx)))
      withComplianceLog
        (\outcome -> logRegisterOpen lctx regId startCash outcome)
        $ runRegEff env (SvcReg.openRegister regId request)

    closeRegisterHandler :: Maybe Text -> UUID -> CloseRegisterRequest -> Handler CloseRegisterResult
    closeRegisterHandler mHeader regId request = do
      ctx <- requireAuth env mHeader
      let
        empId = closeRegisterEmployeeId request
        countedCash = closeRegisterCountedCash request
        lctx = empLogCtx logEnv empId
      liftIO $
        logHttpRequest
          logEnv
          "POST"
          ("/register/close/" <> showT regId)
          (showT (auUserId (scUser ctx)))
      withComplianceLog
        (\outcome -> logRegisterClose lctx regId countedCash 0 outcome)
        $ do
          result <- runRegEff env (SvcReg.closeRegister regId request)
          liftIO $
            logRegisterClose
              lctx
              regId
              countedCash
              (closeRegisterResultVariance result)
              LogSuccess
          pure result

ledgerServer :: AppEnv -> Server LedgerAPI
ledgerServer env =
  getEntriesHandler
    :<|> getEntryHandler
    :<|> getAccountsHandler
    :<|> getAccountHandler
    :<|> createAccountHandler
    :<|> dailyReportHandler
  where
    getEntriesHandler mHeader =
      void (requireAuth env mHeader) >> pure []

    getEntryHandler mHeader _ =
      void (requireAuth env mHeader)
        >> Servant.throwError err501 {errBody = "Not implemented"}

    getAccountsHandler mHeader =
      void (requireAuth env mHeader) >> pure []

    getAccountHandler mHeader _ =
      void (requireAuth env mHeader)
        >> Servant.throwError err501 {errBody = "Not implemented"}

    createAccountHandler mHeader _ =
      void (requireAuth env mHeader)
        >> Servant.throwError err501 {errBody = "Not implemented"}

    dailyReportHandler mHeader _ =
      void (requireAuth env mHeader) >> pure (DailyReportResult 0 0 0 0 0)

complianceServer :: AppEnv -> Server ComplianceAPI
complianceServer env =
  verificationHandler
    :<|> getRecordHandler
    :<|> reportHandler
  where
    verificationHandler mHeader v =
      void (requireAuth env mHeader) >> pure v

    getRecordHandler mHeader _ =
      void (requireAuth env mHeader)
        >> Servant.throwError err501 {errBody = "Not implemented"}

    reportHandler mHeader _ =
      void (requireAuth env mHeader)
        >> pure (ComplianceReportResult (pack "Not implemented"))

posServerImpl :: AppEnv -> Server PosAPI
posServerImpl env =
  transactionServer env
    :<|> registerServer env
    :<|> ledgerServer env
    :<|> complianceServer env
