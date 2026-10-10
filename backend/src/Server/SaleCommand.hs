{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Server.SaleCommand (saleCommandServer) where

import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)
import qualified Data.Text as T
import Data.UUID (UUID)
import Effectful (Eff, IOE, runEff)
import Effectful.Error.Static (Error, runErrorNoCallStack)
import Servant hiding (throwError)
import qualified Servant (throwError)

import API.SaleCommand (SaleCommandAPI)
import Auth.Session (SessionContext (..))
import Config.App (cfgStockPolicy)
import Effect.Clock
import Effect.EventEmitter
import Effect.GenUUID
import Effect.InventoryDb (InventoryDb, runInventoryDbIO)
import Effect.StockDb (StockDb, runStockDbIO)
import Effect.TaxRules (TaxRules, runTaxRulesIO)
import Effect.TransactionDb
import Logging
import Server.Env (AppEnv (..))
import Server.Transaction
  ( requireAuth
  , requireCapability
  , requireSaleWriter
  , showT
  , withComplianceLog
  )
import qualified Service.Sale as SaleSvc
import Types.Auth (UserCapabilities (..), auRole, auUserId)
import Types.Primitives.Money (saleMoneyCents)
import Types.Transaction.Request
import qualified Types.Transaction.Sale as Sale

type SaleEffs =
  '[ TaxRules
   , GenUUID
   , Clock
   , TransactionDb
   , StockDb
   , InventoryDb
   , EventEmitter
   , Error ServerError
   , IOE
   ]

runSaleEff :: AppEnv -> Eff SaleEffs a -> Handler a
runSaleEff env action = do
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
      . runTaxRulesIO (envDbPool env)
      $ action
  either Servant.throwError pure result

-- | Every handler here does three things before it runs its command.
--
-- 1. It resolves the session. No session is a 401.
-- 2. It requires the capability to process transactions. A role without it
--    gets a 403.
-- 3. For a command on an existing sale, it requires that the signed-in user
--    opened the sale, or is a manager or an admin. Anyone else gets a 403.
--
-- The employee recorded on a new sale is the signed-in user. The employee
-- id in the request body is ignored.
saleCommandServer :: AppEnv -> Server SaleCommandAPI
saleCommandServer env =
  startHandler
    :<|> addItemHandler
    :<|> removeItemHandler
    :<|> addPaymentHandler
    :<|> removePaymentHandler
    :<|> clearHandler
    :<|> finalizeHandler
  where
    logEnv = envLogEnv env

    -- Authenticates, writes the HTTP log line, requires the capability to
    -- process transactions, and returns the session with the log context
    -- for the signed-in user.
    begin :: Maybe Text -> Text -> Text -> Handler (SessionContext, LogCtx)
    begin mHeader method path = do
      ctx <- requireAuth env mHeader
      let userId = showT (auUserId (scUser ctx))
      liftIO $ logHttpRequest logEnv method path userId
      requireCapability env ctx "capCanProcessTransaction" capCanProcessTransaction
      pure (ctx, makeLogCtx logEnv (Just userId) (auRole (scUser ctx)))

    startHandler :: Maybe Text -> StartSaleRequest -> Handler Sale.SaleTransaction
    startHandler mHeader req = do
      (ctx, lctx) <- begin mHeader "POST" "/pos/sale"
      let asCaller = req {startSaleEmployeeId = auUserId (scUser ctx)}
      sale <- runSaleEff env (SaleSvc.startSale asCaller)
      liftIO $ logTransactionCreate lctx (Sale.saleId sale) LogSuccess
      pure sale

    addItemHandler :: Maybe Text -> AddItemRequest -> Handler Sale.SaleTransaction
    addItemHandler mHeader req = do
      (ctx, lctx) <- begin mHeader "POST" "/pos/sale/item"
      requireSaleWriter env ctx (addItemSaleId req)
      withComplianceLog
        (logTransactionAddItem lctx (addItemSaleId req) (addItemSku req) (addItemQuantity req))
        $ runSaleEff env (SaleSvc.addItem req)

    -- An item id that belongs to no sale is passed on, and the command
    -- answers 404.
    removeItemHandler :: Maybe Text -> UUID -> Handler Sale.SaleTransaction
    removeItemHandler mHeader itemId = do
      (ctx, _) <- begin mHeader "DELETE" ("/pos/sale/item/" <> showT itemId)
      owner <- runSaleEff env (getTxIdByItemId itemId)
      mapM_ (requireSaleWriter env ctx) owner
      runSaleEff env (SaleSvc.removeItem itemId)

    addPaymentHandler :: Maybe Text -> AddPaymentRequest -> Handler Sale.SaleTransaction
    addPaymentHandler mHeader req = do
      (ctx, lctx) <- begin mHeader "POST" "/pos/sale/payment"
      requireSaleWriter env ctx (addPaymentSaleId req)
      withComplianceLog
        ( logTransactionAddPayment
            lctx
            (addPaymentSaleId req)
            (addPaymentAmount req)
            (T.pack (show (addPaymentMethod req)))
        )
        $ runSaleEff env (SaleSvc.addPayment req)

    -- A payment id that belongs to no sale is passed on, and the command
    -- answers 404.
    removePaymentHandler :: Maybe Text -> UUID -> Handler Sale.SaleTransaction
    removePaymentHandler mHeader paymentId = do
      (ctx, _) <- begin mHeader "DELETE" ("/pos/sale/payment/" <> showT paymentId)
      owner <- runSaleEff env (getTxIdByPaymentId paymentId)
      mapM_ (requireSaleWriter env ctx) owner
      runSaleEff env (SaleSvc.removePayment paymentId)

    clearHandler :: Maybe Text -> UUID -> Handler Sale.SaleTransaction
    clearHandler mHeader saleId = do
      (ctx, lctx) <- begin mHeader "POST" ("/pos/sale/clear/" <> showT saleId)
      requireSaleWriter env ctx saleId
      withComplianceLog (logTransactionClear lctx saleId) $
        runSaleEff env (SaleSvc.clear saleId)

    -- A refused or failed finalize is logged by withComplianceLog with zero
    -- amounts. A successful one is logged once with the real total and item
    -- count.
    finalizeHandler :: Maybe Text -> UUID -> Handler Sale.SaleTransaction
    finalizeHandler mHeader saleId = do
      (ctx, lctx) <- begin mHeader "POST" ("/pos/sale/finalize/" <> showT saleId)
      requireSaleWriter env ctx saleId
      sale <-
        withComplianceLog (logFailureOnly (logTransactionFinalize lctx saleId 0 0)) $
          runSaleEff env (SaleSvc.finalize saleId)
      liftIO $
        logTransactionFinalize
          lctx
          saleId
          (saleMoneyCents (Sale.saleTotal sale))
          (length (Sale.saleItems sale))
          LogSuccess
      pure sale

    logFailureOnly :: (LogOutcome -> IO ()) -> LogOutcome -> IO ()
    logFailureOnly _ LogSuccess       = pure ()
    logFailureOnly logIt (LogFailure e) = logIt (LogFailure e)