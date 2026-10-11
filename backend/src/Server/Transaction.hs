{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant return" #-}

module Server.Transaction where

import API.Transaction
import Auth.Session (SessionContext (..), resolveSession)
import Config.App (cfgStockPolicy)
import Control.Monad (unless, void)
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
import Types.Auth (AuthenticatedUser (..), UserCapabilities (..), capabilitiesForRole)
import qualified Types.Auth as Auth
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
      . runTransactionDbIO (cfgStockPolicy (envConfig env)) (envDbPool env)
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

requireCapability ::
  AppEnv ->
  SessionContext ->
  Text ->
  (UserCapabilities -> Bool) ->
  Handler ()
requireCapability env ctx capName capFn =
  unless (capFn (capabilitiesForRole (auRole user))) $ do
    liftIO $ logAuthDenied (envLogEnv env) (showT (auUserId user)) capName
    Servant.throwError
      err403 {errBody = txtErr ("Forbidden: " <> capName <> " required")}
  where
    user = scUser ctx

mayWriteSale :: AuthenticatedUser -> UUID -> Bool
mayWriteSale user saleEmployee =
  auUserId user == saleEmployee
    || auRole user `elem` [Auth.Manager, Auth.Admin]

requireSaleWriter :: AppEnv -> SessionContext -> UUID -> Handler ()
requireSaleWriter env ctx saleId = do
  found <- runTxEff env (getSaleById saleId)
  case found of
    Right sale ->
      unless (mayWriteSale user (Sale.saleEmployeeId sale)) $ do
        liftIO $
          logAuthDenied (envLogEnv env) (showT (auUserId user)) "sale belongs to another employee"
        Servant.throwError
          err403 {errBody = "Forbidden: this sale belongs to another employee"}
    Left _ -> pure ()
  where
    user = scUser ctx

saleServer :: AppEnv -> Server SaleAPI
saleServer env =
  getAllSalesHandler
    :<|> getSaleHandler
    :<|> voidSaleHandler
    :<|> refundSaleHandler
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

    voidSaleHandler :: Maybe Text -> UUID -> Text -> Handler Sale.SaleTransaction
    voidSaleHandler mHeader txId reason = do
      ctx <- requireAuth env mHeader
      let lctx = makeLogCtx logEnv
                   (Just (showT (auUserId (scUser ctx))))
                   (auRole (scUser ctx))
      liftIO $ logHttpRequest logEnv "POST" ("/sale/void/" <> showT txId)
        (showT (auUserId (scUser ctx)))
      requireCapability env ctx "capCanVoidTransaction" capCanVoidTransaction
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
      requireCapability env ctx "capCanRefundTransaction" capCanRefundTransaction
      withComplianceLog
        (\outcome -> logTransactionRefund lctx txId reason outcome)
        $ runTxEff env (SvcTx.refundTx txId reason)

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

reservationServer :: AppEnv -> Server ReservationAPI
reservationServer env =
  getAvailableInventoryHandler
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
      requireCapability env ctx "capCanManageRegisters" capCanManageRegisters
      withComplianceLog (logRegisterCreate lctx (registerId register))
        $ runRegEff env (createRegister register)

    updateRegisterHandler mHeader regId register = do
      ctx <- requireAuth env mHeader
      liftIO $ logHttpRequest logEnv "PUT" ("/register/" <> showT regId)
        (showT (auUserId (scUser ctx)))
      requireCapability env ctx "capCanManageRegisters" capCanManageRegisters
      runRegEff env (updateRegister regId register)



    openRegisterHandler mHeader regId request = do
      ctx <- requireAuth env mHeader
      let empId     = auUserId (scUser ctx)
          startCash = openRegisterStartingCash request
          lctx      = empLogCtx logEnv empId
      liftIO $ logHttpRequest logEnv "POST" ("/register/open/" <> showT regId)
        (showT empId)
      requireCapability env ctx "capCanOpenRegister" capCanOpenRegister
      withComplianceLog (\outcome -> logRegisterOpen lctx regId startCash outcome)
        $ runRegEff env (SvcReg.openRegister regId empId request)



    closeRegisterHandler mHeader regId request = do
      ctx <- requireAuth env mHeader
      let empId       = auUserId (scUser ctx)
          countedCash = closeRegisterCountedCash request
          lctx        = empLogCtx logEnv empId
      liftIO $ logHttpRequest logEnv "POST" ("/register/close/" <> showT regId)
        (showT empId)
      requireCapability env ctx "capCanCloseRegister" capCanCloseRegister
      result <-
        runRegEff env (SvcReg.closeRegister regId empId request)
          `catchError` \err -> do
            liftIO $
              logRegisterClose lctx regId countedCash 0
                (LogFailure (T.pack (show (errHTTPCode err))))
            Servant.throwError err
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