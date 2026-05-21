{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Test.Service.TransactionSpec (spec) where

import Control.Monad (void)
import Data.IORef (newIORef, readIORef)
import qualified Data.Map.Strict as Map
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Effectful (Eff, IOE, runEff)
import Effectful.Error.Static (Error, runErrorNoCallStack)
import Servant (ServerError (..))
import Test.Hspec

import Effect.Clock (Clock, runClockPure)
import Effect.EventEmitter
import Effect.GenUUID (GenUUID, runGenUUIDPure)
import Effect.InventoryDb (InventoryDb, runInventoryDbPure)
import Effect.StockDb (StockDb, emptyStockStore, runStockDbPure)
import Effect.TransactionDb
import qualified Service.Transaction as Svc
import Types.Events.Domain
import Types.Events
import Types.Location (LocationId (..))
import Types.Primitives.Money (refundMoneyCents, unsafeMkSaleMoney)
import Types.Primitives.Quantity (unsafeMkSaleQuantity)
import Types.Transaction
import Types.Transaction.Conversion (saleItemToLegacy, salePaymentToLegacy)
import qualified Types.Transaction.Refund as Refund
import qualified Types.Transaction.Sale as Sale
import Types.Transaction.Sale (itemId, itemMenuItemSku)

-- ---------------------------------------------------------------------------
-- Fixed UUIDs
-- ---------------------------------------------------------------------------

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
  ]
    <> [read $ "b0000000-0000-0000-0000-" <> pad n | n <- [1 ..] :: [Int]]
  where
    pad n = replicate (12 - length (show n)) '0' <> show n

testTime :: UTCTime
testTime = read "2024-06-15 10:00:00 UTC"

-- ---------------------------------------------------------------------------
-- Test fixtures
-- ---------------------------------------------------------------------------

mkTx :: TransactionStatus -> Transaction
mkTx status =
  Transaction
    { transactionId = txUUID
    , transactionStatus = status
    , transactionCreated = testTime
    , transactionCompleted = Nothing
    , transactionCustomerId = Nothing
    , transactionEmployeeId = empUUID
    , transactionRegisterId = regUUID
    , transactionLocationId = LocationId locUUID
    , transactionItems = []
    , transactionPayments = []
    , transactionSubtotal = 0
    , transactionDiscountTotal = 0
    , transactionTaxTotal = 0
    , transactionTotal = 0
    , transactionType = Sale
    , transactionIsVoided = False
    , transactionVoidReason = Nothing
    , transactionIsRefunded = False
    , transactionRefundReason = Nothing
    , transactionReferenceTransactionId = Nothing
    , transactionNotes = Nothing
    }

-- | Typed item fixture used in service-call arguments.
testSaleItem :: Sale.Item
testSaleItem =
  Sale.Item
    { itemId            = itemUUID
    , itemTransactionId = txUUID
    , itemMenuItemSku   = skuUUID
    , itemQuantity      = unsafeMkSaleQuantity 1
    , itemPricePerUnit  = unsafeMkSaleMoney 1000
    , itemDiscounts     = []
    , itemTaxes         = []
    , itemSubtotal      = unsafeMkSaleMoney 1000
    , itemTotal         = unsafeMkSaleMoney 1000
    }

-- | Legacy item used inside store fixtures. Derived from the typed one
-- so the two stay in sync.
testItem :: TransactionItem
testItem = saleItemToLegacy testSaleItem

-- | Typed payment fixture used in service-call arguments.
testSalePayment :: Sale.Payment
testSalePayment =
  Sale.Payment
    { paymentId                = pymtUUID
    , paymentTransactionId     = txUUID
    , paymentMethod            = Cash
    , paymentAmount            = unsafeMkSaleMoney 1000
    , paymentTendered          = unsafeMkSaleMoney 1000
    , paymentChange            = unsafeMkSaleMoney 0
    , paymentReference         = Nothing
    , paymentApproved          = True
    , paymentAuthorizationCode = Nothing
    }

-- | Legacy payment used inside store fixtures.
testPayment :: PaymentTransaction
testPayment = salePaymentToLegacy testSalePayment

storeWith :: TransactionStatus -> TxStore
storeWith status =
  emptyTxStore
    { tsTxs = Map.singleton txUUID (mkTx status)
    , tsInventory = Map.singleton skuUUID 10
    }

storeWithItem :: TransactionStatus -> TxStore
storeWithItem status =
  let tx = (mkTx status) {transactionItems = [testItem]}
   in emptyTxStore
        { tsTxs = Map.singleton txUUID tx
        , tsItemToTx = Map.singleton itemUUID txUUID
        , tsInventory = Map.singleton skuUUID 10
        }

storeWithPayment :: TransactionStatus -> TxStore
storeWithPayment status =
  let tx = (mkTx status) {transactionPayments = [testPayment]}
   in emptyTxStore
        { tsTxs = Map.singleton txUUID tx
        , tsPaymentToTx = Map.singleton pymtUUID txUUID
        , tsInventory = Map.singleton skuUUID 10
        }

storeWithItemAndPaymentCompleted :: TxStore
storeWithItemAndPaymentCompleted =
  let tx =
        (mkTx Completed)
          { transactionItems    = [testItem]
          , transactionPayments = [testPayment]
          , transactionSubtotal = 1000
          , transactionTotal    = 1000
          }
   in emptyTxStore
        { tsTxs          = Map.singleton txUUID tx
        , tsItemToTx     = Map.singleton itemUUID txUUID
        , tsPaymentToTx  = Map.singleton pymtUUID txUUID
        , tsInventory    = Map.singleton skuUUID 10
        }

-- ---------------------------------------------------------------------------
-- Effect stack
-- ---------------------------------------------------------------------------

type TestEffs =
  '[ TransactionDb
   , StockDb
   , InventoryDb
   , Clock
   , GenUUID
   , EventEmitter
   , Error ServerError
   , IOE
   ]

runTest :: TxStore -> Eff TestEffs a -> IO (Either ServerError a)
runTest store action =
  fmap (fmap (fst . fst . fst . fst))
    $ runEff
      . runErrorNoCallStack @ServerError
      . runEventEmitterNoop
      . runGenUUIDPure uuidSupply
      . runClockPure testTime
      . runInventoryDbPure Map.empty
      . runStockDbPure emptyStockStore
      . runTransactionDbPure store
    $ action

runTestWithEvents ::
  TxStore ->
  Eff TestEffs a ->
  IO (Either ServerError a, [DomainEvent])
runTestWithEvents store action = do
  ref <- newIORef []
  result <-
    fmap (fmap (fst . fst . fst . fst))
      $ runEff
        . runErrorNoCallStack @ServerError
        . runEventEmitterCollect ref
        . runGenUUIDPure uuidSupply
        . runClockPure testTime
        . runInventoryDbPure Map.empty
        . runStockDbPure emptyStockStore
        . runTransactionDbPure store
      $ action
  evts <- reverse <$> readIORef ref
  pure (result, evts)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

shouldSucceed :: IO (Either ServerError a) -> IO a
shouldSucceed io = do
  result <- io
  case result of
    Left err ->
      expectationFailure ("Expected success but got HTTP " <> show (errHTTPCode err))
        >> error "unreachable"
    Right a -> pure a

shouldFailWith :: Int -> IO (Either ServerError a) -> IO ()
shouldFailWith code io = do
  result <- io
  case result of
    Left err -> errHTTPCode err `shouldBe` code
    Right _  -> expectationFailure $ "Expected HTTP " <> show code <> " but got success"

-- ---------------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Service.Transaction (pure interpreter)" $ do

  describe "addItem — state machine guards" $ do
    it "succeeds from Created (transitions tx to InProgress)" $ do
      item <- shouldSucceed $ runTest (storeWith Created) (Svc.addItem testSaleItem)
      Sale.itemId item `shouldBe` itemUUID

    it "succeeds from InProgress" $ do
      let item2 = testSaleItem {itemId = freshUUID, itemMenuItemSku = skuUUID}
      void $ shouldSucceed $ runTest (storeWith InProgress) (Svc.addItem item2)

    it "rejects from Completed with 409" $
      shouldFailWith 409 $
        runTest (storeWith Completed) (Svc.addItem testSaleItem)

    it "rejects from Voided with 409" $
      shouldFailWith 409 $
        runTest (storeWith Voided) (Svc.addItem testSaleItem)

    it "rejects from Refunded with 409" $
      shouldFailWith 409 $
        runTest (storeWith Refunded) (Svc.addItem testSaleItem)

  describe "addItem — DB-level errors" $ do
    it "returns 404 for non-existent transaction" $
      shouldFailWith 404 $
        runTest emptyTxStore (Svc.addItem testSaleItem)

    it "returns 404 when SKU not in inventory" $
      shouldFailWith 404 $
        runTest (storeWith Created) $
          Svc.addItem testSaleItem {itemMenuItemSku = read "ffffffff-ffff-ffff-ffff-ffffffffffff"}

    it "returns 400 when insufficient inventory" $ do
      let store = (storeWith Created) {tsInventory = Map.singleton skuUUID 0}
      shouldFailWith 400 $ runTest store (Svc.addItem testSaleItem)

  describe "removeItem — state machine guards" $ do
    it "succeeds from InProgress" $
      void $
        shouldSucceed $
          runTest (storeWithItem InProgress) (Svc.removeItem itemUUID)

    it "rejects from Completed with 409" $
      shouldFailWith 409 $
        runTest (storeWithItem Completed) (Svc.removeItem itemUUID)

    it "rejects from Voided with 409" $
      shouldFailWith 409 $
        runTest (storeWithItem Voided) (Svc.removeItem itemUUID)

    it "returns 404 for non-existent item" $
      shouldFailWith 404 $
        runTest (storeWith InProgress) (Svc.removeItem itemUUID)

  describe "addPayment — state machine guards" $ do
    it "succeeds from InProgress" $ do
      p <- shouldSucceed $ runTest (storeWith InProgress) (Svc.addPayment testSalePayment)
      Sale.paymentId p `shouldBe` pymtUUID

    it "rejects from Created with 409" $
      shouldFailWith 409 $
        runTest (storeWith Created) (Svc.addPayment testSalePayment)

    it "rejects from Completed with 409" $
      shouldFailWith 409 $
        runTest (storeWith Completed) (Svc.addPayment testSalePayment)

  describe "removePayment — state machine guards" $ do
    it "succeeds from InProgress" $
      void $
        shouldSucceed $
          runTest (storeWithPayment InProgress) (Svc.removePayment pymtUUID)

    it "rejects from Completed with 409" $
      shouldFailWith 409 $
        runTest (storeWithPayment Completed) (Svc.removePayment pymtUUID)

    it "returns 404 for non-existent payment" $
      shouldFailWith 404 $
        runTest (storeWith InProgress) (Svc.removePayment pymtUUID)

  describe "finalizeTx — state machine guards" $ do
    it "succeeds from InProgress" $ do
      sale <- shouldSucceed $ runTest (storeWith InProgress) (Svc.finalizeTx txUUID)
      Sale.saleStatus sale `shouldBe` Completed

    it "rejects from Created with 409" $
      shouldFailWith 409 $
        runTest (storeWith Created) (Svc.finalizeTx txUUID)

    it "rejects from Voided with 409" $
      shouldFailWith 409 $
        runTest (storeWith Voided) (Svc.finalizeTx txUUID)

    it "returns 404 for non-existent transaction" $
      shouldFailWith 404 $
        runTest emptyTxStore (Svc.finalizeTx txUUID)

  describe "voidTx — state machine guards" $ do
    it "succeeds from Created" $ do
      sale <- shouldSucceed $ runTest (storeWith Created) (Svc.voidTx txUUID "test reason")
      Sale.saleStatus     sale `shouldBe` Voided
      Sale.saleIsVoided   sale `shouldBe` True
      Sale.saleVoidReason sale `shouldBe` Just "test reason"

    it "succeeds from InProgress" $ do
      sale <- shouldSucceed $ runTest (storeWith InProgress) (Svc.voidTx txUUID "fraud")
      Sale.saleIsVoided sale `shouldBe` True

    it "succeeds from Completed" $ do
      sale <- shouldSucceed $ runTest (storeWith Completed) (Svc.voidTx txUUID "error")
      Sale.saleStatus sale `shouldBe` Voided

    it "rejects from Voided with 409" $
      shouldFailWith 409 $
        runTest (storeWith Voided) (Svc.voidTx txUUID "again")

    it "rejects from Refunded with 409" $
      shouldFailWith 409 $
        runTest (storeWith Refunded) (Svc.voidTx txUUID "again")

    it "returns 404 for non-existent transaction" $
      shouldFailWith 404 $
        runTest emptyTxStore (Svc.voidTx txUUID "reason")

  describe "refundTx — state machine guards" $ do
    -- The result type is now 'Refund.RefundTransaction'; the
    -- "is this a refund?" question is settled by the type system, so
    -- we assert on the refund-specific fields instead.
    it "succeeds from Completed" $ do
      refund <- shouldSucceed $ runTest (storeWith Completed) (Svc.refundTx txUUID "defective")
      Refund.refundReason                 refund `shouldBe` "defective"
      Refund.refundReferenceTransactionId refund `shouldBe` txUUID

    it "rejects from InProgress with 409" $
      shouldFailWith 409 $
        runTest (storeWith InProgress) (Svc.refundTx txUUID "early")

    it "rejects from Created with 409" $
      shouldFailWith 409 $
        runTest (storeWith Created) (Svc.refundTx txUUID "early")

    it "rejects from Voided with 409" $
      shouldFailWith 409 $
        runTest (storeWith Voided) (Svc.refundTx txUUID "late")

    it "returns 404 for non-existent transaction" $
      shouldFailWith 404 $
        runTest emptyTxStore (Svc.refundTx txUUID "reason")

  describe "refundTx — child id safety" $ do
    it "refund items have ids distinct from the original sale's items" $ do
      refund <-
        shouldSucceed $
          runTest storeWithItemAndPaymentCompleted (Svc.refundTx txUUID "defective")
      let refundItemIds = map Refund.itemId (Refund.refundItems refund)
      length refundItemIds `shouldBe` 1
      refundItemIds `shouldSatisfy` notElem itemUUID

    it "refund payments have ids distinct from the original sale's payments" $ do
      refund <-
        shouldSucceed $
          runTest storeWithItemAndPaymentCompleted (Svc.refundTx txUUID "defective")
      let refundPymtIds = map Refund.paymentId (Refund.refundPayments refund)
      length refundPymtIds `shouldBe` 1
      refundPymtIds `shouldSatisfy` notElem pymtUUID

    it "refund items reference the refund transaction, not the original" $ do
      refund <-
        shouldSucceed $
          runTest storeWithItemAndPaymentCompleted (Svc.refundTx txUUID "defective")
      let refTxId = Refund.refundId refund
      refTxId `shouldNotBe` txUUID
      all (\i -> Refund.itemTransactionId i == refTxId) (Refund.refundItems refund)
        `shouldBe` True

    it "refund payments reference the refund transaction, not the original" $ do
      refund <-
        shouldSucceed $
          runTest storeWithItemAndPaymentCompleted (Svc.refundTx txUUID "defective")
      let refTxId = Refund.refundId refund
      all (\p -> Refund.paymentTransactionId p == refTxId) (Refund.refundPayments refund)
        `shouldBe` True

    it "refund item amounts are negated" $ do
      refund <-
        shouldSucceed $
          runTest storeWithItemAndPaymentCompleted (Svc.refundTx txUUID "defective")
      map (refundMoneyCents . Refund.itemSubtotal) (Refund.refundItems refund) `shouldBe` [-1000]
      map (refundMoneyCents . Refund.itemTotal)    (Refund.refundItems refund) `shouldBe` [-1000]

    it "refund payment amounts are negated" $ do
      refund <-
        shouldSucceed $
          runTest storeWithItemAndPaymentCompleted (Svc.refundTx txUUID "defective")
      map (refundMoneyCents . Refund.paymentAmount)   (Refund.refundPayments refund) `shouldBe` [-1000]
      map (refundMoneyCents . Refund.paymentTendered) (Refund.refundPayments refund) `shouldBe` [-1000]

  describe "store state after successful operations" $ do
    it "addItem reserves inventory" $ do
      let
        store  = (storeWith Created) {tsInventory = Map.singleton skuUUID 5}
        action = Svc.addItem testSaleItem >> getInventoryAvailability skuUUID
      result <- shouldSucceed $ runTest store action
      case result of
        Just (_, reserved) -> reserved `shouldBe` 1
        Nothing            -> expectationFailure "Expected availability"

    it "two addItem calls consume two units" $ do
      let
        item2  = testSaleItem {itemId = freshUUID}
        store  = (storeWith Created) {tsInventory = Map.singleton skuUUID 5}
        action = do
          _ <- Svc.addItem testSaleItem
          _ <- Svc.addItem item2
          getInventoryAvailability skuUUID
      result <- shouldSucceed $ runTest store action
      case result of
        Just (_, reserved) -> reserved `shouldBe` 2
        Nothing            -> expectationFailure "Expected availability"

    it "addItem followed by removeItem restores reserved count" $ do
      let
        store  = (storeWith Created) {tsInventory = Map.singleton skuUUID 5}
        action = do
          _ <- Svc.addItem testSaleItem
          Svc.removeItem itemUUID
          getInventoryAvailability skuUUID
      result <- shouldSucceed $ runTest store action
      case result of
        Just (_, reserved) -> reserved `shouldBe` 0
        Nothing            -> expectationFailure "Expected availability"

  describe "event emission" $ do
    it "addItem emits TransactionItemAdded and PullRequestCreated on success" $ do
      (result, evts) <- runTestWithEvents (storeWith Created) (Svc.addItem testSaleItem)
      result `shouldSatisfy` either (const False) (const True)
      let txAdded     = [() | TransactionEvt (TransactionItemAdded {teTxId}) <- evts, teTxId == txUUID]
          pullCreated = [() | StockEvt (PullRequestCreated {}) <- evts]
      txAdded     `shouldSatisfy` (not . null)
      pullCreated `shouldSatisfy` (not . null)

    it "addItem emits no events on state machine rejection (Completed)" $ do
      (_, evts) <- runTestWithEvents (storeWith Completed) (Svc.addItem testSaleItem)
      evts `shouldBe` []

    it "addItem emits no events when SKU not in inventory" $ do
      (_, evts) <-
        runTestWithEvents (storeWith Created) $
          Svc.addItem testSaleItem {itemMenuItemSku = read "ffffffff-ffff-ffff-ffff-ffffffffffff"}
      evts `shouldBe` []

    it "voidTx emits TransactionVoided on success (no open pulls)" $ do
      (result, evts) <- runTestWithEvents (storeWith InProgress) (Svc.voidTx txUUID "fraud")
      result `shouldSatisfy` either (const False) (const True)
      case evts of
        [TransactionEvt (TransactionVoided {teReason})] ->
          teReason `shouldBe` "fraud"
        _ -> expectationFailure $ "Expected [TransactionVoided], got " <> show (length evts) <> " events"

    it "voidTx emits no events on rejection (already voided)" $ do
      (_, evts) <- runTestWithEvents (storeWith Voided) (Svc.voidTx txUUID "again")
      evts `shouldBe` []

    it "finalizeTx emits TransactionFinalized on success" $ do
      (result, evts) <- runTestWithEvents (storeWith InProgress) (Svc.finalizeTx txUUID)
      result `shouldSatisfy` either (const False) (const True)
      case evts of
        [TransactionEvt (TransactionFinalized {teTxId})] ->
          teTxId `shouldBe` txUUID
        _ -> expectationFailure $ "Expected [TransactionFinalized], got " <> show (length evts) <> " events"

    it "addPayment emits TransactionPaymentAdded on success" $ do
      (result, evts) <- runTestWithEvents (storeWith InProgress) (Svc.addPayment testSalePayment)
      result `shouldSatisfy` either (const False) (const True)
      case evts of
        [TransactionEvt (TransactionPaymentAdded {teTxId})] ->
          teTxId `shouldBe` txUUID
        _ -> expectationFailure $ "Expected [TransactionPaymentAdded], got " <> show (length evts) <> " events"

    it "removePayment emits TransactionPaymentRemoved on success" $ do
      (result, evts) <- runTestWithEvents (storeWithPayment InProgress) (Svc.removePayment pymtUUID)
      result `shouldSatisfy` either (const False) (const True)
      case evts of
        [TransactionEvt (TransactionPaymentRemoved {tePaymentId})] ->
          tePaymentId `shouldBe` pymtUUID
        _ -> expectationFailure $ "Expected [TransactionPaymentRemoved], got " <> show (length evts) <> " events"

    it "refundTx emits TransactionRefunded on success" $ do
      (result, evts) <- runTestWithEvents (storeWith Completed) (Svc.refundTx txUUID "defective")
      result `shouldSatisfy` either (const False) (const True)
      case evts of
        [TransactionEvt (TransactionRefunded {teTxId, teReason})] -> do
          teTxId  `shouldBe` txUUID
          teReason `shouldBe` "defective"
        _ -> expectationFailure $ "Expected [TransactionRefunded], got " <> show (length evts) <> " events"