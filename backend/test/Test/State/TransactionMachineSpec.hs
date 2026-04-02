{-# LANGUAGE GADTs               #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.State.TransactionMachineSpec (spec) where

import Test.Hspec
import Data.UUID (UUID)
import Data.Time (UTCTime)

import State.TransactionMachine
import qualified Types.Transaction as T
import Types.Location (LocationId (..))

-- ── fixtures ──────────────────────────────────────────────────────────────────

testUUID :: UUID
testUUID = read "33333333-3333-3333-3333-333333333333"

testUUID2 :: UUID
testUUID2 = read "44444444-4444-4444-4444-444444444444"

testUUID3 :: UUID
testUUID3 = read "55555555-5555-5555-5555-555555555555"

testTime :: UTCTime
testTime = read "2024-06-15 10:30:00 UTC"

baseTx :: T.TransactionStatus -> T.Transaction
baseTx status = T.Transaction
  { T.transactionId                     = testUUID
  , T.transactionStatus                 = status
  , T.transactionCreated                = testTime
  , T.transactionCompleted              = Nothing
  , T.transactionCustomerId             = Nothing
  , T.transactionEmployeeId             = testUUID2
  , T.transactionRegisterId             = testUUID2
  , T.transactionLocationId             = LocationId testUUID2
  , T.transactionItems                  = []
  , T.transactionPayments               = []
  , T.transactionSubtotal               = 0
  , T.transactionDiscountTotal          = 0
  , T.transactionTaxTotal               = 0
  , T.transactionTotal                  = 0
  , T.transactionType                   = T.Sale
  , T.transactionIsVoided               = False
  , T.transactionVoidReason             = Nothing
  , T.transactionIsRefunded             = False
  , T.transactionRefundReason           = Nothing
  , T.transactionReferenceTransactionId = Nothing
  , T.transactionNotes                  = Nothing
  }

testItem :: T.TransactionItem
testItem = T.TransactionItem
  { T.transactionItemId            = testUUID2
  , T.transactionItemTransactionId = testUUID
  , T.transactionItemMenuItemSku   = read "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  , T.transactionItemQuantity      = 1
  , T.transactionItemPricePerUnit  = 1000
  , T.transactionItemDiscounts     = []
  , T.transactionItemTaxes         = []
  , T.transactionItemSubtotal      = 1000
  , T.transactionItemTotal         = 1080
  }

testPayment :: T.PaymentTransaction
testPayment = T.PaymentTransaction
  { T.paymentId                = testUUID2
  , T.paymentTransactionId     = testUUID
  , T.paymentMethod            = T.Cash
  , T.paymentAmount            = 1080
  , T.paymentTendered          = 2000
  , T.paymentChange            = 920
  , T.paymentReference         = Nothing
  , T.paymentApproved          = True
  , T.paymentAuthorizationCode = Nothing
  }

-- ── helpers ───────────────────────────────────────────────────────────────────

vertexOf :: SomeTxState -> TxVertex
vertexOf (SomeTxState sv _) = case sv of
  STxCreated    -> TxCreated
  STxInProgress -> TxInProgress
  STxCompleted  -> TxCompleted
  STxVoided     -> TxVoided
  STxRefunded   -> TxRefunded

-- ── spec ──────────────────────────────────────────────────────────────────────

spec :: Spec
spec = describe "State.TransactionMachine" $ do

  describe "fromTransaction" $ do
    it "Created status → TxCreated vertex" $
      vertexOf (fromTransaction (baseTx T.Created)) `shouldBe` TxCreated
    it "InProgress status → TxInProgress vertex" $
      vertexOf (fromTransaction (baseTx T.InProgress)) `shouldBe` TxInProgress
    it "Completed status → TxCompleted vertex" $
      vertexOf (fromTransaction (baseTx T.Completed)) `shouldBe` TxCompleted
    it "Voided status → TxVoided vertex" $
      vertexOf (fromTransaction (baseTx T.Voided)) `shouldBe` TxVoided
    it "Refunded status → TxRefunded vertex" $
      vertexOf (fromTransaction (baseTx T.Refunded)) `shouldBe` TxRefunded


  describe "event emission" $ do
    -- Every pattern uses `case` so the match is exhaustive and GHC does not
    -- emit -Wincomplete-uni-patterns.

    it "AddItemCmd on Created emits ItemAdded" $ do
      let (evt, _) = runTxCommand (fromTransaction (baseTx T.Created)) (AddItemCmd testItem)
      case evt of
        ItemAdded item -> T.transactionItemId item `shouldBe` T.transactionItemId testItem
        _              -> expectationFailure $ "Expected ItemAdded, got: " ++ show evt

    it "RemoveItemCmd on InProgress emits ItemRemoved" $ do
      let (evt, _) = runTxCommand (fromTransaction (baseTx T.InProgress)) (RemoveItemCmd testUUID2)
      case evt of
        ItemRemoved uid -> uid `shouldBe` testUUID2
        _               -> expectationFailure $ "Expected ItemRemoved, got: " ++ show evt

    it "AddPaymentCmd on InProgress emits PaymentAdded" $ do
      let (evt, _) = runTxCommand (fromTransaction (baseTx T.InProgress)) (AddPaymentCmd testPayment)
      case evt of
        PaymentAdded p -> T.paymentId p `shouldBe` T.paymentId testPayment
        _              -> expectationFailure $ "Expected PaymentAdded, got: " ++ show evt

    it "RemovePaymentCmd on InProgress emits PaymentRemoved" $ do
      let (evt, _) = runTxCommand (fromTransaction (baseTx T.InProgress)) (RemovePaymentCmd testUUID2)
      case evt of
        PaymentRemoved uid -> uid `shouldBe` testUUID2
        _                  -> expectationFailure $ "Expected PaymentRemoved, got: " ++ show evt

    it "VoidCmd on InProgress emits TxWasVoided with the reason" $ do
      let (evt, _) = runTxCommand (fromTransaction (baseTx T.InProgress)) (VoidCmd "customer request")
      case evt of
        TxWasVoided reason -> reason `shouldBe` "customer request"
        _                  -> expectationFailure $ "Expected TxWasVoided, got: " ++ show evt

    it "RefundCmd on Completed emits TxWasRefunded with reason and id" $ do
      let (evt, _) = runTxCommand (fromTransaction (baseTx T.Completed)) (RefundCmd "defective" testUUID3)
      case evt of
        TxWasRefunded reason uid -> do
          reason `shouldBe` "defective"
          uid    `shouldBe` testUUID3
        _ -> expectationFailure $ "Expected TxWasRefunded, got: " ++ show evt

    it "FinalizeCmd on InProgress emits TxFinalized" $ do
      let (evt, _) = runTxCommand (fromTransaction (baseTx T.InProgress)) FinalizeCmd
      case evt of
        TxFinalized -> pure ()
        _           -> expectationFailure $ "Expected TxFinalized, got: " ++ show evt


  describe "state transitions" $ do

    it "AddItemCmd from Created → TxInProgress" $ do
      let (_, next) = runTxCommand (fromTransaction (baseTx T.Created)) (AddItemCmd testItem)
      vertexOf next `shouldBe` TxInProgress

    it "AddItemCmd from InProgress stays TxInProgress" $ do
      let (_, next) = runTxCommand (fromTransaction (baseTx T.InProgress)) (AddItemCmd testItem)
      vertexOf next `shouldBe` TxInProgress

    it "FinalizeCmd from InProgress → TxCompleted" $ do
      let (_, next) = runTxCommand (fromTransaction (baseTx T.InProgress)) FinalizeCmd
      vertexOf next `shouldBe` TxCompleted

    it "VoidCmd from Created → TxVoided" $ do
      let (_, next) = runTxCommand (fromTransaction (baseTx T.Created)) (VoidCmd "test")
      vertexOf next `shouldBe` TxVoided

    it "VoidCmd from InProgress → TxVoided" $ do
      let (_, next) = runTxCommand (fromTransaction (baseTx T.InProgress)) (VoidCmd "test")
      vertexOf next `shouldBe` TxVoided

    it "VoidCmd from Completed → TxVoided" $ do
      let (_, next) = runTxCommand (fromTransaction (baseTx T.Completed)) (VoidCmd "test")
      vertexOf next `shouldBe` TxVoided

    it "RefundCmd from Completed → TxRefunded" $ do
      let (_, next) = runTxCommand (fromTransaction (baseTx T.Completed)) (RefundCmd "defective" testUUID3)
      vertexOf next `shouldBe` TxRefunded


  describe "invalid commands" $ do

    it "RemoveItemCmd from Created emits InvalidTxCommand" $ do
      let (evt, _) = runTxCommand (fromTransaction (baseTx T.Created)) (RemoveItemCmd testUUID2)
      case evt of
        InvalidTxCommand _ -> pure ()
        _                  -> expectationFailure $ "Expected InvalidTxCommand, got: " ++ show evt

    it "FinalizeCmd from Created emits InvalidTxCommand" $ do
      let (evt, _) = runTxCommand (fromTransaction (baseTx T.Created)) FinalizeCmd
      case evt of
        InvalidTxCommand _ -> pure ()
        _                  -> expectationFailure $ "Expected InvalidTxCommand, got: " ++ show evt

    it "RefundCmd from InProgress emits InvalidTxCommand" $ do
      let (evt, _) = runTxCommand (fromTransaction (baseTx T.InProgress)) (RefundCmd "x" testUUID3)
      case evt of
        InvalidTxCommand _ -> pure ()
        _                  -> expectationFailure $ "Expected InvalidTxCommand, got: " ++ show evt

    it "AddItemCmd on Voided emits InvalidTxCommand" $ do
      let (evt, _) = runTxCommand (fromTransaction (baseTx T.Voided)) (AddItemCmd testItem)
      case evt of
        InvalidTxCommand _ -> pure ()
        _                  -> expectationFailure $ "Expected InvalidTxCommand, got: " ++ show evt

    it "AddItemCmd on Refunded emits InvalidTxCommand" $ do
      let (evt, _) = runTxCommand (fromTransaction (baseTx T.Refunded)) (AddItemCmd testItem)
      case evt of
        InvalidTxCommand _ -> pure ()
        _                  -> expectationFailure $ "Expected InvalidTxCommand, got: " ++ show evt

    it "Voided stays TxVoided on any command" $ do
      let (_, next) = runTxCommand (fromTransaction (baseTx T.Voided)) (AddItemCmd testItem)
      vertexOf next `shouldBe` TxVoided

    it "Refunded stays TxRefunded on any command" $ do
      let (_, next) = runTxCommand (fromTransaction (baseTx T.Refunded)) (AddItemCmd testItem)
      vertexOf next `shouldBe` TxRefunded


  describe "void sets transaction fields" $ do

    it "VoidCmd sets transactionIsVoided = True in resulting state" $ do
      let (_, next) = runTxCommand (fromTransaction (baseTx T.InProgress)) (VoidCmd "fraud")
      case next of
        SomeTxState _ (VoidedState tx) -> T.transactionIsVoided tx `shouldBe` True
        _                              -> expectationFailure "Expected VoidedState"

    it "VoidCmd stores the void reason" $ do
      let (_, next) = runTxCommand (fromTransaction (baseTx T.InProgress)) (VoidCmd "fraud")
      case next of
        SomeTxState _ (VoidedState tx) -> T.transactionVoidReason tx `shouldBe` Just "fraud"
        _                              -> expectationFailure "Expected VoidedState"