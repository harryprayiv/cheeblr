{-# LANGUAGE GADTs             #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.Props.StateMachineSpec (spec) where

import           Data.Time.Clock (UTCTime)
import           Data.UUID (UUID)
import           Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import           Test.Hspec
import           Test.Hspec.Hedgehog (hedgehog)

import           API.Transaction (Register (..))
import           State.RegisterMachine
import           State.TransactionMachine
import           Test.Gen
import qualified Types.Transaction as T
import Types.Location (LocationId (..))

fixedUUID :: UUID
fixedUUID = read "33333333-3333-3333-3333-333333333333"

fixedUUID2 :: UUID
fixedUUID2 = read "44444444-4444-4444-4444-444444444444"

fixedTime :: UTCTime
fixedTime = read "2024-01-01 00:00:00 UTC"

baseTx :: T.TransactionStatus -> T.Transaction
baseTx status = T.Transaction
  { T.transactionId                     = fixedUUID
  , T.transactionStatus                 = status
  , T.transactionCreated                = fixedTime
  , T.transactionCompleted              = Nothing
  , T.transactionCustomerId             = Nothing
  , T.transactionEmployeeId             = fixedUUID2
  , T.transactionRegisterId             = fixedUUID2
  , T.transactionLocationId             = LocationId fixedUUID2
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

baseReg :: Bool -> Register
baseReg isOpen = Register
  { registerId                   = fixedUUID
  , registerName                 = "Test"
  , registerLocationId           = LocationId fixedUUID2
  , registerIsOpen               = isOpen
  , registerCurrentDrawerAmount  = 50000
  , registerExpectedDrawerAmount = 50000
  , registerOpenedAt             = Nothing
  , registerOpenedBy             = Nothing
  , registerLastTransactionTime  = Nothing
  }

txVertexOf :: SomeTxState -> TxVertex
txVertexOf (SomeTxState sv _) = case sv of
  STxCreated    -> TxCreated
  STxInProgress -> TxInProgress
  STxCompleted  -> TxCompleted
  STxVoided     -> TxVoided
  STxRefunded   -> TxRefunded

regVertexOf :: SomeRegState -> RegVertex
regVertexOf (SomeRegState sv _) = case sv of
  SRegClosed -> RegClosed
  SRegOpen   -> RegOpen

genTxCommand :: Gen TxCommand
genTxCommand = Gen.choice
  [ AddItemCmd       <$> genTransactionItem
  , RemoveItemCmd    <$> genUUID
  , AddPaymentCmd    <$> genPaymentTransaction
  , RemovePaymentCmd <$> genUUID
  , pure FinalizeCmd
  , VoidCmd          <$> genText
  , RefundCmd        <$> genText <*> genUUID
  ]

someTxState :: T.TransactionStatus -> SomeTxState
someTxState s = fromTransaction (baseTx s)

spec :: Spec
spec = describe "Props.StateMachine" $ do

  describe "TxMachine: Voided is a sink" $ do
    it "any command produces InvalidTxCommand" $ hedgehog $ do
      cmd <- forAll genTxCommand
      let (evt, _) = runTxCommand (someTxState T.Voided) cmd
      case evt of
        InvalidTxCommand _ -> success
        _                  -> footnoteShow evt >> failure

    it "any command leaves vertex at TxVoided" $ hedgehog $ do
      cmd <- forAll genTxCommand
      let (_, next) = runTxCommand (someTxState T.Voided) cmd
      txVertexOf next === TxVoided

  describe "TxMachine: Refunded is a sink" $ do
    it "any command produces InvalidTxCommand" $ hedgehog $ do
      cmd <- forAll genTxCommand
      let (evt, _) = runTxCommand (someTxState T.Refunded) cmd
      case evt of
        InvalidTxCommand _ -> success
        _                  -> footnoteShow evt >> failure

    it "any command leaves vertex at TxRefunded" $ hedgehog $ do
      cmd <- forAll genTxCommand
      let (_, next) = runTxCommand (someTxState T.Refunded) cmd
      txVertexOf next === TxRefunded

  describe "TxMachine: VoidCmd always voids from live states" $ do
    it "VoidCmd from Created yields TxVoided" $ hedgehog $ do
      reason <- forAll genText
      let (_, next) = runTxCommand (someTxState T.Created) (VoidCmd reason)
      txVertexOf next === TxVoided

    it "VoidCmd from InProgress yields TxVoided" $ hedgehog $ do
      reason <- forAll genText
      let (_, next) = runTxCommand (someTxState T.InProgress) (VoidCmd reason)
      txVertexOf next === TxVoided

    it "VoidCmd from Completed yields TxVoided" $ hedgehog $ do
      reason <- forAll genText
      let (_, next) = runTxCommand (someTxState T.Completed) (VoidCmd reason)
      txVertexOf next === TxVoided

  describe "TxMachine: void payload is recorded" $ do
    it "void reason stored in resulting state" $ hedgehog $ do
      reason <- forAll genText
      let (_, next) = runTxCommand (someTxState T.InProgress) (VoidCmd reason)
      case next of
        SomeTxState _ (VoidedState tx) -> T.transactionVoidReason tx === Just reason
        _                              -> footnote "Expected VoidedState" >> failure

    it "transactionIsVoided set to True" $ hedgehog $ do
      reason <- forAll genText
      let (_, next) = runTxCommand (someTxState T.InProgress) (VoidCmd reason)
      case next of
        SomeTxState _ (VoidedState tx) -> T.transactionIsVoided tx === True
        _                              -> footnote "Expected VoidedState" >> failure

  describe "RegisterMachine: OpenRegCmd on open register is rejected" $ do
    it "any OpenRegCmd emits InvalidRegCommand" $ hedgehog $ do
      empId <- forAll genUUID
      cash  <- forAll $ Gen.int (Range.linear 0 10000000)
      let st       = SomeRegState SRegOpen (OpenState (baseReg True))
          (evt, _) = runRegCommand st (OpenRegCmd empId cash)
      case evt of
        InvalidRegCommand _ -> success
        _                   -> footnoteShow evt >> failure

    it "vertex stays RegOpen" $ hedgehog $ do
      empId <- forAll genUUID
      cash  <- forAll $ Gen.int (Range.linear 0 10000000)
      let st        = SomeRegState SRegOpen (OpenState (baseReg True))
          (_, next) = runRegCommand st (OpenRegCmd empId cash)
      regVertexOf next === RegOpen

  describe "RegisterMachine: CloseRegCmd on closed register is rejected" $ do
    it "any CloseRegCmd emits InvalidRegCommand" $ hedgehog $ do
      empId <- forAll genUUID
      cash  <- forAll $ Gen.int (Range.linear 0 10000000)
      let st       = SomeRegState SRegClosed (ClosedState (baseReg False))
          (evt, _) = runRegCommand st (CloseRegCmd empId cash)
      case evt of
        InvalidRegCommand _ -> success
        _                   -> footnoteShow evt >> failure

    it "vertex stays RegClosed" $ hedgehog $ do
      empId <- forAll genUUID
      cash  <- forAll $ Gen.int (Range.linear 0 10000000)
      let st        = SomeRegState SRegClosed (ClosedState (baseReg False))
          (_, next) = runRegCommand st (CloseRegCmd empId cash)
      regVertexOf next === RegClosed

  describe "RegisterMachine: CloseRegCmd variance law" $ do
    it "variance == expected - counted for all inputs" $ hedgehog $ do
      expected <- forAll $ Gen.int (Range.linear 0 10000000)
      counted  <- forAll $ Gen.int (Range.linear 0 10000000)
      empId    <- forAll genUUID
      let reg      = (baseReg True) { registerExpectedDrawerAmount = expected }
          st       = SomeRegState SRegOpen (OpenState reg)
          (evt, _) = runRegCommand st (CloseRegCmd empId counted)
      case evt of
        RegWasClosed _ variance -> variance === expected - counted
        _                       -> footnoteShow evt >> failure