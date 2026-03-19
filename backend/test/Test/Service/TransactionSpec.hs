{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.Service.TransactionSpec (spec) where

import Control.Monad (void)
import qualified Data.Map.Strict as Map
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Effectful (Eff, IOE, runEff)
import Effectful.Error.Static (Error, runErrorNoCallStack)
import Servant (ServerError (..))
import Test.Hspec

import Effect.Clock (Clock, runClockPure)
import Effect.GenUUID (GenUUID, runGenUUIDPure)
import Effect.TransactionDb
import qualified Service.Transaction as Svc
import Types.Transaction

txUUID, itemUUID, pymtUUID, skuUUID, empUUID, regUUID, locUUID :: UUID
txUUID   = read "11111111-1111-1111-1111-111111111111"
itemUUID = read "22222222-2222-2222-2222-222222222222"
pymtUUID = read "33333333-3333-3333-3333-333333333333"
skuUUID  = read "44444444-4444-4444-4444-444444444444"
empUUID  = read "55555555-5555-5555-5555-555555555555"
regUUID  = read "66666666-6666-6666-6666-666666666666"
locUUID  = read "77777777-7777-7777-7777-777777777777"

freshUUID :: UUID
freshUUID = read "88888888-8888-8888-8888-888888888888"

-- Infinite supply of distinct deterministic UUIDs for the pure interpreter.
uuidSupply :: [UUID]
uuidSupply =
  [ read "a0000000-0000-0000-0000-000000000001"
  , read "a0000000-0000-0000-0000-000000000002"
  , read "a0000000-0000-0000-0000-000000000003"
  , read "a0000000-0000-0000-0000-000000000004"
  , read "a0000000-0000-0000-0000-000000000005"
  , read "a0000000-0000-0000-0000-000000000006"
  , read "a0000000-0000-0000-0000-000000000007"
  , read "a0000000-0000-0000-0000-000000000008"
  , read "a0000000-0000-0000-0000-000000000009"
  , read "a0000000-0000-0000-0000-000000000010"
  ] <> [ read $ "b0000000-0000-0000-0000-" <> pad n | n <- [1..] :: [Int] ]
  where
    pad n = replicate (12 - length (show n)) '0' <> show n

testTime :: UTCTime
testTime = read "2024-06-15 10:00:00 UTC"

mkTx :: TransactionStatus -> Transaction
mkTx status = Transaction
  { transactionId                     = txUUID
  , transactionStatus                 = status
  , transactionCreated                = testTime
  , transactionCompleted              = Nothing
  , transactionCustomerId             = Nothing
  , transactionEmployeeId             = empUUID
  , transactionRegisterId             = regUUID
  , transactionLocationId             = locUUID
  , transactionItems                  = []
  , transactionPayments               = []
  , transactionSubtotal               = 0
  , transactionDiscountTotal          = 0
  , transactionTaxTotal               = 0
  , transactionTotal                  = 0
  , transactionType                   = Sale
  , transactionIsVoided               = False
  , transactionVoidReason             = Nothing
  , transactionIsRefunded             = False
  , transactionRefundReason           = Nothing
  , transactionReferenceTransactionId = Nothing
  , transactionNotes                  = Nothing
  }

testItem :: TransactionItem
testItem = TransactionItem
  { transactionItemId            = itemUUID
  , transactionItemTransactionId = txUUID
  , transactionItemMenuItemSku   = skuUUID
  , transactionItemQuantity      = 1
  , transactionItemPricePerUnit  = 1000
  , transactionItemDiscounts     = []
  , transactionItemTaxes         = []
  , transactionItemSubtotal      = 1000
  , transactionItemTotal         = 1000
  }

testPayment :: PaymentTransaction
testPayment = PaymentTransaction
  { paymentId                = pymtUUID
  , paymentTransactionId     = txUUID
  , paymentMethod            = Cash
  , paymentAmount            = 1000
  , paymentTendered          = 1000
  , paymentChange            = 0
  , paymentReference         = Nothing
  , paymentApproved          = True
  , paymentAuthorizationCode = Nothing
  }

storeWith :: TransactionStatus -> TxStore
storeWith status = emptyTxStore
  { tsTxs       = Map.singleton txUUID (mkTx status)
  , tsInventory = Map.singleton skuUUID 10
  }

storeWithItem :: TransactionStatus -> TxStore
storeWithItem status =
  let tx = (mkTx status) { transactionItems = [testItem] }
  in emptyTxStore
    { tsTxs      = Map.singleton txUUID tx
    , tsItemToTx = Map.singleton itemUUID txUUID
    , tsInventory = Map.singleton skuUUID 10
    }

storeWithPayment :: TransactionStatus -> TxStore
storeWithPayment status =
  let tx = (mkTx status) { transactionPayments = [testPayment] }
  in emptyTxStore
    { tsTxs         = Map.singleton txUUID tx
    , tsPaymentToTx = Map.singleton pymtUUID txUUID
    , tsInventory   = Map.singleton skuUUID 10
    }

type TestEffs = '[TransactionDb, Clock, GenUUID, Error ServerError, IOE]

-- Interpreter order: TransactionDb innermost so GenUUID and Clock remain
-- in scope when the pure DB handler dispatches nextUUID / currentTime.
-- Result nesting: Either ServerError ((a, TxStore), [UUID])
runTest
  :: TxStore
  -> Eff TestEffs a
  -> IO (Either ServerError a)
runTest store action =
  fmap (fmap (fst . fst)) $
  runEff
  . runErrorNoCallStack @ServerError
  . runGenUUIDPure uuidSupply
  . runClockPure testTime
  . runTransactionDbPure store
  $ action

shouldSucceed :: IO (Either ServerError a) -> IO a
shouldSucceed io = do
  result <- io
  case result of
    Left err -> do
      expectationFailure $ "Expected success but got HTTP " <> show (errHTTPCode err)
      error "unreachable"
    Right a -> pure a

shouldFailWith :: Int -> IO (Either ServerError a) -> IO ()
shouldFailWith code io = do
  result <- io
  case result of
    Left err -> errHTTPCode err `shouldBe` code
    Right _  -> expectationFailure $ "Expected HTTP " <> show code <> " but got success"

spec :: Spec
spec = describe "Service.Transaction (pure interpreter)" $ do

  describe "addItem — state machine guards" $ do
    it "succeeds from Created (transitions tx to InProgress)" $ do
      item <- shouldSucceed $ runTest (storeWith Created) (Svc.addItem testItem)
      transactionItemId item `shouldBe` itemUUID

    it "succeeds from InProgress" $ do
      let item2 = testItem { transactionItemId = freshUUID, transactionItemMenuItemSku = skuUUID }
      void $ shouldSucceed $ runTest (storeWith InProgress) (Svc.addItem item2)

    it "rejects from Completed with 409" $
      shouldFailWith 409 $ runTest (storeWith Completed) (Svc.addItem testItem)

    it "rejects from Voided with 409" $
      shouldFailWith 409 $ runTest (storeWith Voided) (Svc.addItem testItem)

    it "rejects from Refunded with 409" $
      shouldFailWith 409 $ runTest (storeWith Refunded) (Svc.addItem testItem)

  describe "addItem — DB-level errors" $ do
    it "returns 404 for non-existent transaction" $
      shouldFailWith 404 $ runTest emptyTxStore (Svc.addItem testItem)

    it "returns 404 when SKU not in inventory" $
      shouldFailWith 404 $ runTest (storeWith Created) $
        Svc.addItem testItem { transactionItemMenuItemSku = read "ffffffff-ffff-ffff-ffff-ffffffffffff" }

    it "returns 400 when insufficient inventory" $ do
      let store = (storeWith Created) { tsInventory = Map.singleton skuUUID 0 }
      shouldFailWith 400 $ runTest store (Svc.addItem testItem)

  describe "removeItem — state machine guards" $ do
    it "succeeds from InProgress" $
      void $ shouldSucceed $ runTest (storeWithItem InProgress) (Svc.removeItem itemUUID)

    it "rejects from Completed with 409" $
      shouldFailWith 409 $ runTest (storeWithItem Completed) (Svc.removeItem itemUUID)

    it "rejects from Voided with 409" $
      shouldFailWith 409 $ runTest (storeWithItem Voided) (Svc.removeItem itemUUID)

    it "returns 404 for non-existent item" $
      shouldFailWith 404 $ runTest (storeWith InProgress) (Svc.removeItem itemUUID)

  describe "addPayment — state machine guards" $ do
    it "succeeds from InProgress" $ do
      p <- shouldSucceed $ runTest (storeWith InProgress) (Svc.addPayment testPayment)
      paymentId p `shouldBe` pymtUUID

    it "rejects from Created with 409" $
      shouldFailWith 409 $ runTest (storeWith Created) (Svc.addPayment testPayment)

    it "rejects from Completed with 409" $
      shouldFailWith 409 $ runTest (storeWith Completed) (Svc.addPayment testPayment)

  describe "removePayment — state machine guards" $ do
    it "succeeds from InProgress" $
      void $ shouldSucceed $ runTest (storeWithPayment InProgress) (Svc.removePayment pymtUUID)

    it "rejects from Completed with 409" $
      shouldFailWith 409 $ runTest (storeWithPayment Completed) (Svc.removePayment pymtUUID)

    it "returns 404 for non-existent payment" $
      shouldFailWith 404 $ runTest (storeWith InProgress) (Svc.removePayment pymtUUID)

  describe "finalizeTx — state machine guards" $ do
    it "succeeds from InProgress" $ do
      tx <- shouldSucceed $ runTest (storeWith InProgress) (Svc.finalizeTx txUUID)
      transactionStatus tx `shouldBe` Completed

    it "rejects from Created with 409" $
      shouldFailWith 409 $ runTest (storeWith Created) (Svc.finalizeTx txUUID)

    it "rejects from Voided with 409" $
      shouldFailWith 409 $ runTest (storeWith Voided) (Svc.finalizeTx txUUID)

    it "returns 404 for non-existent transaction" $
      shouldFailWith 404 $ runTest emptyTxStore (Svc.finalizeTx txUUID)

  describe "voidTx — state machine guards" $ do
    it "succeeds from Created" $ do
      tx <- shouldSucceed $ runTest (storeWith Created) (Svc.voidTx txUUID "test reason")
      transactionStatus tx `shouldBe` Voided
      transactionIsVoided tx `shouldBe` True
      transactionVoidReason tx `shouldBe` Just "test reason"

    it "succeeds from InProgress" $ do
      tx <- shouldSucceed $ runTest (storeWith InProgress) (Svc.voidTx txUUID "fraud")
      transactionIsVoided tx `shouldBe` True

    it "succeeds from Completed" $ do
      tx <- shouldSucceed $ runTest (storeWith Completed) (Svc.voidTx txUUID "error")
      transactionStatus tx `shouldBe` Voided

    it "rejects from Voided with 409" $
      shouldFailWith 409 $ runTest (storeWith Voided) (Svc.voidTx txUUID "again")

    it "rejects from Refunded with 409" $
      shouldFailWith 409 $ runTest (storeWith Refunded) (Svc.voidTx txUUID "again")

    it "returns 404 for non-existent transaction" $
      shouldFailWith 404 $ runTest emptyTxStore (Svc.voidTx txUUID "reason")

  describe "refundTx — state machine guards" $ do
    it "succeeds from Completed" $ do
      tx <- shouldSucceed $ runTest (storeWith Completed) (Svc.refundTx txUUID "defective")
      transactionType tx `shouldBe` Return

    it "rejects from InProgress with 409" $
      shouldFailWith 409 $ runTest (storeWith InProgress) (Svc.refundTx txUUID "early")

    it "rejects from Created with 409" $
      shouldFailWith 409 $ runTest (storeWith Created) (Svc.refundTx txUUID "early")

    it "rejects from Voided with 409" $
      shouldFailWith 409 $ runTest (storeWith Voided) (Svc.refundTx txUUID "late")

    it "returns 404 for non-existent transaction" $
      shouldFailWith 404 $ runTest emptyTxStore (Svc.refundTx txUUID "reason")

  describe "store state after successful operations" $ do
    it "addItem reserves inventory" $ do
      let store  = (storeWith Created) { tsInventory = Map.singleton skuUUID 5 }
          action = do
            _ <- Svc.addItem testItem
            getInventoryAvailability skuUUID
      result <- shouldSucceed $ runTest store action
      case result of
        Just (_, reserved) -> reserved `shouldBe` 1
        Nothing            -> expectationFailure "Expected availability"

    it "two addItem calls consume two units" $ do
      let item2  = testItem { transactionItemId = freshUUID }
          store  = (storeWith Created) { tsInventory = Map.singleton skuUUID 5 }
          action = do
            _ <- Svc.addItem testItem
            _ <- Svc.addItem item2
            getInventoryAvailability skuUUID
      result <- shouldSucceed $ runTest store action
      case result of
        Just (_, reserved) -> reserved `shouldBe` 2
        Nothing            -> expectationFailure "Expected availability"

    it "addItem followed by removeItem restores reserved count" $ do
      let store  = (storeWith Created) { tsInventory = Map.singleton skuUUID 5 }
          action = do
            _ <- Svc.addItem testItem
            Svc.removeItem itemUUID
            getInventoryAvailability skuUUID
      result <- shouldSucceed $ runTest store action
      case result of
        Just (_, reserved) -> reserved `shouldBe` 0
        Nothing            -> expectationFailure "Expected availability"