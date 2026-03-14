{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant return" #-}

module Server.Transaction where

import API.Transaction
import Control.Exception (SomeException, try, displayException, fromException)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (encode, object, (.=))
import Data.Text (Text, pack)
import Data.Time (getCurrentTime)
import Data.UUID (UUID)
import Data.UUID.V4 (nextRandom)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Servant
import Types.Transaction

import DB.Database (DBPool)
import qualified DB.Transaction as DB

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
      liftIO $ putStrLn "Handling GET /transaction request"
      transactions <- liftIO $ DB.getAllTransactions pool
      liftIO $ putStrLn $ "Returning " ++ show (length transactions) ++ " transactions"
      return transactions

    getTransactionHandler :: UUID -> Handler Transaction
    getTransactionHandler txId = do
      liftIO $ putStrLn $ "Handling GET /transaction/" ++ show txId ++ " request"
      maybeTransaction <- liftIO $ DB.getTransactionById pool txId
      case maybeTransaction of
        Just tx -> return tx
        Nothing -> throwError err404 { errBody = stringToLBS "Transaction not found" }

    getAvailableInventoryHandler :: UUID -> Handler AvailableInventory
    getAvailableInventoryHandler sku = do
      liftIO $ putStrLn $ "Handling GET /inventory/available/" ++ show sku ++ " request"
      result <- liftIO $ DB.getInventoryAvailability pool sku
      case result of
        Nothing               -> throwError err404 { errBody = stringToLBS "Item not found" }
        Just (total, reserved) ->
          return AvailableInventory
            { availableTotal    = total
            , availableReserved = reserved
            , availableActual   = total - reserved
            }

    reserveInventoryHandler :: ReservationRequest -> Handler InventoryReservation
    reserveInventoryHandler request = do
      liftIO $ putStrLn "Handling POST /inventory/reserve request"
      result <- liftIO $ DB.getInventoryAvailability pool (reserveItemSku request)
      case result of
        Nothing -> throwError err404 { errBody = stringToLBS "Item not found" }
        Just (total, reserved) -> do
          let available = total - reserved
          if available < reserveQuantity request
            then throwError err400
                   { errBody = stringToLBS $
                       "Insufficient inventory. Only " ++ show available ++ " available" }
            else do
              reservationId <- liftIO nextRandom
              now           <- liftIO getCurrentTime
              liftIO $ DB.createInventoryReservation pool reservationId
                (reserveItemSku request)
                (reserveTransactionId request)
                (reserveQuantity request)
                now
              return InventoryReservation
                { reservationItemSku       = reserveItemSku request
                , reservationTransactionId = reserveTransactionId request
                , reservationQuantity      = reserveQuantity request
                , reservationStatus        = "Reserved"
                }

    releaseInventoryHandler :: UUID -> Handler NoContent
    releaseInventoryHandler reservationId = do
      liftIO $ putStrLn $ "Handling DELETE /inventory/release/" ++ show reservationId ++ " request"
      released <- liftIO $ DB.releaseInventoryReservation pool reservationId
      if released
        then return NoContent
        else throwError err404
               { errBody = stringToLBS "Reservation not found or already released" }

    createTransactionHandler :: Transaction -> Handler Transaction
    createTransactionHandler transaction = do
      liftIO $ putStrLn "Handling POST /transaction request"
      liftIO $ putStrLn $ "Creating transaction: " ++ show (transactionId transaction)
      created <- liftIO $ DB.createTransaction pool transaction
      liftIO $ putStrLn "Transaction created successfully"
      return created

    updateTransactionHandler :: UUID -> Transaction -> Handler Transaction
    updateTransactionHandler txId transaction = do
      liftIO $ putStrLn $ "Handling PUT /transaction/" ++ show txId ++ " request"
      updated <- liftIO $ DB.updateTransaction pool txId transaction
      liftIO $ putStrLn "Transaction updated successfully"
      return updated

    voidTransactionHandler :: UUID -> Text -> Handler Transaction
    voidTransactionHandler txId reason = do
      liftIO $ putStrLn $ "Handling POST /transaction/void/" ++ show txId ++ " request"
      voided <- liftIO $ DB.voidTransaction pool txId reason
      liftIO $ putStrLn "Transaction voided successfully"
      return voided

    refundTransactionHandler :: UUID -> Text -> Handler Transaction
    refundTransactionHandler txId reason = do
      liftIO $ putStrLn $ "Handling POST /transaction/refund/" ++ show txId ++ " request"
      refunded <- liftIO $ DB.refundTransaction pool txId reason
      liftIO $ putStrLn "Transaction refunded successfully"
      return refunded

    addTransactionItemHandler :: TransactionItem -> Handler TransactionItem
    addTransactionItemHandler item = do
      liftIO $ putStrLn "Handling POST /transaction/item request"
      result <- liftIO $ try @SomeException $ DB.addTransactionItem pool item
      case result of
        Right added -> do
          liftIO $ putStrLn "Transaction item added successfully"
          return added
        Left e -> do
          let errorMsg = case fromException e of
                Just (DB.ItemNotFound sku) ->
                  "Item not found: " ++ show sku
                Just (DB.InsufficientInventory sku requested available) ->
                  "Insufficient inventory for item " ++ show sku ++
                  ". Only " ++ show available ++ " available, but " ++
                  show requested ++ " requested."
                Nothing -> displayException e
          liftIO $ putStrLn $ "Error adding transaction item: " ++ errorMsg
          throwError err400 { errBody = encode $ object ["error" .= errorMsg] }

    removeTransactionItemHandler :: UUID -> Handler NoContent
    removeTransactionItemHandler itemId = do
      liftIO $ putStrLn $ "Handling DELETE /transaction/item/" ++ show itemId ++ " request"
      liftIO $ DB.deleteTransactionItem pool itemId
      liftIO $ putStrLn "Transaction item deleted successfully"
      return NoContent

    clearTransactionHandler :: UUID -> Handler NoContent
    clearTransactionHandler txId = do
      liftIO $ putStrLn $ "Handling POST /transaction/clear/" ++ show txId ++ " request"
      liftIO $ DB.clearTransaction pool txId
      return NoContent

    addPaymentTransactionHandler :: PaymentTransaction -> Handler PaymentTransaction
    addPaymentTransactionHandler payment = do
      liftIO $ putStrLn "Handling POST /transaction/payment request"
      added <- liftIO $ DB.addPaymentTransaction pool payment
      liftIO $ putStrLn "Payment transaction added successfully"
      return added

    removePaymentTransactionHandler :: UUID -> Handler NoContent
    removePaymentTransactionHandler pymtId = do
      liftIO $ putStrLn $ "Handling DELETE /transaction/payment/" ++ show pymtId ++ " request"
      liftIO $ DB.deletePaymentTransaction pool pymtId
      liftIO $ putStrLn "Payment transaction deleted successfully"
      return NoContent

    finalizeTransactionHandler :: UUID -> Handler Transaction
    finalizeTransactionHandler txId = do
      liftIO $ putStrLn $ "Handling POST /transaction/finalize/" ++ show txId ++ " request"
      finalized <- liftIO $ DB.finalizeTransaction pool txId
      liftIO $ putStrLn "Transaction finalized successfully"
      return finalized

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
      liftIO $ putStrLn "Handling GET /register request"
      liftIO $ DB.getAllRegisters pool

    getRegisterHandler :: UUID -> Handler Register
    getRegisterHandler regId = do
      liftIO $ putStrLn $ "Handling GET /register/" ++ show regId ++ " request"
      maybeRegister <- liftIO $ DB.getRegisterById pool regId
      case maybeRegister of
        Just reg -> return reg
        Nothing  -> throwError err404 { errBody = stringToLBS "Register not found" }

    createRegisterHandler :: Register -> Handler Register
    createRegisterHandler register = do
      liftIO $ putStrLn "Handling POST /register request"
      liftIO $ DB.createRegister pool register

    updateRegisterHandler :: UUID -> Register -> Handler Register
    updateRegisterHandler regId register = do
      liftIO $ putStrLn $ "Handling PUT /register/" ++ show regId ++ " request"
      liftIO $ DB.updateRegister pool regId register

    openRegisterHandler :: UUID -> OpenRegisterRequest -> Handler Register
    openRegisterHandler regId request = do
      liftIO $ putStrLn $ "Handling POST /register/open/" ++ show regId ++ " request"
      liftIO $ DB.openRegister pool regId request

    closeRegisterHandler :: UUID -> CloseRegisterRequest -> Handler CloseRegisterResult
    closeRegisterHandler regId request = do
      liftIO $ putStrLn $ "Handling POST /register/close/" ++ show regId ++ " request"
      liftIO $ DB.closeRegister pool regId request

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
      liftIO $ putStrLn "Handling GET /ledger/entry request"
      return []

    getEntryHandler :: UUID -> Handler LedgerEntry
    getEntryHandler entryId = do
      liftIO $ putStrLn $ "Handling GET /ledger/entry/" ++ show entryId ++ " request"
      throwError err501 { errBody = stringToLBS "Not implemented yet" }

    getAccountsHandler :: Handler [Account]
    getAccountsHandler = do
      liftIO $ putStrLn "Handling GET /ledger/account request"
      return []

    getAccountHandler :: UUID -> Handler Account
    getAccountHandler acctId = do
      liftIO $ putStrLn $ "Handling GET /ledger/account/" ++ show acctId ++ " request"
      throwError err501 { errBody = stringToLBS "Not implemented yet" }

    createAccountHandler :: Account -> Handler Account
    createAccountHandler _ = do
      liftIO $ putStrLn "Handling POST /ledger/account request"
      throwError err501 { errBody = stringToLBS "Not implemented yet" }

    dailyReportHandler :: DailyReportRequest -> Handler DailyReportResult
    dailyReportHandler _ = do
      liftIO $ putStrLn "Handling POST /ledger/report/daily request"
      return $ DailyReportResult 0 0 0 0 0

complianceServer :: DBPool -> Server ComplianceAPI
complianceServer _ =
  verificationHandler
    :<|> getRecordHandler
    :<|> reportHandler
  where
    verificationHandler :: CustomerVerification -> Handler CustomerVerification
    verificationHandler verification = do
      liftIO $ putStrLn "Handling POST /compliance/verification request"
      return verification

    getRecordHandler :: UUID -> Handler ComplianceRecord
    getRecordHandler txId = do
      liftIO $ putStrLn $ "Handling GET /compliance/record/" ++ show txId ++ " request"
      throwError err501 { errBody = stringToLBS "Not implemented yet" }

    reportHandler :: ComplianceReportRequest -> Handler ComplianceReportResult
    reportHandler _ = do
      liftIO $ putStrLn "Handling POST /compliance/report request"
      return $ ComplianceReportResult (pack "Report Not Implemented")

posServerImpl :: DBPool -> Server PosAPI
posServerImpl pool =
  transactionServer pool
    :<|> registerServer pool
    :<|> ledgerServer pool
    :<|> complianceServer pool