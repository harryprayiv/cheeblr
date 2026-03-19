{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant return" #-}

module Server.Transaction where

import API.Transaction
import Control.Monad.IO.Class (liftIO)
import Data.Text (Text, pack)
import Data.UUID (UUID)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Effectful (Eff, IOE, runEff)
import Effectful.Error.Static (Error, runErrorNoCallStack, throwError)
import Servant hiding (throwError)
import qualified Servant as Servant (throwError)
import Types.Transaction

import DB.Database (DBPool)
import Effect.Clock
import Effect.GenUUID
import Effect.RegisterDb
import Effect.TransactionDb
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

stringToLBS :: String -> LBS.ByteString
stringToLBS = LBS.pack

transactionServer :: DBPool -> Server TransactionAPI
transactionServer pool =
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
    getAllTransactionsHandler :: Handler [Transaction]
    getAllTransactionsHandler = do
      liftIO $ putStrLn "GET /transaction"
      runTxEff pool getAllTransactions

    getTransactionHandler :: UUID -> Handler Transaction
    getTransactionHandler txId = do
      liftIO $ putStrLn $ "GET /transaction/" ++ show txId
      runTxEff pool $ do
        maybeTx <- getTransactionById txId
        case maybeTx of
          Just tx -> pure tx
          Nothing -> throwError err404 { errBody = "Transaction not found" }

    createTransactionHandler :: Transaction -> Handler Transaction
    createTransactionHandler tx = do
      liftIO $ putStrLn $ "POST /transaction: " ++ show (transactionId tx)
      runTxEff pool (createTransaction tx)

    updateTransactionHandler :: UUID -> Transaction -> Handler Transaction
    updateTransactionHandler txId tx = do
      liftIO $ putStrLn $ "PUT /transaction/" ++ show txId
      runTxEff pool (updateTransaction txId tx)

    voidTransactionHandler :: UUID -> Text -> Handler Transaction
    voidTransactionHandler txId reason = do
      liftIO $ putStrLn $ "POST /transaction/void/" ++ show txId
      runTxEff pool (SvcTx.voidTx txId reason)

    refundTransactionHandler :: UUID -> Text -> Handler Transaction
    refundTransactionHandler txId reason = do
      liftIO $ putStrLn $ "POST /transaction/refund/" ++ show txId
      runTxEff pool (SvcTx.refundTx txId reason)

    addTransactionItemHandler :: TransactionItem -> Handler TransactionItem
    addTransactionItemHandler item = do
      liftIO $ putStrLn "POST /transaction/item"
      runTxEff pool (SvcTx.addItem item)

    removeTransactionItemHandler :: UUID -> Handler NoContent
    removeTransactionItemHandler itemId = do
      liftIO $ putStrLn $ "DELETE /transaction/item/" ++ show itemId
      runTxEff pool (SvcTx.removeItem itemId) >> pure NoContent

    addPaymentTransactionHandler :: PaymentTransaction -> Handler PaymentTransaction
    addPaymentTransactionHandler payment = do
      liftIO $ putStrLn "POST /transaction/payment"
      runTxEff pool (SvcTx.addPayment payment)

    removePaymentTransactionHandler :: UUID -> Handler NoContent
    removePaymentTransactionHandler pymtId = do
      liftIO $ putStrLn $ "DELETE /transaction/payment/" ++ show pymtId
      runTxEff pool (SvcTx.removePayment pymtId) >> pure NoContent

    finalizeTransactionHandler :: UUID -> Handler Transaction
    finalizeTransactionHandler txId = do
      liftIO $ putStrLn $ "POST /transaction/finalize/" ++ show txId
      runTxEff pool (SvcTx.finalizeTx txId)

    clearTransactionHandler :: UUID -> Handler NoContent
    clearTransactionHandler txId = do
      liftIO $ putStrLn $ "POST /transaction/clear/" ++ show txId
      runTxEff pool (clearTransaction txId) >> pure NoContent

    getAvailableInventoryHandler :: UUID -> Handler AvailableInventory
    getAvailableInventoryHandler sku = do
      liftIO $ putStrLn $ "GET /inventory/available/" ++ show sku
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
      liftIO $ putStrLn "POST /inventory/reserve"
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
      liftIO $ putStrLn $ "DELETE /inventory/release/" ++ show reservationId
      runTxEff pool $ do
        released <- releaseReservation reservationId
        if released
          then pure NoContent
          else throwError err404 { errBody = "Reservation not found or already released" }

registerServer :: DBPool -> Server RegisterAPI
registerServer pool =
  getAllRegistersHandler
    :<|> getRegisterHandler
    :<|> createRegisterHandler
    :<|> updateRegisterHandler
    :<|> openRegisterHandler
    :<|> closeRegisterHandler
  where
    getAllRegistersHandler :: Handler [Register]
    getAllRegistersHandler = do
      liftIO $ putStrLn "GET /register"
      runRegEff pool getAllRegisters

    getRegisterHandler :: UUID -> Handler Register
    getRegisterHandler regId = do
      liftIO $ putStrLn $ "GET /register/" ++ show regId
      runRegEff pool $ do
        maybeReg <- getRegisterById regId
        case maybeReg of
          Just reg -> pure reg
          Nothing  -> throwError err404 { errBody = "Register not found" }

    createRegisterHandler :: Register -> Handler Register
    createRegisterHandler register = do
      liftIO $ putStrLn "POST /register"
      runRegEff pool (createRegister register)

    updateRegisterHandler :: UUID -> Register -> Handler Register
    updateRegisterHandler regId register = do
      liftIO $ putStrLn $ "PUT /register/" ++ show regId
      runRegEff pool (updateRegister regId register)

    openRegisterHandler :: UUID -> OpenRegisterRequest -> Handler Register
    openRegisterHandler regId request = do
      liftIO $ putStrLn $ "POST /register/open/" ++ show regId
      runRegEff pool (SvcReg.openRegister regId request)

    closeRegisterHandler :: UUID -> CloseRegisterRequest -> Handler CloseRegisterResult
    closeRegisterHandler regId request = do
      liftIO $ putStrLn $ "POST /register/close/" ++ show regId
      runRegEff pool (SvcReg.closeRegister regId request)

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
    getEntriesHandler = do
      liftIO $ putStrLn "GET /ledger/entry"
      pure []

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

posServerImpl :: DBPool -> Server PosAPI
posServerImpl pool =
  transactionServer pool
    :<|> registerServer pool
    :<|> ledgerServer pool
    :<|> complianceServer pool