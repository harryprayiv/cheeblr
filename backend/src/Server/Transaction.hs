{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant return" #-}

module Server.Transaction where

import API.Transaction
import Control.Monad.IO.Class (liftIO)
import Data.Pool (Pool)
import Data.UUID (UUID)
import Database.PostgreSQL.Simple (Connection, Only(..), query, execute, Query)
import DB.Transaction
import Servant
import Servant.API
import Types.Transaction
import Data.Text (Text, pack)
import qualified Data.ByteString.Lazy.Char8 as LBS
import qualified DB.Database as DB
import Data.UUID.V4 (nextRandom)
import Data.Time (getCurrentTime)

stringToLBS :: String -> LBS.ByteString
stringToLBS = LBS.pack

transactionServer :: Pool Connection -> Server TransactionAPI
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
    :<|> getAvailableInventoryHandler
    :<|> reserveInventoryHandler
    :<|> releaseInventoryHandler
  where
    getAllTransactionsHandler :: Handler [Transaction]
    getAllTransactionsHandler = do
      liftIO $ putStrLn "Handling GET /transaction request"
      transactions <- liftIO $ getAllTransactions pool
      liftIO $ putStrLn $ "Returning " ++ show (length transactions) ++ " transactions"
      return transactions

    getTransactionHandler :: UUID -> Handler Transaction
    getTransactionHandler txId = do
      liftIO $ putStrLn $ "Handling GET /transaction/" ++ show txId ++ " request"
      maybeTransaction <- liftIO $ getTransactionById pool txId
      case maybeTransaction of
        Just transaction -> return transaction
        Nothing -> throwError err404 { errBody = stringToLBS "Transaction not found" }

    getAvailableInventoryHandler :: UUID -> Handler AvailableInventory
    getAvailableInventoryHandler sku = do
      liftIO $ putStrLn $ "Handling GET /inventory/available/" ++ show sku ++ " request"
      
      -- Perform the database query in IO and then handle the result
      result <- liftIO $ DB.withConnection pool $ \conn -> do
        query conn
          ("SELECT m.quantity, COALESCE(SUM(r.quantity), 0) " <>
           "FROM menu_items m " <>
           "LEFT JOIN inventory_reservation r ON r.item_sku = m.sku AND r.status = 'Reserved' " <>
           "WHERE m.sku = ? " <>
           "GROUP BY m.quantity" :: Query)
          (Only sku) :: IO [(Int, Int)]
      
      case result of
        [] -> throwError err404 { errBody = stringToLBS "Item not found" }
        ((total, reserved):_) ->
          return $ AvailableInventory
            { availableTotal = total
            , availableReserved = reserved
            , availableActual = total - reserved
            }

    reserveInventoryHandler :: ReservationRequest -> Handler InventoryReservation
    reserveInventoryHandler request = do
      liftIO $ putStrLn "Handling POST /inventory/reserve request"
      
      -- Create a new reservation
      reservationId <- liftIO nextRandom
      now <- liftIO getCurrentTime
      
      -- Check availability and create reservation atomically
      result <- liftIO $ DB.withConnection pool $ \conn -> do
        -- Check current availability
        availability <- query conn
          ("SELECT m.quantity, COALESCE(SUM(r.quantity), 0) " <>
           "FROM menu_items m " <>
           "LEFT JOIN inventory_reservation r ON r.item_sku = m.sku AND r.status = 'Reserved' " <>
           "WHERE m.sku = ? " <>
           "GROUP BY m.quantity" :: Query)
          (Only $ reserveItemSku request) :: IO [(Int, Int)]
        
        case availability of
          [] -> return $ Left "Item not found"
          ((total, reserved):_) -> do
            let available = total - reserved
            if available < reserveQuantity request
              then return $ Left $ "Insufficient inventory. Only " ++ show available ++ " available"
              else do
                -- Create the reservation
                _ <- execute conn
                  ("INSERT INTO inventory_reservation " <>
                   "(id, item_sku, transaction_id, quantity, status, created_at) " <>
                   "VALUES (?, ?, ?, ?, 'Reserved', ?)" :: Query)
                  ( reservationId
                  , reserveItemSku request
                  , reserveTransactionId request
                  , reserveQuantity request
                  , now
                  )
                
                return $ Right $ InventoryReservation
                  { reservationItemSku = reserveItemSku request
                  , reservationTransactionId = reserveTransactionId request
                  , reservationQuantity = reserveQuantity request
                  , reservationStatus = "Reserved"
                  }
      
      case result of
        Left errMsg -> throwError err400 { errBody = stringToLBS errMsg }
        Right reservation -> return reservation

    releaseInventoryHandler :: UUID -> Handler NoContent
    releaseInventoryHandler reservationId = do
      liftIO $ putStrLn $ "Handling DELETE /inventory/release/" ++ show reservationId ++ " request"
      
      rowsAffected <- liftIO $ DB.withConnection pool $ \conn ->
        execute conn
          ("UPDATE inventory_reservation " <>
           "SET status = 'Released' " <>
           "WHERE id = ? AND status = 'Reserved'" :: Query)
          (Only reservationId)
      
      if rowsAffected > 0
        then return NoContent
        else throwError err404 { errBody = stringToLBS "Reservation not found or already released" }

    createTransactionHandler :: Transaction -> Handler Transaction
    createTransactionHandler transaction = do
      liftIO $ putStrLn "Handling POST /transaction request"
      liftIO $ putStrLn $ "Creating transaction: " ++ show (transactionId transaction)
      createdTransaction <- liftIO $ createTransaction pool transaction
      liftIO $ putStrLn "Transaction created successfully"
      return createdTransaction

    updateTransactionHandler :: UUID -> Transaction -> Handler Transaction
    updateTransactionHandler txId transaction = do
      liftIO $ putStrLn $ "Handling PUT /transaction/" ++ show txId ++ " request"
      updatedTransaction <- liftIO $ updateTransaction pool txId transaction
      liftIO $ putStrLn "Transaction updated successfully"
      return updatedTransaction

    voidTransactionHandler :: UUID -> Text -> Handler Transaction
    voidTransactionHandler txId reason = do
      liftIO $ putStrLn $ "Handling POST /transaction/void/" ++ show txId ++ " request"
      voidedTransaction <- liftIO $ voidTransaction pool txId reason
      liftIO $ putStrLn "Transaction voided successfully"
      return voidedTransaction

    refundTransactionHandler :: UUID -> Text -> Handler Transaction
    refundTransactionHandler txId reason = do
      liftIO $ putStrLn $ "Handling POST /transaction/refund/" ++ show txId ++ " request"
      refundedTransaction <- liftIO $ refundTransaction pool txId reason
      liftIO $ putStrLn "Transaction refunded successfully"
      return refundedTransaction

    addTransactionItemHandler :: TransactionItem -> Handler TransactionItem
    addTransactionItemHandler item = do
      liftIO $ putStrLn "Handling POST /transaction/item request"
      addedItem <- liftIO $ addTransactionItem pool item
      liftIO $ putStrLn "Transaction item added successfully"
      return addedItem

    removeTransactionItemHandler :: UUID -> Handler NoContent
    removeTransactionItemHandler itemId = do
      liftIO $ putStrLn $ "Handling DELETE /transaction/item/" ++ show itemId ++ " request"
      liftIO $ deleteTransactionItem pool itemId
      liftIO $ putStrLn "Transaction item deleted successfully"
      return NoContent

    addPaymentTransactionHandler :: PaymentTransaction -> Handler PaymentTransaction
    addPaymentTransactionHandler payment = do
      liftIO $ putStrLn "Handling POST /transaction/payment request"
      addedPayment <- liftIO $ addPaymentTransaction pool payment
      liftIO $ putStrLn "Payment transaction added successfully"
      return addedPayment

    removePaymentTransactionHandler :: UUID -> Handler NoContent
    removePaymentTransactionHandler pymtId = do
      liftIO $ putStrLn $ "Handling DELETE /transaction/payment/" ++ show pymtId ++ " request"
      liftIO $ deletePaymentTransaction pool pymtId
      liftIO $ putStrLn "Payment transaction deleted successfully"
      return NoContent

    finalizeTransactionHandler :: UUID -> Handler Transaction
    finalizeTransactionHandler txId = do
      liftIO $ putStrLn $ "Handling POST /transaction/finalize/" ++ show txId ++ " request"
      finalizedTransaction <- liftIO $ finalizeTransaction pool txId
      liftIO $ putStrLn "Transaction finalized successfully"
      return finalizedTransaction

registerServer :: Pool Connection -> Server RegisterAPI
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
      registers <- liftIO $ getAllRegisters pool
      return registers

    getRegisterHandler :: UUID -> Handler Register
    getRegisterHandler regId = do
      liftIO $ putStrLn $ "Handling GET /register/" ++ show regId ++ " request"
      maybeRegister <- liftIO $ getRegisterById pool regId
      case maybeRegister of
        Just register -> return register
        Nothing -> throwError err404 { errBody = stringToLBS "Register not found" }

    createRegisterHandler :: Register -> Handler Register
    createRegisterHandler register = do
      liftIO $ putStrLn "Handling POST /register request"
      createdRegister <- liftIO $ createRegister pool register
      return createdRegister

    updateRegisterHandler :: UUID -> Register -> Handler Register
    updateRegisterHandler regId register = do
      liftIO $ putStrLn $ "Handling PUT /register/" ++ show regId ++ " request"
      updatedRegister <- liftIO $ updateRegister pool regId register
      return updatedRegister

    openRegisterHandler :: UUID -> OpenRegisterRequest -> Handler Register
    openRegisterHandler regId request = do
      liftIO $ putStrLn $ "Handling POST /register/open/" ++ show regId ++ " request"
      openedRegister <- liftIO $ openRegister pool regId request
      return openedRegister

    closeRegisterHandler :: UUID -> CloseRegisterRequest -> Handler CloseRegisterResult
    closeRegisterHandler regId request = do
      liftIO $ putStrLn $ "Handling POST /register/close/" ++ show regId ++ " request"
      closeResult <- liftIO $ closeRegister pool regId request
      return closeResult

ledgerServer :: Pool Connection -> Server LedgerAPI
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

complianceServer :: Pool Connection -> Server ComplianceAPI
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

posServerImpl :: Pool Connection -> Server PosAPI
posServerImpl pool =
  transactionServer pool
    :<|> registerServer pool
    :<|> ledgerServer pool
    :<|> complianceServer pool