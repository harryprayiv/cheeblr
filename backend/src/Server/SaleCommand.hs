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
import Effect.Clock
import Effect.EventEmitter
import Effect.GenUUID
import Effect.InventoryDb (InventoryDb, runInventoryDbIO)
import Effect.StockDb (StockDb, runStockDbIO)
import Effect.TaxRules (TaxRules, runTaxRulesIO)
import Effect.TransactionDb
import Logging
import Server.Env (AppEnv (..))
import Server.Transaction (requireAuth, showT, withComplianceLog)
import qualified Service.Sale as SaleSvc
import Types.Auth (auRole, auUserId)
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
      . runTransactionDbIO (envDbPool env)
      . runClockIO
      . runGenUUIDIO
      . runTaxRulesIO (envDbPool env)
      $ action
  either Servant.throwError pure result

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

    -- Authenticates, writes the HTTP log line, and returns the log context
    -- for the signed-in user.
    begin :: Maybe Text -> Text -> Text -> Handler LogCtx
    begin mHeader method path = do
      ctx <- requireAuth env mHeader
      let userId = showT (auUserId (scUser ctx))
      liftIO $ logHttpRequest logEnv method path userId
      pure (makeLogCtx logEnv (Just userId) (auRole (scUser ctx)))

    startHandler :: Maybe Text -> StartSaleRequest -> Handler Sale.SaleTransaction
    startHandler mHeader req = do
      lctx <- begin mHeader "POST" "/pos/sale"
      sale <- runSaleEff env (SaleSvc.startSale req)
      liftIO $ logTransactionCreate lctx (Sale.saleId sale) LogSuccess
      pure sale

    addItemHandler :: Maybe Text -> AddItemRequest -> Handler Sale.SaleTransaction
    addItemHandler mHeader req = do
      lctx <- begin mHeader "POST" "/pos/sale/item"
      withComplianceLog
        (logTransactionAddItem lctx (addItemSaleId req) (addItemSku req) (addItemQuantity req))
        $ runSaleEff env (SaleSvc.addItem req)

    removeItemHandler :: Maybe Text -> UUID -> Handler Sale.SaleTransaction
    removeItemHandler mHeader itemId = do
      _ <- begin mHeader "DELETE" ("/pos/sale/item/" <> showT itemId)
      runSaleEff env (SaleSvc.removeItem itemId)

    addPaymentHandler :: Maybe Text -> AddPaymentRequest -> Handler Sale.SaleTransaction
    addPaymentHandler mHeader req = do
      lctx <- begin mHeader "POST" "/pos/sale/payment"
      withComplianceLog
        ( logTransactionAddPayment
            lctx
            (addPaymentSaleId req)
            (addPaymentAmount req)
            (T.pack (show (addPaymentMethod req)))
        )
        $ runSaleEff env (SaleSvc.addPayment req)

    removePaymentHandler :: Maybe Text -> UUID -> Handler Sale.SaleTransaction
    removePaymentHandler mHeader paymentId = do
      _ <- begin mHeader "DELETE" ("/pos/sale/payment/" <> showT paymentId)
      runSaleEff env (SaleSvc.removePayment paymentId)

    clearHandler :: Maybe Text -> UUID -> Handler Sale.SaleTransaction
    clearHandler mHeader saleId = do
      lctx <- begin mHeader "POST" ("/pos/sale/clear/" <> showT saleId)
      withComplianceLog (logTransactionClear lctx saleId) $
        runSaleEff env (SaleSvc.clear saleId)

    -- A refused or failed finalize is logged by withComplianceLog with zero
    -- amounts. A successful one is logged once with the real total and item
    -- count.
    finalizeHandler :: Maybe Text -> UUID -> Handler Sale.SaleTransaction
    finalizeHandler mHeader saleId = do
      lctx <- begin mHeader "POST" ("/pos/sale/finalize/" <> showT saleId)
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