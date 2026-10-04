{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Test.Service.SaleSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import qualified Data.Vector as V
import Effectful (Eff, IOE, runEff)
import Effectful.Error.Static (Error, runErrorNoCallStack)
import Servant (ServerError (..))
import Test.Hspec

import Domain.Pricing (RoundingMode (..), TaxRule (..), mkTaxRate)
import Domain.TaxRule (StoredTaxRule (..))
import Effect.Clock (Clock, runClockPure)
import Effect.EventEmitter (EventEmitter, runEventEmitterNoop)
import Effect.GenUUID (GenUUID, runGenUUIDPure)
import Effect.InventoryDb (InventoryDb, runInventoryDbPure)
import Effect.StockDb (StockDb, emptyStockStore, runStockDbPure)
import Effect.TaxRules (TaxRules, runTaxRulesPure)
import Effect.TransactionDb
import qualified Service.Sale as SaleSvc
import Types.Inventory
  ( ItemCategory (..)
  , MenuItem (..)
  , Species (..)
  , StrainLineage (..)
  )
import Types.Location (LocationId (..))
import Types.Primitives.Money (saleMoneyCents, unsafeMkSaleMoney)
import Types.Primitives.Quantity (saleQuantityCount, unsafeMkSaleQuantity)
import Types.Transaction
import Types.Transaction.Conversion (saleItemToLegacy, salePaymentToLegacy)
import Types.Transaction.Request
import qualified Types.Transaction.Sale as Sale

-- ---------------------------------------------------------------------------
-- Fixed values
-- ---------------------------------------------------------------------------

txUUID, itemUUID, pymtUUID, skuUUID, empUUID, regUUID, locUUID, unknownUUID :: UUID
txUUID      = read "11111111-1111-1111-1111-111111111111"
itemUUID    = read "22222222-2222-2222-2222-222222222222"
pymtUUID    = read "33333333-3333-3333-3333-333333333333"
skuUUID     = read "44444444-4444-4444-4444-444444444444"
empUUID     = read "55555555-5555-5555-5555-555555555555"
regUUID     = read "66666666-6666-6666-6666-666666666666"
locUUID     = read "77777777-7777-7777-7777-777777777777"
unknownUUID = read "ffffffff-ffff-ffff-ffff-ffffffffffff"

uuidSupply :: [UUID]
uuidSupply =
  [read $ "b0000000-0000-0000-0000-" <> pad n | n <- [1 ..] :: [Int]]
  where
    pad n = replicate (12 - length (show n)) '0' <> show n

firstSuppliedUUID :: UUID
firstSuppliedUUID = read "b0000000-0000-0000-0000-000000000001"

testTime :: UTCTime
testTime = read "2024-06-15 10:00:00 UTC"

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

-- | A flower item priced at $19.99 on the menu.
testMenuItem :: MenuItem
testMenuItem =
  MenuItem
    { sort = 0
    , sku = skuUUID
    , brand = "Brand"
    , name = "OG Kush"
    , price = 1999
    , measure_unit = "g"
    , per_package = "3.5"
    , quantity = 10
    , category = Flower
    , subcategory = "Indoor"
    , description = ""
    , tags = V.empty
    , effects = V.empty
    , strain_lineage =
        StrainLineage
          { thc = "20%"
          , cbg = "1%"
          , strain = "OG Kush"
          , creator = "Unknown"
          , species = Hybrid
          , dominant_terpene = "Myrcene"
          , terpenes = V.empty
          , lineage = V.empty
          , leafly_url = "https://leafly.com"
          , img = "https://example.com/img.jpg"
          }
    }

testMenu :: Map.Map UUID MenuItem
testMenu = Map.singleton skuUUID testMenuItem

-- | A 6.25% tax on everything and a 10.75% tax on flower. Test values, not
-- real rates.
testRules :: [StoredTaxRule]
testRules =
  [ stored (rule Nothing RegularSalesTax 62500 "Sales tax")
  , stored (rule (Just Flower) ExciseTax 107500 "Excise tax")
  ]
  where
    rule itemCategory taxCategory ppm text =
      TaxRule
        { ruleItemCategory = itemCategory
        , ruleTaxCategory  = taxCategory
        , ruleRate         = fromJust (mkTaxRate ppm)
        , ruleRounding     = RoundHalfUp
        , ruleDescription  = text
        }
    stored r =
      StoredTaxRule
        { storedRuleId        = unknownUUID
        , storedLocation      = Nothing
        , storedEffectiveFrom = read "2020-01-01 00:00:00 UTC"
        , storedEffectiveTo   = Nothing
        , storedRule          = r
        }

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

-- | A $10.00 line already on the sale.
existingItem :: Sale.Item
existingItem =
  Sale.Item
    { Sale.itemId            = itemUUID
    , Sale.itemTransactionId = txUUID
    , Sale.itemMenuItemSku   = skuUUID
    , Sale.itemQuantity      = unsafeMkSaleQuantity 1
    , Sale.itemPricePerUnit  = unsafeMkSaleMoney 1000
    , Sale.itemDiscounts     = []
    , Sale.itemTaxes         = []
    , Sale.itemSubtotal      = unsafeMkSaleMoney 1000
    , Sale.itemTotal         = unsafeMkSaleMoney 1000
    }

existingPayment :: Int -> Sale.Payment
existingPayment cents =
  Sale.Payment
    { Sale.paymentId                = pymtUUID
    , Sale.paymentTransactionId     = txUUID
    , Sale.paymentMethod            = Cash
    , Sale.paymentAmount            = unsafeMkSaleMoney cents
    , Sale.paymentTendered          = unsafeMkSaleMoney cents
    , Sale.paymentChange            = unsafeMkSaleMoney 0
    , Sale.paymentReference         = Nothing
    , Sale.paymentApproved          = True
    , Sale.paymentAuthorizationCode = Nothing
    }

-- | An empty sale in the given status, with 10 units of the test item in
-- stock.
emptySale :: TransactionStatus -> TxStore
emptySale status =
  emptyTxStore
    { tsTxs       = Map.singleton txUUID (mkTx status)
    , tsInventory = Map.singleton skuUUID 10
    }

-- | A sale holding the $10.00 line, with its stored total set to match.
saleWithItem :: TransactionStatus -> TxStore
saleWithItem status =
  let tx =
        (mkTx status)
          { transactionItems    = [saleItemToLegacy existingItem]
          , transactionSubtotal = 1000
          , transactionTotal    = 1000
          }
   in emptyTxStore
        { tsTxs       = Map.singleton txUUID tx
        , tsItemToTx  = Map.singleton itemUUID txUUID
        , tsInventory = Map.singleton skuUUID 10
        }

-- | The same sale with one payment of the given amount.
saleWithItemAndPayment :: Int -> TxStore
saleWithItemAndPayment cents =
  let tx =
        (mkTx InProgress)
          { transactionItems    = [saleItemToLegacy existingItem]
          , transactionPayments = [salePaymentToLegacy (existingPayment cents)]
          , transactionSubtotal = 1000
          , transactionTotal    = 1000
          }
   in emptyTxStore
        { tsTxs         = Map.singleton txUUID tx
        , tsItemToTx    = Map.singleton itemUUID txUUID
        , tsPaymentToTx = Map.singleton pymtUUID txUUID
        , tsInventory   = Map.singleton skuUUID 10
        }

-- ---------------------------------------------------------------------------
-- Effect stack
-- ---------------------------------------------------------------------------

type TestEffs =
  '[ TaxRules
   , TransactionDb
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
      . runInventoryDbPure testMenu
      . runStockDbPure emptyStockStore
      . runTransactionDbPure store
      . runTaxRulesPure testRules
    $ action

shouldSucceed :: IO (Either ServerError a) -> IO a
shouldSucceed io = do
  result <- io
  case result of
    Left err ->
      expectationFailure
        ("Expected success but got HTTP " <> show (errHTTPCode err) <> " " <> show (errBody err))
        >> error "unreachable"
    Right a -> pure a

shouldFailWith :: Int -> IO (Either ServerError a) -> IO ()
shouldFailWith code io = do
  result <- io
  case result of
    Left err -> errHTTPCode err `shouldBe` code
    Right _  -> expectationFailure $ "Expected HTTP " <> show code <> " but got success"

addTwo :: AddItemRequest
addTwo = AddItemRequest {addItemSaleId = txUUID, addItemSku = skuUUID, addItemQuantity = 2}

payment :: Int -> Maybe Int -> AddPaymentRequest
payment amount tendered =
  AddPaymentRequest
    { addPaymentSaleId    = txUUID
    , addPaymentMethod    = Cash
    , addPaymentAmount    = amount
    , addPaymentTendered  = tendered
    , addPaymentReference = Nothing
    }

-- ---------------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Service.Sale (pure interpreter)" $ do

  describe "startSale" $ do
    let request =
          StartSaleRequest
            { startSaleEmployeeId = empUUID
            , startSaleRegisterId = regUUID
            , startSaleLocationId = LocationId locUUID
            }

    it "opens an empty sale with a backend-generated id" $ do
      sale <- shouldSucceed $ runTest emptyTxStore (SaleSvc.startSale request)
      Sale.saleId sale `shouldBe` firstSuppliedUUID
      Sale.saleStatus sale `shouldBe` Created
      Sale.saleCreated sale `shouldBe` testTime
      Sale.saleItems sale `shouldBe` []
      Sale.salePayments sale `shouldBe` []
      saleMoneyCents (Sale.saleTotal sale) `shouldBe` 0

    it "carries the employee, register and location from the request" $ do
      sale <- shouldSucceed $ runTest emptyTxStore (SaleSvc.startSale request)
      Sale.saleEmployeeId sale `shouldBe` empUUID
      Sale.saleRegisterId sale `shouldBe` regUUID
      Sale.saleLocationId sale `shouldBe` LocationId locUUID

  describe "addItem" $ do
    it "prices the line from the menu and the tax rules" $ do
      sale <- shouldSucceed $ runTest (emptySale Created) (SaleSvc.addItem addTwo)
      case Sale.saleItems sale of
        [item] -> do
          Sale.itemMenuItemSku item `shouldBe` skuUUID
          saleQuantityCount (Sale.itemQuantity item) `shouldBe` 2
          saleMoneyCents (Sale.itemPricePerUnit item) `shouldBe` 1999
          saleMoneyCents (Sale.itemSubtotal item) `shouldBe` 3998
          map (saleMoneyCents . Sale.taxAmount) (Sale.itemTaxes item) `shouldBe` [250, 430]
          map Sale.taxCategory (Sale.itemTaxes item) `shouldBe` [RegularSalesTax, ExciseTax]
          saleMoneyCents (Sale.itemTotal item) `shouldBe` 4678
        other -> expectationFailure ("Expected one item, got " <> show (length other))

    it "generates the item id on the backend" $ do
      sale <- shouldSucceed $ runTest (emptySale Created) (SaleSvc.addItem addTwo)
      map Sale.itemId (Sale.saleItems sale) `shouldBe` [firstSuppliedUUID]

    it "moves a new sale to InProgress" $ do
      sale <- shouldSucceed $ runTest (emptySale Created) (SaleSvc.addItem addTwo)
      Sale.saleStatus sale `shouldBe` InProgress

    it "rejects an unknown sale with 404" $
      shouldFailWith 404 $
        runTest emptyTxStore (SaleSvc.addItem addTwo)

    it "rejects an item that is not on the menu with 404" $
      shouldFailWith 404 $
        runTest (emptySale Created) (SaleSvc.addItem addTwo {addItemSku = unknownUUID})

    it "rejects a zero quantity with 400" $
      shouldFailWith 400 $
        runTest (emptySale Created) (SaleSvc.addItem addTwo {addItemQuantity = 0})

    it "rejects more than is in stock with 400" $
      shouldFailWith 400 $
        runTest (emptySale Created) (SaleSvc.addItem addTwo {addItemQuantity = 11})

    it "rejects a completed sale with 409" $
      shouldFailWith 409 $
        runTest (emptySale Completed) (SaleSvc.addItem addTwo)

  describe "removeItem" $ do
    it "returns the sale without the item" $ do
      sale <- shouldSucceed $ runTest (saleWithItem InProgress) (SaleSvc.removeItem itemUUID)
      Sale.saleItems sale `shouldBe` []

    it "rejects an unknown item with 404" $
      shouldFailWith 404 $
        runTest (saleWithItem InProgress) (SaleSvc.removeItem unknownUUID)

  describe "addPayment" $ do
    it "computes the change and approves the payment on the backend" $ do
      sale <-
        shouldSucceed $
          runTest (saleWithItem InProgress) (SaleSvc.addPayment (payment 1000 (Just 2000)))
      case Sale.salePayments sale of
        [p] -> do
          Sale.paymentId p `shouldBe` firstSuppliedUUID
          saleMoneyCents (Sale.paymentAmount p) `shouldBe` 1000
          saleMoneyCents (Sale.paymentTendered p) `shouldBe` 2000
          saleMoneyCents (Sale.paymentChange p) `shouldBe` 1000
          Sale.paymentApproved p `shouldBe` True
        other -> expectationFailure ("Expected one payment, got " <> show (length other))

    it "treats a payment with no tendered amount as exact" $ do
      sale <-
        shouldSucceed $
          runTest (saleWithItem InProgress) (SaleSvc.addPayment (payment 1000 Nothing))
      map (saleMoneyCents . Sale.paymentTendered) (Sale.salePayments sale) `shouldBe` [1000]
      map (saleMoneyCents . Sale.paymentChange) (Sale.salePayments sale) `shouldBe` [0]

    it "does not complete the sale, even when it is paid in full" $ do
      sale <-
        shouldSucceed $
          runTest (saleWithItem InProgress) (SaleSvc.addPayment (payment 1000 Nothing))
      Sale.saleStatus sale `shouldBe` InProgress

    it "rejects a zero amount with 400" $
      shouldFailWith 400 $
        runTest (saleWithItem InProgress) (SaleSvc.addPayment (payment 0 Nothing))

    it "rejects tendering less than the amount with 400" $
      shouldFailWith 400 $
        runTest (saleWithItem InProgress) (SaleSvc.addPayment (payment 1000 (Just 500)))

    it "rejects a payment on a sale with no items yet with 409" $
      shouldFailWith 409 $
        runTest (emptySale Created) (SaleSvc.addPayment (payment 1000 Nothing))

  describe "removePayment" $ do
    it "returns the sale without the payment" $ do
      sale <-
        shouldSucceed $
          runTest (saleWithItemAndPayment 1000) (SaleSvc.removePayment pymtUUID)
      Sale.salePayments sale `shouldBe` []

    it "rejects an unknown payment with 404" $
      shouldFailWith 404 $
        runTest (saleWithItemAndPayment 1000) (SaleSvc.removePayment unknownUUID)

  describe "clear" $ do
    it "returns the sale empty and back in Created" $ do
      sale <- shouldSucceed $ runTest (saleWithItemAndPayment 1000) (SaleSvc.clear txUUID)
      Sale.saleItems sale `shouldBe` []
      Sale.salePayments sale `shouldBe` []
      Sale.saleStatus sale `shouldBe` Created
      saleMoneyCents (Sale.saleTotal sale) `shouldBe` 0

    it "rejects a completed sale with 409" $
      shouldFailWith 409 $
        runTest (saleWithItem Completed) (SaleSvc.clear txUUID)

  describe "finalize" $ do
    it "completes a sale that has items and is paid in full" $ do
      sale <- shouldSucceed $ runTest (saleWithItemAndPayment 1000) (SaleSvc.finalize txUUID)
      Sale.saleStatus sale `shouldBe` Completed

    it "completes a sale that is overpaid" $ do
      sale <- shouldSucceed $ runTest (saleWithItemAndPayment 1500) (SaleSvc.finalize txUUID)
      Sale.saleStatus sale `shouldBe` Completed

    it "rejects a sale whose payments are short with 409" $
      shouldFailWith 409 $
        runTest (saleWithItemAndPayment 999) (SaleSvc.finalize txUUID)

    it "rejects a sale with no payment with 409" $
      shouldFailWith 409 $
        runTest (saleWithItem InProgress) (SaleSvc.finalize txUUID)

    it "rejects a sale with no items with 409" $
      shouldFailWith 409 $
        runTest (emptySale InProgress) (SaleSvc.finalize txUUID)

    it "rejects an unknown sale with 404" $
      shouldFailWith 404 $
        runTest emptyTxStore (SaleSvc.finalize txUUID)
