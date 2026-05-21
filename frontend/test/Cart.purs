-- FILE: ./frontend/test/Cart.purs
module Test.Cart where

import Prelude

import Data.Finance.Money (Discrete(..))
import Data.Maybe (Maybe(..))
import Services.Cart
  ( getCartQuantityForSku
  , isItemAvailable
  , getAvailableQuantity
  , findUnavailableItems
  , findExistingItem
  )
import Services.TransactionService
  ( calculateCartTotals
  , emptyCartTotals
  , calculateTotalPayments
  , paymentsCoversTotal
  , getRemainingBalance
  )
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Inventory (Inventory(..), MenuItem(..), StrainLineage(..))
import Types.Primitives.Money (unsafeMkSaleMoney)
import Types.Primitives.Quantity (unsafeMkSaleQuantity)
import Types.Transaction (PaymentMethod(..), TaxCategory(..))
import Types.Transaction.Sale as Sale
import Types.UUID (UUID(..))

mkUUID :: String -> UUID
mkUUID = UUID

skuA :: UUID
skuA = mkUUID "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

skuB :: UUID
skuB = mkUUID "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

itemIdA :: UUID
itemIdA = mkUUID "11111111-1111-1111-1111-111111111111"

itemIdB :: UUID
itemIdB = mkUUID "22222222-2222-2222-2222-222222222222"

txId :: UUID
txId = mkUUID "33333333-3333-3333-3333-333333333333"

mkMenuItem :: UUID -> String -> Int -> Int -> MenuItem
mkMenuItem sku name price qty = MenuItem
  { sort: 0
  , sku
  , brand: "TestBrand"
  , name
  , price: Discrete price
  , measure_unit: "g"
  , per_package: "3.5"
  , quantity: qty
  , category: top -- Flower
  , subcategory: "Indoor"
  , description: "Test item"
  , tags: []
  , effects: []
  , strain_lineage: StrainLineage
      { thc: "25%"
      , cbg: "0.5%"
      , strain: "Test Strain"
      , creator: "Test Creator"
      , species: bottom -- Indica
      , dominant_terpene: "Myrcene"
      , terpenes: []
      , lineage: []
      , leafly_url: "https://leafly.com"
      , img: "https://example.com/img.jpg"
      }
  }

mkSaleItem :: UUID -> UUID -> UUID -> Int -> Int -> Sale.Item
mkSaleItem id txnId sku qty pricePerUnit =
  let
    subtotal  = pricePerUnit * qty
    taxAmount = (subtotal * 8) / 100
    total     = subtotal + taxAmount
  in
    { itemId            : id
    , itemTransactionId : txnId
    , itemMenuItemSku   : sku
    , itemQuantity      : unsafeMkSaleQuantity qty
    , itemPricePerUnit  : unsafeMkSaleMoney pricePerUnit
    , itemDiscounts     : []
    , itemTaxes         :
        [ { taxCategory    : RegularSalesTax
          , taxRate        : 0.08
          , taxAmount      : unsafeMkSaleMoney taxAmount
          , taxDescription : "Sales Tax"
          }
        ]
    , itemSubtotal      : unsafeMkSaleMoney subtotal
    , itemTotal         : unsafeMkSaleMoney total
    }

mkPayment :: UUID -> UUID -> Int -> Sale.Payment
mkPayment payId txnId amount =
  { paymentId                : payId
  , paymentTransactionId     : txnId
  , paymentMethod            : Cash
  , paymentAmount            : unsafeMkSaleMoney amount
  , paymentTendered          : unsafeMkSaleMoney amount
  , paymentChange            : unsafeMkSaleMoney 0
  , paymentReference         : Nothing
  , paymentApproved          : true
  , paymentAuthorizationCode : Nothing
  }

spec :: Spec Unit
spec = describe "Cart & Transaction Logic" do

  describe "emptyCartTotals" do
    it "has zero subtotal" do
      emptyCartTotals.subtotal `shouldEqual` Discrete 0
    it "has zero tax" do
      emptyCartTotals.taxTotal `shouldEqual` Discrete 0
    it "has zero total" do
      emptyCartTotals.total `shouldEqual` Discrete 0
    it "has zero discounts" do
      emptyCartTotals.discountTotal `shouldEqual` Discrete 0

  describe "calculateCartTotals" do
    it "returns empty totals for empty cart" do
      let totals = calculateCartTotals []
      totals.subtotal `shouldEqual` Discrete 0
      totals.total `shouldEqual` Discrete 0

    it "calculates totals for single item" do
      let item = mkSaleItem itemIdA txId skuA 2 1000 -- 2x $10.00
      let totals = calculateCartTotals [item]
      totals.subtotal `shouldEqual` Discrete 2000

    it "calculates totals for multiple items" do
      let itemA = mkSaleItem itemIdA txId skuA 1 1000 -- 1x $10.00
      let itemB = mkSaleItem itemIdB txId skuB 3 500  -- 3x $5.00
      let totals = calculateCartTotals [itemA, itemB]
      totals.subtotal `shouldEqual` Discrete 2500

    it "accumulates tax totals" do
      let item = mkSaleItem itemIdA txId skuA 1 1000
      let totals = calculateCartTotals [item]
      -- tax = 1000 * 0.08 = 80
      totals.taxTotal `shouldEqual` Discrete 80

  describe "calculateTotalPayments" do
    it "returns zero for no payments" do
      calculateTotalPayments [] `shouldEqual` Discrete 0

    it "sums multiple payments" do
      let p1 = mkPayment (mkUUID "44444444-4444-4444-4444-444444444444") txId 1000
      let p2 = mkPayment (mkUUID "55555555-5555-5555-5555-555555555555") txId 500
      calculateTotalPayments [p1, p2] `shouldEqual` Discrete 1500

  describe "paymentsCoversTotal" do
    it "returns true when payment equals total" do
      let payment = mkPayment (mkUUID "44444444-4444-4444-4444-444444444444") txId 5000
      paymentsCoversTotal [payment] (Discrete 5000) `shouldEqual` true

    it "returns true when payment exceeds total" do
      let payment = mkPayment (mkUUID "44444444-4444-4444-4444-444444444444") txId 6000
      paymentsCoversTotal [payment] (Discrete 5000) `shouldEqual` true

    it "returns false when payment is less than total" do
      let payment = mkPayment (mkUUID "44444444-4444-4444-4444-444444444444") txId 3000
      paymentsCoversTotal [payment] (Discrete 5000) `shouldEqual` false

    it "returns false for no payments" do
      paymentsCoversTotal [] (Discrete 5000) `shouldEqual` false

  describe "getRemainingBalance" do
    it "returns full amount when no payments" do
      getRemainingBalance [] (Discrete 5000) `shouldEqual` Discrete 5000

    it "returns remaining after partial payment" do
      let payment = mkPayment (mkUUID "44444444-4444-4444-4444-444444444444") txId 3000
      getRemainingBalance [payment] (Discrete 5000) `shouldEqual` Discrete 2000

    it "returns zero when fully paid" do
      let payment = mkPayment (mkUUID "44444444-4444-4444-4444-444444444444") txId 5000
      getRemainingBalance [payment] (Discrete 5000) `shouldEqual` Discrete 0

    it "returns zero when overpaid (clamped)" do
      let payment = mkPayment (mkUUID "44444444-4444-4444-4444-444444444444") txId 7000
      getRemainingBalance [payment] (Discrete 5000) `shouldEqual` Discrete 0

  describe "getCartQuantityForSku" do
    it "returns 0 for empty cart" do
      getCartQuantityForSku skuA [] `shouldEqual` 0

    it "returns quantity for matching sku" do
      let item = mkSaleItem itemIdA txId skuA 3 1000
      getCartQuantityForSku skuA [item] `shouldEqual` 3

    it "returns 0 for non-matching sku" do
      let item = mkSaleItem itemIdA txId skuA 3 1000
      getCartQuantityForSku skuB [item] `shouldEqual` 0

  describe "isItemAvailable" do
    let menuItem = mkMenuItem skuA "Test" 1000 10 -- 10 in stock

    it "available when no items in cart" do
      isItemAvailable menuItem 1 [] `shouldEqual` true

    it "available when cart + request <= stock" do
      let cartItem = mkSaleItem itemIdA txId skuA 5 1000
      isItemAvailable menuItem 3 [cartItem] `shouldEqual` true

    it "available at exact boundary" do
      let cartItem = mkSaleItem itemIdA txId skuA 5 1000
      isItemAvailable menuItem 5 [cartItem] `shouldEqual` true

    it "unavailable when exceeds stock" do
      let cartItem = mkSaleItem itemIdA txId skuA 8 1000
      isItemAvailable menuItem 5 [cartItem] `shouldEqual` false

  describe "getAvailableQuantity" do
    let menuItem = mkMenuItem skuA "Test" 1000 10

    it "returns full stock when nothing in cart" do
      getAvailableQuantity menuItem [] `shouldEqual` 10

    it "returns remaining when items in cart" do
      let cartItem = mkSaleItem itemIdA txId skuA 3 1000
      getAvailableQuantity menuItem [cartItem] `shouldEqual` 7

    it "returns 0 when fully allocated" do
      let cartItem = mkSaleItem itemIdA txId skuA 10 1000
      getAvailableQuantity menuItem [cartItem] `shouldEqual` 0

  describe "findExistingItem" do
    it "finds matching item" do
      let menuItem = mkMenuItem skuA "Test" 1000 10
      let cartItem = mkSaleItem itemIdA txId skuA 1 1000
      findExistingItem menuItem [cartItem] `shouldSatisfy` case _ of
        Just _  -> true
        Nothing -> false

    it "returns Nothing when no match" do
      let menuItem = mkMenuItem skuA "Test" 1000 10
      let cartItem = mkSaleItem itemIdB txId skuB 1 500
      findExistingItem menuItem [cartItem] `shouldEqual` Nothing

  describe "findUnavailableItems" do
    let inventory = Inventory
          [ mkMenuItem skuA "Item A" 1000 5
          , mkMenuItem skuB "Item B" 500 2
          ]

    it "returns empty for available items" do
      let cartItems = [ mkSaleItem itemIdA txId skuA 3 1000 ]
      findUnavailableItems cartItems inventory `shouldEqual` []

    it "finds items exceeding stock" do
      let cartItems = [ mkSaleItem itemIdA txId skuA 10 1000 ]
      let result = findUnavailableItems cartItems inventory
      (result /= []) `shouldEqual` true

    it "finds items with unknown sku" do
      let unknownSku = mkUUID "cccccccc-cccc-cccc-cccc-cccccccccccc"
      let cartItems = [ mkSaleItem itemIdA txId unknownSku 1 1000 ]
      let result = findUnavailableItems cartItems inventory
      (result /= []) `shouldEqual` true