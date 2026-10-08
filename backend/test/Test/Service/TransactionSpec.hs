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
import Effectful.Error.Static (Error, runErrorNoCallStack, tryError)
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
import Types.Primitives.Money (refundMoneyCents, saleMoneyCents, unsafeMkSaleMoney)
import Types.Primitives.Quantity (saleQuantityCount, unsafeMkSaleQuantity)
import Types.Transaction
import Types.Transaction.Conversion (saleItemToLegacy, salePaymentToLegacy)
import qualified Types.Transaction.Refund as Refund
import qualified Types.Transaction.Sale as Sale
import Types.Transaction.Sale (itemId, itemMenuItemSku)

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

-- An add request built from a line. It asks for the line's quantity to be
-- added, offers the line's id for a new line, and prices any whole quantity
-- at the line's unit price with no tax.
lineFor :: Sale.Item -> SaleLineAdd
lineFor item =
  SaleLineAdd
    { lineAddSaleId    = Sale.itemTransactionId item
    , lineAddSku       = Sale.itemMenuItemSku item
    , lineAddQuantity  = saleQuantityCount (Sale.itemQuantity item)
    , lineAddNewItemId = Sale.itemId item
    , lineAddPrice     = \lineId wholeQty ->
        Right
          item
            { Sale.itemId       = lineId
            , Sale.itemQuantity = unsafeMkSaleQuantity wholeQty
            , Sale.itemSubtotal = unsafeMkSaleMoney (wholeQty * unitPrice)
            , Sale.itemTotal    = unsafeMkSaleMoney (wholeQty * unitPrice)
            }
    }
  where
    unitPrice = saleMoneyCents (Sale.itemPricePerUnit item)

testItem :: TransactionItem
testItem = saleItemToLegacy testSaleItem

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
  let tx =
        (mkTx status)
          { transactionItems    = [testItem]
          , transactionSubtotal = 1000
          , transactionTotal    = 1000
          }
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

-- A sale with one $10.00 line and one $10.00 payment, in the given status.
storeWithItemAndPayment :: TransactionStatus -> TxStore
storeWithItemAndPayment status =
  let tx =
        (mkTx status)
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

storeWithItemAndPaymentCompleted :: TxStore
storeWithItemAndPaymentCompleted = storeWithItemAndPayment Completed

-- A paid sale that is ready to be completed.
storeReadyToFinalize :: TxStore
storeReadyToFinalize = storeWithItemAndPayment InProgress

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

-- Checks that an interpreter-level write was refused.
shouldBeRefused :: Either e a -> Expectation
shouldBeRefused outcome =
  case outcome of
    Left _  -> pure ()
    Right _ -> expectationFailure "Expected the write to be refused"

-- Checks that the stored sale holds exactly one line with the given id,
-- quantity and total, and that the sale total matches.
shouldHoldOneLine ::
  Either TypedLoadError Sale.SaleTransaction ->
  UUID ->
  Int ->
  Int ->
  Expectation
shouldHoldOneLine loaded expectedId expectedQty expectedTotal =
  case loaded of
    Right sale -> do
      map Sale.itemId (Sale.saleItems sale) `shouldBe` [expectedId]
      map (saleQuantityCount . Sale.itemQuantity) (Sale.saleItems sale) `shouldBe` [expectedQty]
      saleMoneyCents (Sale.saleTotal sale) `shouldBe` expectedTotal
    Left err -> expectationFailure ("Expected the sale, got " <> show err)

spec :: Spec
spec = describe "Service.Transaction (pure interpreter)" $ do

  describe "addItem — state machine guards" $ do
    it "succeeds from Created (transitions tx to InProgress)" $ do
      item <- shouldSucceed $ runTest (storeWith Created) (Svc.addItem (lineFor testSaleItem))
      Sale.itemId item `shouldBe` itemUUID

    it "succeeds from InProgress" $ do
      let item2 = testSaleItem {itemId = freshUUID, itemMenuItemSku = skuUUID}
      void $ shouldSucceed $ runTest (storeWith InProgress) (Svc.addItem (lineFor item2))

    it "rejects from Completed with 409" $
      shouldFailWith 409 $
        runTest (storeWith Completed) (Svc.addItem (lineFor testSaleItem))

    it "rejects from Voided with 409" $
      shouldFailWith 409 $
        runTest (storeWith Voided) (Svc.addItem (lineFor testSaleItem))

    it "rejects from Refunded with 409" $
      shouldFailWith 409 $
        runTest (storeWith Refunded) (Svc.addItem (lineFor testSaleItem))

  describe "addItem — DB-level errors" $ do
    it "returns 404 for non-existent transaction" $
      shouldFailWith 404 $
        runTest emptyTxStore (Svc.addItem (lineFor testSaleItem))

    it "returns 404 when SKU not in inventory" $
      shouldFailWith 404 $
        runTest (storeWith Created) $
          Svc.addItem
            (lineFor testSaleItem {itemMenuItemSku = read "ffffffff-ffff-ffff-ffff-ffffffffffff"})

    it "returns 400 when insufficient inventory" $ do
      let store = (storeWith Created) {tsInventory = Map.singleton skuUUID 0}
      shouldFailWith 400 $ runTest store (Svc.addItem (lineFor testSaleItem))

    it "returns 400 for a quantity of zero" $
      shouldFailWith 400 $
        runTest (storeWith Created) $
          Svc.addItem (lineFor testSaleItem) {lineAddQuantity = 0}

    it "returns 400 when the pricing function rejects the line" $
      shouldFailWith 400 $
        runTest (storeWith Created) $
          Svc.addItem (lineFor testSaleItem) {lineAddPrice = \_ _ -> Left "no price"}

  describe "writes check the sale at the moment of the write" $ do
    it "addSaleItem refuses a completed sale without the service guard" $ do
      outcome <-
        shouldSucceed $
          runTest (storeWith Completed) (addSaleItem (lineFor testSaleItem))
      shouldBeRefused outcome

    it "addSaleItem refuses a sale that does not exist" $ do
      outcome <- shouldSucceed $ runTest emptyTxStore (addSaleItem (lineFor testSaleItem))
      shouldBeRefused outcome

    it "addSalePayment refuses a completed sale without the service guard" $ do
      outcome <-
        shouldSucceed $
          runTest (storeWithItem Completed) (addSalePayment testSalePayment)
      shouldBeRefused outcome

    it "addSalePayment refuses a sale that has not started" $ do
      outcome <-
        shouldSucceed $
          runTest (storeWith Created) (addSalePayment testSalePayment)
      shouldBeRefused outcome

    it "deleteSalePayment refuses a completed sale and keeps the payment" $ do
      (outcome, loaded) <-
        shouldSucceed $
          runTest storeWithItemAndPaymentCompleted $ do
            o <- deleteSalePayment pymtUUID
            s <- getSaleById txUUID
            pure (o, s)
      shouldBeRefused outcome
      case loaded of
        Right sale -> map Sale.paymentId (Sale.salePayments sale) `shouldBe` [pymtUUID]
        Left err   -> expectationFailure ("Expected the sale, got " <> show err)

    it "finalizeSale refuses an unpaid sale and leaves it in progress" $ do
      (outcome, loaded, stock) <-
        shouldSucceed $
          runTest (storeWithItem InProgress) $ do
            o <- finalizeSale txUUID
            s <- getSaleById txUUID
            q <- getInventoryAvailability skuUUID
            pure (o, s, q)
      shouldBeRefused outcome
      fmap Sale.saleStatus loaded `shouldBe` Right InProgress
      fmap fst stock `shouldBe` Just 10

    it "finalizeSale refuses a sale with no lines" $ do
      outcome <-
        shouldSucceed $
          runTest (storeWithPayment InProgress) (finalizeSale txUUID)
      shouldBeRefused outcome

    it "finalizeSale refuses a sale that is already completed" $ do
      outcome <-
        shouldSucceed $
          runTest storeWithItemAndPaymentCompleted (finalizeSale txUUID)
      shouldBeRefused outcome

    it "removing the payment and then finalizing is refused" $ do
      (removed, finalized) <-
        shouldSucceed $
          runTest storeReadyToFinalize $ do
            r <- deleteSalePayment pymtUUID
            f <- finalizeSale txUUID
            pure (r, f)
      case removed of
        Right () -> pure ()
        Left _   -> expectationFailure "Expected the payment removal to succeed"
      shouldBeRefused finalized

    it "finalizing and then removing the payment is refused" $ do
      (finalized, removed) <-
        shouldSucceed $
          runTest storeReadyToFinalize $ do
            f <- finalizeSale txUUID
            r <- deleteSalePayment pymtUUID
            pure (f, r)
      case finalized of
        Right sale -> Sale.saleStatus sale `shouldBe` Completed
        Left _     -> expectationFailure "Expected finalize to succeed"
      shouldBeRefused removed

    it "clearSale refuses a completed sale and keeps its line and payment" $ do
      (outcome, loaded) <-
        shouldSucceed $
          runTest storeWithItemAndPaymentCompleted $ do
            o <- clearSale txUUID
            s <- getSaleById txUUID
            pure (o, s)
      shouldBeRefused outcome
      case loaded of
        Right sale -> do
          Sale.saleStatus sale `shouldBe` Completed
          map Sale.itemId (Sale.saleItems sale) `shouldBe` [itemUUID]
          map Sale.paymentId (Sale.salePayments sale) `shouldBe` [pymtUUID]
        Left err -> expectationFailure ("Expected the sale, got " <> show err)

    it "clearSale refuses a sale that does not exist" $ do
      outcome <- shouldSucceed $ runTest emptyTxStore (clearSale txUUID)
      shouldBeRefused outcome

    it "finalizing and then clearing is refused and the sale stays completed" $ do
      (cleared, loaded) <-
        shouldSucceed $
          runTest storeReadyToFinalize $ do
            _ <- finalizeSale txUUID
            c <- clearSale txUUID
            s <- getSaleById txUUID
            pure (c, s)
      shouldBeRefused cleared
      case loaded of
        Right sale -> do
          Sale.saleStatus sale `shouldBe` Completed
          map Sale.itemId (Sale.saleItems sale) `shouldBe` [itemUUID]
          map Sale.paymentId (Sale.salePayments sale) `shouldBe` [pymtUUID]
        Left err -> expectationFailure ("Expected the sale, got " <> show err)

    it "clearing and then finalizing is refused and the sale stays empty" $ do
      (cleared, finalized, loaded) <-
        shouldSucceed $
          runTest storeReadyToFinalize $ do
            c <- clearSale txUUID
            f <- finalizeSale txUUID
            s <- getSaleById txUUID
            pure (c, f, s)
      case cleared of
        Right () -> pure ()
        Left _   -> expectationFailure "Expected the clear to succeed"
      shouldBeRefused finalized
      case loaded of
        Right sale -> do
          Sale.saleStatus sale `shouldBe` Created
          Sale.saleItems sale `shouldBe` []
          Sale.salePayments sale `shouldBe` []
        Left err -> expectationFailure ("Expected the sale, got " <> show err)

    it "voidSale refuses a voided sale without the service guard" $ do
      outcome <- shouldSucceed $ runTest (storeWith Voided) (voidSale txUUID "again")
      shouldBeRefused outcome

    it "voidSale refuses a refunded sale without the service guard" $ do
      outcome <- shouldSucceed $ runTest (storeWith Refunded) (voidSale txUUID "again")
      shouldBeRefused outcome

    it "voidSale refuses a sale that does not exist" $ do
      outcome <- shouldSucceed $ runTest emptyTxStore (voidSale txUUID "reason")
      shouldBeRefused outcome

    it "a second voidSale is refused and the first reason is kept" $ do
      (second, loaded) <-
        shouldSucceed $
          runTest (storeWith InProgress) $ do
            _ <- voidSale txUUID "first"
            v <- voidSale txUUID "second"
            s <- getSaleById txUUID
            pure (v, s)
      shouldBeRefused second
      fmap Sale.saleVoidReason loaded `shouldBe` Right (Just "first")

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

  describe "finalizeTx" $ do
    it "completes a paid sale that is in progress" $ do
      sale <- shouldSucceed $ runTest storeReadyToFinalize (Svc.finalizeTx txUUID)
      Sale.saleStatus sale `shouldBe` Completed

    it "rejects an unpaid sale with 409" $
      shouldFailWith 409 $
        runTest (storeWithItem InProgress) (Svc.finalizeTx txUUID)

    it "rejects a sale with no lines with 409" $
      shouldFailWith 409 $
        runTest (storeWith InProgress) (Svc.finalizeTx txUUID)

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

  describe "refundTx — one refund per sale" $ do
    it "a second refund is rejected with 409 and writes no second refund" $ do
      (second, refundCount, loaded) <-
        shouldSucceed $
          runTest storeWithItemAndPaymentCompleted $ do
            _ <- Svc.refundTx txUUID "first"
            s <- tryError @ServerError (Svc.refundTx txUUID "second")
            n <- length <$> getAllRefunds
            l <- getSaleById txUUID
            pure (fmap (const ()) s, n, l)
      case second of
        Left (_, err) -> errHTTPCode err `shouldBe` 409
        Right ()      -> expectationFailure "Expected the second refund to be rejected"
      refundCount `shouldBe` 1
      fmap Sale.saleIsRefunded loaded `shouldBe` Right True
      fmap Sale.saleRefundReason loaded `shouldBe` Right (Just "first")

    it "a rejected second refund emits no second event" $ do
      (_, evts) <-
        runTestWithEvents storeWithItemAndPaymentCompleted $ do
          _ <- Svc.refundTx txUUID "first"
          tryError @ServerError (Svc.refundTx txUUID "second")
      length [() | TransactionEvt (TransactionRefunded {}) <- evts] `shouldBe` 1

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
        action = Svc.addItem (lineFor testSaleItem) >> getInventoryAvailability skuUUID
      result <- shouldSucceed $ runTest store action
      case result of
        Just (_, reserved) -> reserved `shouldBe` 1
        Nothing            -> expectationFailure "Expected availability"

    it "two addItem calls for the same sku reserve both units on one line" $ do
      let
        item2  = testSaleItem {itemId = freshUUID}
        store  = (storeWith Created) {tsInventory = Map.singleton skuUUID 5}
        action = do
          _ <- Svc.addItem (lineFor testSaleItem)
          _ <- Svc.addItem (lineFor item2)
          availability <- getInventoryAvailability skuUUID
          loaded       <- getSaleById txUUID
          pure (availability, loaded)
      (availability, loaded) <- shouldSucceed $ runTest store action
      case availability of
        Just (_, reserved) -> reserved `shouldBe` 2
        Nothing            -> expectationFailure "Expected availability"
      shouldHoldOneLine loaded itemUUID 2 2000

    it "two adds prepared before either is applied both count" $ do
      let
        prepared = lineFor testSaleItem
        store    = (storeWith Created) {tsInventory = Map.singleton skuUUID 5}
        action   = do
          _ <- addSaleItem prepared
          _ <- addSaleItem prepared
          availability <- getInventoryAvailability skuUUID
          loaded       <- getSaleById txUUID
          pure (availability, loaded)
      (availability, loaded) <- shouldSucceed $ runTest store action
      case availability of
        Just (_, reserved) -> reserved `shouldBe` 2
        Nothing            -> expectationFailure "Expected availability"
      shouldHoldOneLine loaded itemUUID 2 2000

    it "addItem followed by removeItem restores reserved count" $ do
      let
        store  = (storeWith Created) {tsInventory = Map.singleton skuUUID 5}
        action = do
          _ <- Svc.addItem (lineFor testSaleItem)
          Svc.removeItem itemUUID
          getInventoryAvailability skuUUID
      result <- shouldSucceed $ runTest store action
      case result of
        Just (_, reserved) -> reserved `shouldBe` 0
        Nothing            -> expectationFailure "Expected availability"

    it "a full sale reduces stock by the quantity sold" $ do
      let
        store  = (storeWith Created) {tsInventory = Map.singleton skuUUID 5}
        action = do
          _ <- Svc.addItem (lineFor testSaleItem)
          _ <- Svc.addPayment testSalePayment
          _ <- Svc.finalizeTx txUUID
          getInventoryAvailability skuUUID
      result <- shouldSucceed $ runTest store action
      result `shouldBe` Just (4, 0)

  describe "event emission" $ do
    it "addItem emits TransactionItemAdded and PullRequestCreated on success" $ do
      (result, evts) <-
        runTestWithEvents (storeWith Created) (Svc.addItem (lineFor testSaleItem))
      result `shouldSatisfy` either (const False) (const True)
      let txAdded     = [() | TransactionEvt (TransactionItemAdded {teTxId}) <- evts, teTxId == txUUID]
          pullCreated = [() | StockEvt (PullRequestCreated {}) <- evts]
      txAdded     `shouldSatisfy` (not . null)
      pullCreated `shouldSatisfy` (not . null)

    it "a second add of the same sku reports the old line removed with its quantity" $ do
      let action = do
            _ <- Svc.addItem (lineFor testSaleItem)
            Svc.addItem (lineFor testSaleItem)
      (result, evts) <- runTestWithEvents (storeWith Created) action
      result `shouldSatisfy` either (const False) (const True)
      [ (teItemId, teQty)
        | TransactionEvt (TransactionItemRemoved {teItemId, teQty}) <- evts
        ]
        `shouldBe` [(itemUUID, 1)]
      [ transactionItemQuantity teItem
        | TransactionEvt (TransactionItemAdded {teItem}) <- evts
        ]
        `shouldBe` [1, 2]

    it "addItem emits no events on state machine rejection (Completed)" $ do
      (_, evts) <-
        runTestWithEvents (storeWith Completed) (Svc.addItem (lineFor testSaleItem))
      evts `shouldBe` []

    it "addItem emits no events when SKU not in inventory" $ do
      (_, evts) <-
        runTestWithEvents (storeWith Created) $
          Svc.addItem
            (lineFor testSaleItem {itemMenuItemSku = read "ffffffff-ffff-ffff-ffff-ffffffffffff"})
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
      (result, evts) <- runTestWithEvents storeReadyToFinalize (Svc.finalizeTx txUUID)
      result `shouldSatisfy` either (const False) (const True)
      case evts of
        [TransactionEvt (TransactionFinalized {teTxId})] ->
          teTxId `shouldBe` txUUID
        _ -> expectationFailure $ "Expected [TransactionFinalized], got " <> show (length evts) <> " events"

    it "finalizeTx emits no events when the sale is unpaid" $ do
      (_, evts) <- runTestWithEvents (storeWithItem InProgress) (Svc.finalizeTx txUUID)
      evts `shouldBe` []

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