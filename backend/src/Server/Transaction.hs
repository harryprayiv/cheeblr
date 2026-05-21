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
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text, pack)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.UUID (UUID)
import Effectful (Eff, IOE, runEff)
import Effectful.Error.Static (Error, runErrorNoCallStack, throwError)
import Servant hiding (throwError)
import qualified Servant (throwError)

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
import Types.Primitives.Money (saleMoneyCents)
import Types.Primitives.Quantity (saleQuantityCount)
import qualified Types.Transaction.Refund as Refund
import qualified Types.Transaction.Sale as Sale
import Types.Transaction

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

requireAuth :: AppEnv -> Maybe Text -> Handler SessionContext
requireAuth env mHeader = resolveSession (envDbPool env) mHeader

withComplianceLog ::
  (LogOutcome -> IO ()) ->
  Handler a ->
  Handler a
withComplianceLog logIt action = do
  val <- action `catchError` \err -> do
    liftIO $ logIt (LogFailure (T.pack (show (errHTTPCode err))))
    Servant.throwError err
  liftIO $ logIt LogSuccess
  pure val

showT :: (Show a) => a -> Text
showT = T.pack . show

txtErr :: Text -> LBS.ByteString
txtErr = LBS.fromStrict . TE.encodeUtf8

-- ---------------------------------------------------------------------------
-- Sale server
-- ---------------------------------------------------------------------------

saleServer :: AppEnv -> Server SaleAPI
saleServer env =
  getAllSalesHandler
    :<|> getSaleHandler
    :<|> createSaleHandler
    :<|> voidSaleHandler
    :<|> refundSaleHandler
    :<|> addSaleItemHandler
    :<|> removeSaleItemHandler
    :<|> addSalePaymentHandler
    :<|> removeSalePaymentHandler
    :<|> finalizeSaleHandler
    :<|> clearSaleHandler
  where
    logEnv = envLogEnv env

    getAllSalesHandler :: Maybe Text -> Handler [Sale.SaleTransaction]
    getAllSalesHandler mHeader = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "GET" "/sale" (showT (auUserId (scUser ctx)))
      runTxEff env getAllSales

    getSaleHandler :: Maybe Text -> UUID -> Handler Sale.SaleTransaction
    getSaleHandler mHeader txId = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "GET" ("/sale/" <> showT txId)
        (showT (auUserId (scUser ctx)))
      r <- runTxEff env (getSaleById txId)
      case r of
        Right sale                 -> pure sale
        Left TypedNotFound         ->
          Servant.throwError err404 {errBody = "Sale not found"}
        Left TypedWrongKind        ->
          Servant.throwError err404 {errBody = "Sale not found"}
        Left (TypedDecodeFailed e) ->
          Servant.throwError err500
            { errBody = txtErr $ "Transaction failed typed conversion: " <> e }

    createSaleHandler :: Maybe Text -> Sale.SaleTransaction -> Handler Sale.SaleTransaction
    createSaleHandler mHeader sale = do
      ctx <- requireAuth env mHeader
      let
        empId = Sale.saleEmployeeId sale
        lctx  = empLogCtx logEnv empId
      liftIO $ logHttpRequest logEnv "POST" "/sale"
        (showT (auUserId (scUser ctx)))
      withComplianceLog (logTransactionCreate lctx (Sale.saleId sale)) $
        runTxEff env (SvcTx.createSaleSvc sale)

    -- PUT /sale/:id remains a whole-row update that bypasses the state
    -- machine. It is the next dead-code candidate; consumers should be
    -- audited before relying on it. Status changes go through specific
    -- endpoints (void, finalize, etc.) which use 'UpdateSaleStatus' and
    -- the state machine.
    -- updateSaleHandler :: Maybe Text -> UUID -> Sale.SaleTransaction -> Handler Sale.SaleTransaction
    -- updateSaleHandler mHeader _txId sale = do
    --   ctx <- requireAuth env mHeader
    --   liftIO $ logHttpRequest logEnv "PUT" ("/sale/" <> showT (Sale.saleId sale))
    --     (showT (auUserId (scUser ctx)))
    --   -- No service-layer wrapper exists for whole-row replace, and the
    --   -- old `updateTransaction` effect op was removed in 2H-3b. This
    --   -- handler is currently a placeholder that 501s. Replace with a
    --   -- state-machine-aware update if a real use case appears, or
    --   -- delete the endpoint outright.
    --   Servant.throwError err501
    --     { errBody = "PUT /sale/:id: not implemented in the typed service layer" }

    voidSaleHandler :: Maybe Text -> UUID -> Text -> Handler Sale.SaleTransaction
    voidSaleHandler mHeader txId reason = do
      ctx <- requireAuth env mHeader
      let lctx = makeLogCtx logEnv
                   (Just (showT (auUserId (scUser ctx))))
                   (auRole (scUser ctx))
      liftIO $ logHttpRequest logEnv "POST" ("/sale/void/" <> showT txId)
        (showT (auUserId (scUser ctx)))
      withComplianceLog
        (\outcome -> logTransactionVoid lctx txId reason outcome)
        $ runTxEff env (SvcTx.voidTx txId reason)

    refundSaleHandler :: Maybe Text -> UUID -> Text -> Handler Refund.RefundTransaction
    refundSaleHandler mHeader txId reason = do
      ctx <- requireAuth env mHeader
      let lctx = makeLogCtx logEnv
                   (Just (showT (auUserId (scUser ctx))))
                   (auRole (scUser ctx))
      liftIO $ logHttpRequest logEnv "POST" ("/sale/refund/" <> showT txId)
        (showT (auUserId (scUser ctx)))
      withComplianceLog
        (\outcome -> logTransactionRefund lctx txId reason outcome)
        $ runTxEff env (SvcTx.refundTx txId reason)

    addSaleItemHandler :: Maybe Text -> Sale.Item -> Handler Sale.Item
    addSaleItemHandler mHeader item = do
      ctx <- requireAuth env mHeader
      let
        txId  = Sale.itemTransactionId item
        skuId = Sale.itemMenuItemSku item
        qty   = saleQuantityCount (Sale.itemQuantity item)
      liftIO $ logHttpRequest logEnv "POST" "/sale/item"
        (showT (auUserId (scUser ctx)))
      -- Compliance log wants the employee id of the parent sale; pull
      -- it via the typed read.
      mEmpId <- runTxEff env $ do
        r <- getSaleById txId
        pure $ case r of
          Right sale -> Just (showT (Sale.saleEmployeeId sale))
          _          -> Nothing
      let lctx = case mEmpId of
            Just eid -> LogCtx logEnv eid "employee"
            Nothing  -> makeLogCtx logEnv
                          (Just (showT (auUserId (scUser ctx))))
                          (auRole (scUser ctx))
      withComplianceLog
        (\outcome -> logTransactionAddItem lctx txId skuId qty outcome)
        $ runTxEff env (SvcTx.addItem item)

    removeSaleItemHandler :: Maybe Text -> UUID -> Handler NoContent
    removeSaleItemHandler mHeader itemId = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "DELETE" ("/sale/item/" <> showT itemId)
        (showT (auUserId (scUser ctx)))
      runTxEff env (SvcTx.removeItem itemId) >> pure NoContent

    addSalePaymentHandler :: Maybe Text -> Sale.Payment -> Handler Sale.Payment
    addSalePaymentHandler mHeader payment = do
      ctx <- requireAuth env mHeader
      let
        txId   = Sale.paymentTransactionId payment
        amt    = saleMoneyCents (Sale.paymentAmount payment)
        method = T.pack (show (Sale.paymentMethod payment))
      liftIO $ logHttpRequest logEnv "POST" "/sale/payment"
        (showT (auUserId (scUser ctx)))
      mEmpId <- runTxEff env $ do
        r <- getSaleById txId
        pure $ case r of
          Right sale -> Just (showT (Sale.saleEmployeeId sale))
          _          -> Nothing
      let lctx = case mEmpId of
            Just eid -> LogCtx logEnv eid "employee"
            Nothing  -> makeLogCtx logEnv
                          (Just (showT (auUserId (scUser ctx))))
                          (auRole (scUser ctx))
      withComplianceLog
        (\outcome -> logTransactionAddPayment lctx txId amt method outcome)
        $ runTxEff env (SvcTx.addPayment payment)

    removeSalePaymentHandler :: Maybe Text -> UUID -> Handler NoContent
    removeSalePaymentHandler mHeader pymtId = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "DELETE" ("/sale/payment/" <> showT pymtId)
        (showT (auUserId (scUser ctx)))
      runTxEff env (SvcTx.removePayment pymtId) >> pure NoContent

    finalizeSaleHandler :: Maybe Text -> UUID -> Handler Sale.SaleTransaction
    finalizeSaleHandler mHeader txId = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "POST" ("/sale/finalize/" <> showT txId)
        (showT (auUserId (scUser ctx)))
      withComplianceLog
        (\outcome ->
            logTransactionFinalize
              (makeLogCtx logEnv
                (Just (showT (auUserId (scUser ctx))))
                (auRole (scUser ctx)))
              txId 0 0 outcome)
        $ do
            sale <- runTxEff env (SvcTx.finalizeTx txId)
            liftIO $
              logTransactionFinalize
                (empLogCtx logEnv (Sale.saleEmployeeId sale))
                txId
                (saleMoneyCents (Sale.saleTotal sale))
                (length (Sale.saleItems sale))
                LogSuccess
            pure sale

    clearSaleHandler :: Maybe Text -> UUID -> Handler NoContent
    clearSaleHandler mHeader txId = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "POST" ("/sale/clear/" <> showT txId)
        (showT (auUserId (scUser ctx)))
      let lctx = makeLogCtx logEnv
                   (Just (showT (auUserId (scUser ctx))))
                   (auRole (scUser ctx))
      withComplianceLog (logTransactionClear lctx txId) $
        runTxEff env (clearSale txId) >> pure NoContent

-- ---------------------------------------------------------------------------
-- Refund server
-- ---------------------------------------------------------------------------

refundServer :: AppEnv -> Server RefundAPI
refundServer env =
  getAllRefundsHandler
    :<|> getRefundHandler
  where
    logEnv = envLogEnv env

    getAllRefundsHandler :: Maybe Text -> Handler [Refund.RefundTransaction]
    getAllRefundsHandler mHeader = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "GET" "/refund" (showT (auUserId (scUser ctx)))
      runTxEff env getAllRefunds

    getRefundHandler :: Maybe Text -> UUID -> Handler Refund.RefundTransaction
    getRefundHandler mHeader txId = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "GET" ("/refund/" <> showT txId)
        (showT (auUserId (scUser ctx)))
      r <- runTxEff env (getRefundById txId)
      case r of
        Right refund               -> pure refund
        Left TypedNotFound         ->
          Servant.throwError err404 {errBody = "Refund not found"}
        Left TypedWrongKind        ->
          Servant.throwError err404 {errBody = "Refund not found"}
        Left (TypedDecodeFailed e) ->
          Servant.throwError err500
            { errBody = txtErr $ "Transaction failed typed conversion: " <> e }

-- ---------------------------------------------------------------------------
-- Reservation server
-- ---------------------------------------------------------------------------

reservationServer :: AppEnv -> Server ReservationAPI
reservationServer env =
  getAvailableInventoryHandler
    :<|> reserveInventoryHandler
    :<|> releaseInventoryHandler
  where
    logEnv = envLogEnv env

    getAvailableInventoryHandler :: Maybe Text -> UUID -> Handler AvailableInventory
    getAvailableInventoryHandler mHeader sku = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "GET" ("/inventory/available/" <> showT sku)
        (showT (auUserId (scUser ctx)))
      runTxEff env $ do
        result <- getInventoryAvailability sku
        case result of
          Nothing            -> throwError err404 {errBody = "Item not found"}
          Just (total, reserved) ->
            pure
              AvailableInventory
                { availableTotal    = total
                , availableReserved = reserved
                , availableActual   = total - reserved
                }

    reserveInventoryHandler :: Maybe Text -> ReservationRequest -> Handler InventoryReservation
    reserveInventoryHandler mHeader request = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "POST" "/inventory/reserve"
        (showT (auUserId (scUser ctx)))
      runTxEff env $ do
        result <- getInventoryAvailability (reserveItemSku request)
        case result of
          Nothing            -> throwError err404 {errBody = "Item not found"}
          Just (total, reserved) -> do
            let available = total - reserved
            when (available < reserveQuantity request) $
              throwError err400
                { errBody =
                    txtErr $
                      "Insufficient inventory. Only "
                        <> T.pack (show available) <> " available"
                }
            reservationId <- nextUUID
            now           <- currentTime
            createReservation
              reservationId
              (reserveItemSku request)
              (reserveTransactionId request)
              (reserveQuantity request)
              now
            pure
              InventoryReservation
                { reservationItemSku       = reserveItemSku request
                , reservationTransactionId = reserveTransactionId request
                , reservationQuantity      = reserveQuantity request
                , reservationStatus        = "Reserved"
                }

    releaseInventoryHandler :: Maybe Text -> UUID -> Handler NoContent
    releaseInventoryHandler mHeader reservationId = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "DELETE" ("/inventory/release/" <> showT reservationId)
        (showT (auUserId (scUser ctx)))
      runTxEff env $ do
        released <- releaseReservation reservationId
        if released
          then pure NoContent
          else throwError err404 {errBody = "Reservation not found or already released"}

-- ---------------------------------------------------------------------------
-- Other servers (unchanged)
-- ---------------------------------------------------------------------------

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

    getAllRegistersHandler mHeader = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "GET" "/register" (showT (auUserId (scUser ctx)))
      runRegEff env getAllRegisters

    getRegisterHandler mHeader regId = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "GET" ("/register/" <> showT regId)
        (showT (auUserId (scUser ctx)))
      runRegEff env $ do
        maybeReg <- getRegisterById regId
        case maybeReg of
          Just reg -> pure reg
          Nothing  -> throwError err404 {errBody = "Register not found"}

    createRegisterHandler mHeader register = do
      ctx <- requireAuth env mHeader
      let lctx = makeLogCtx logEnv
                   (Just (showT (auUserId (scUser ctx))))
                   (auRole (scUser ctx))
      liftIO $ logHttpRequest logEnv "POST" "/register" (showT (auUserId (scUser ctx)))
      withComplianceLog (logRegisterCreate lctx (registerId register))
        $ runRegEff env (createRegister register)

    updateRegisterHandler mHeader regId register = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "PUT" ("/register/" <> showT regId)
        (showT (auUserId (scUser ctx)))
      runRegEff env (updateRegister regId register)

    openRegisterHandler mHeader regId request = do
      ctx <- requireAuth env mHeader
      let empId = openRegisterEmployeeId request
          startCash = openRegisterStartingCash request
          lctx = empLogCtx logEnv empId
      liftIO $ logHttpRequest logEnv "POST" ("/register/open/" <> showT regId)
        (showT (auUserId (scUser ctx)))
      withComplianceLog (\outcome -> logRegisterOpen lctx regId startCash outcome)
        $ runRegEff env (SvcReg.openRegister regId request)

    closeRegisterHandler mHeader regId request = do
      ctx <- requireAuth env mHeader
      let empId = closeRegisterEmployeeId request
          countedCash = closeRegisterCountedCash request
          lctx = empLogCtx logEnv empId
      liftIO $ logHttpRequest logEnv "POST" ("/register/close/" <> showT regId)
        (showT (auUserId (scUser ctx)))
      withComplianceLog (\outcome -> logRegisterClose lctx regId countedCash 0 outcome)
        $ do
            result <- runRegEff env (SvcReg.closeRegister regId request)
            liftIO $
              logRegisterClose lctx regId countedCash
                (closeRegisterResultVariance result) LogSuccess
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
      void (requireAuth env mHeader) >>
        Servant.throwError err501 {errBody = "Not implemented"}
    getAccountsHandler mHeader =
      void (requireAuth env mHeader) >> pure []
    getAccountHandler mHeader _ =
      void (requireAuth env mHeader) >>
        Servant.throwError err501 {errBody = "Not implemented"}
    createAccountHandler mHeader _ =
      void (requireAuth env mHeader) >>
        Servant.throwError err501 {errBody = "Not implemented"}
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
      void (requireAuth env mHeader) >>
        Servant.throwError err501 {errBody = "Not implemented"}
    reportHandler mHeader _ =
      void (requireAuth env mHeader) >>
        pure (ComplianceReportResult (pack "Not implemented"))

posServerImpl :: AppEnv -> Server PosAPI
posServerImpl env =
  saleServer env
    :<|> refundServer env
    :<|> reservationServer env
    :<|> registerServer env
    :<|> ledgerServer env
    :<|> complianceServer env