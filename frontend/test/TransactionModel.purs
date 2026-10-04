module Test.TransactionModel where

import Prelude

import Data.Finance.Money (Discrete(..))
import Data.Maybe (Maybe(..))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Types.Inventory (Inventory(..), ItemCategory(..), MenuItem(..), Species(..), StrainLineage(..))
import Types.Primitives.Money (SaleMoney, unsafeMkSaleMoney)
import Types.Primitives.Quantity (SaleQuantity, unsafeMkSaleQuantity)
import Types.Transaction (TransactionStatus(..))
import Types.UUID (UUID(..))
import UI.Transaction.Model (Activity(..), activityLabel, addBlocker, availableToAdd, categoriesIn, finalizeBlockers, isBusy, isOpen, paidCents, quantityInCart, remainingCents, totals, visibleItems)

skuA :: UUID
skuA = UUID "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

skuB :: UUID
skuB = UUID "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

skuC :: UUID
skuC = UUID "cccccccc-cccc-cccc-cccc-cccccccccccc"

mkItem :: UUID -> String -> ItemCategory -> Int -> MenuItem
mkItem sku name category quantity = MenuItem
  { sort: 0
  , sku
  , brand: "Brand"
  , name
  , price: Discrete 1000
  , measure_unit: "g"
  , per_package: "3.5"
  , quantity
  , category
  , subcategory: "Sub"
  , description: ""
  , tags: []
  , effects: []
  , strain_lineage: StrainLineage
      { thc: "20%"
      , cbg: "1%"
      , strain: "S"
      , creator: "C"
      , species: Hybrid
      , dominant_terpene: "M"
      , terpenes: []
      , lineage: []
      , leafly_url: "https://leafly.com"
      , img: "https://example.com/img.jpg"
      }
  }

ogKush :: MenuItem
ogKush = mkItem skuA "OG Kush" Flower 10

gummies :: MenuItem
gummies = mkItem skuB "Sour Gummies" Edibles 0

blueDream :: MenuItem
blueDream = mkItem skuC "Blue Dream" Flower 3

inventory :: Inventory
inventory = Inventory [ gummies, ogKush, blueDream ]

names :: Array MenuItem -> Array String
names = map \(MenuItem i) -> i.name

type Line = { itemMenuItemSku :: UUID, itemQuantity :: SaleQuantity }

type Pay = { paymentAmount :: SaleMoney }

line :: UUID -> Int -> Line
line sku qty = { itemMenuItemSku: sku, itemQuantity: unsafeMkSaleQuantity qty }

payment :: Int -> Pay
payment cents = { paymentAmount: unsafeMkSaleMoney cents }

spec :: Spec Unit
spec = describe "UI.Transaction.Model" do

  describe "Activity" do
    it "Idle is not busy" $ isBusy Idle `shouldEqual` false
    it "Finalizing is busy" $ isBusy Finalizing `shouldEqual` true
    it "Idle has no label" $ activityLabel Idle `shouldEqual` ""
    it "AddingItem has a label" $
      activityLabel AddingItem `shouldEqual` "Adding item..."

  describe "categoriesIn" do
    it "lists each category once in enum order" $
      categoriesIn inventory `shouldEqual` [ Flower, Edibles ]
    it "is empty for an empty inventory" $
      categoriesIn (Inventory []) `shouldEqual` []

  describe "visibleItems" do
    it "shows everything with no filters" $
      names (visibleItems { search: "", category: Nothing } inventory)
        `shouldEqual` [ "Sour Gummies", "OG Kush", "Blue Dream" ]
    it "filters by category" $
      names (visibleItems { search: "", category: Just Flower } inventory)
        `shouldEqual` [ "OG Kush", "Blue Dream" ]
    it "searches by name ignoring case and spaces" $
      names (visibleItems { search: "  KUSH ", category: Nothing } inventory)
        `shouldEqual` [ "OG Kush" ]
    it "combines category and search" $
      names (visibleItems { search: "blue", category: Just Edibles } inventory)
        `shouldEqual` []

  describe "quantityInCart" do
    it "is zero for an empty cart" $
      quantityInCart skuA ([] :: Array Line)
        `shouldEqual` 0
    it "sums lines that share a SKU" $
      quantityInCart skuA [ line skuA 2, line skuB 5, line skuA 3 ]
        `shouldEqual` 5

  describe "availableToAdd" do
    it "is the quantity the backend reports" $
      availableToAdd ogKush `shouldEqual` 10
    it "never goes below zero" $
      availableToAdd (mkItem skuC "Oversold" Flower (-2)) `shouldEqual` 0

  describe "addBlocker" do
    it "allows an add within stock" $
      addBlocker 2 ogKush `shouldEqual` Nothing
    it "allows taking everything that is left" $
      addBlocker 3 blueDream `shouldEqual` Nothing
    it "rejects a zero quantity" $
      addBlocker 0 ogKush
        `shouldEqual` Just "Quantity must be greater than 0"
    it "rejects an item with no stock" $
      addBlocker 1 gummies `shouldEqual` Just "Out of stock"
    it "rejects more than is left" $
      addBlocker 4 blueDream
        `shouldEqual` Just "Only 3 available"

  describe "totals" do
    it "reads the backend totals in cents" $
      totals
        { saleSubtotal: unsafeMkSaleMoney 2000
        , saleDiscountTotal: unsafeMkSaleMoney 100
        , saleTaxTotal: unsafeMkSaleMoney 152
        , saleTotal: unsafeMkSaleMoney 2052
        }
        `shouldEqual` { subtotal: 2000, discount: 100, tax: 152, total: 2052 }

  describe "payments" do
    it "sums payment amounts" $
      paidCents [ payment 500, payment 1500 ] `shouldEqual` 2000
    it "remaining is total minus paid" $
      remainingCents
        { saleTotal: unsafeMkSaleMoney 2052, salePayments: [ payment 2000 ] }
        `shouldEqual` 52
    it "remaining is zero when overpaid" $
      remainingCents
        { saleTotal: unsafeMkSaleMoney 2052, salePayments: [ payment 3000 ] }
        `shouldEqual` 0

  describe "isOpen" do
    it "Created is open" $ isOpen Created `shouldEqual` true
    it "InProgress is open" $ isOpen InProgress `shouldEqual` true
    it "Completed is closed" $ isOpen Completed `shouldEqual` false

  describe "finalizeBlockers" do
    let
      sale :: TransactionStatus -> Array Line -> Array Pay -> _
      sale status items payments =
        { saleStatus: status
        , saleItems: items
        , salePayments: payments
        , saleTotal: unsafeMkSaleMoney 2052
        }
    it "is empty when items exist and payment covers the total" $
      finalizeBlockers (sale InProgress [ line skuA 2 ] [ payment 2052 ])
        `shouldEqual` []
    it "reports an empty cart" $
      finalizeBlockers (sale Created [] [])
        `shouldEqual` [ "No items in transaction" ]
    it "reports the shortfall" $
      finalizeBlockers (sale InProgress [ line skuA 2 ] [ payment 2000 ])
        `shouldEqual` [ "Payment is short by $0.52" ]
    it "reports a completed sale and nothing else" $
      finalizeBlockers (sale Completed [ line skuA 2 ] [])
        `shouldEqual` [ "Transaction is already completed" ]