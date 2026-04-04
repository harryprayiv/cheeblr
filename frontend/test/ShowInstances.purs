module Test.ShowInstances where

import Prelude

import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Types.Auth (UserRole(..))
import Types.Inventory (ItemCategory(..), Species(..))
import Types.Transaction
  ( PaymentMethod(..)
  , TaxCategory(..)
  , TransactionStatus(..)
  , TransactionType(..)
  )

spec :: Spec Unit
spec = describe "Show Instances" do

  describe "TransactionStatus Show" do
    it "Created"    $ show Created    `shouldEqual` "CREATED"
    it "InProgress" $ show InProgress `shouldEqual` "IN_PROGRESS"
    it "Completed"  $ show Completed  `shouldEqual` "COMPLETED"
    it "Voided"     $ show Voided     `shouldEqual` "VOIDED"
    it "Refunded"   $ show Refunded   `shouldEqual` "REFUNDED"

  describe "TransactionStatus Eq" do
    it "Created == Created"       $ (Created == Created)       `shouldEqual` true
    it "Created /= InProgress"    $ (Created == InProgress)    `shouldEqual` false
    it "Completed /= Voided"      $ (Completed == Voided)      `shouldEqual` false
    it "Refunded == Refunded"     $ (Refunded == Refunded)     `shouldEqual` true

  describe "TransactionType Show" do
    it "Sale"                   $ show Sale                   `shouldEqual` "SALE"
    it "Return"                 $ show Return                 `shouldEqual` "RETURN"
    it "Exchange"               $ show Exchange               `shouldEqual` "EXCHANGE"
    it "InventoryAdjustment"    $ show InventoryAdjustment    `shouldEqual` "INVENTORY_ADJUSTMENT"
    it "ManagerComp"            $ show ManagerComp            `shouldEqual` "MANAGER_COMP"
    it "Administrative"         $ show Administrative         `shouldEqual` "ADMINISTRATIVE"

  describe "TransactionType Eq" do
    it "Sale == Sale"           $ (Sale == Sale)              `shouldEqual` true
    it "Sale /= Return"         $ (Sale == Return)            `shouldEqual` false

  describe "PaymentMethod Show" do
    it "Cash"          $ show Cash          `shouldEqual` "CASH"
    it "Debit"         $ show Debit         `shouldEqual` "DEBIT"
    it "Credit"        $ show Credit        `shouldEqual` "CREDIT"
    it "ACH"           $ show ACH           `shouldEqual` "ACH"
    it "GiftCard"      $ show GiftCard      `shouldEqual` "GIFT_CARD"
    it "StoredValue"   $ show StoredValue   `shouldEqual` "STORED_VALUE"
    it "Mixed"         $ show Mixed         `shouldEqual` "MIXED"
    it "Other Venmo"   $ show (Other "Venmo") `shouldEqual` "OTHER:Venmo"
    it "Other empty"   $ show (Other "")   `shouldEqual` "OTHER:"

  describe "PaymentMethod Eq" do
    it "Cash == Cash"           $ (Cash == Cash)              `shouldEqual` true
    it "Cash /= Debit"          $ (Cash == Debit)             `shouldEqual` false
    it "Other x == Other x"     $ (Other "Crypto" == Other "Crypto") `shouldEqual` true
    it "Other x /= Other y"     $ (Other "Venmo" == Other "Crypto")  `shouldEqual` false
    it "Cash /= Other Cash"     $ (Cash == Other "Cash")      `shouldEqual` false

  describe "TaxCategory Show" do
    it "RegularSalesTax"  $ show RegularSalesTax  `shouldEqual` "RegularSalesTax"
    it "ExciseTax"        $ show ExciseTax        `shouldEqual` "ExciseTax"
    it "CannabisTax"      $ show CannabisTax      `shouldEqual` "CannabisTax"
    it "LocalTax"         $ show LocalTax         `shouldEqual` "LocalTax"
    it "MedicalTax"       $ show MedicalTax       `shouldEqual` "MedicalTax"
    it "NoTax"            $ show NoTax            `shouldEqual` "NoTax"

  describe "TaxCategory Eq" do
    it "RegularSalesTax == RegularSalesTax" $
      (RegularSalesTax == RegularSalesTax) `shouldEqual` true
    it "CannabisTax /= ExciseTax" $
      (CannabisTax == ExciseTax) `shouldEqual` false

  describe "ItemCategory Show" do
    it "Flower"        $ show Flower        `shouldEqual` "Flower"
    it "PreRolls"      $ show PreRolls      `shouldEqual` "PreRolls"
    it "Vaporizers"    $ show Vaporizers    `shouldEqual` "Vaporizers"
    it "Edibles"       $ show Edibles       `shouldEqual` "Edibles"
    it "Drinks"        $ show Drinks        `shouldEqual` "Drinks"
    it "Concentrates"  $ show Concentrates  `shouldEqual` "Concentrates"
    it "Topicals"      $ show Topicals      `shouldEqual` "Topicals"
    it "Tinctures"     $ show Tinctures     `shouldEqual` "Tinctures"
    it "Accessories"   $ show Accessories   `shouldEqual` "Accessories"

  describe "ItemCategory Eq" do
    it "Flower == Flower"         $ (Flower == Flower)           `shouldEqual` true
    it "Flower /= Edibles"        $ (Flower == Edibles)          `shouldEqual` false

  describe "Species Show" do
    it "Indica"                $ show Indica                `shouldEqual` "Indica"
    it "IndicaDominantHybrid"  $ show IndicaDominantHybrid  `shouldEqual` "IndicaDominantHybrid"
    it "Hybrid"                $ show Hybrid                `shouldEqual` "Hybrid"
    it "SativaDominantHybrid"  $ show SativaDominantHybrid  `shouldEqual` "SativaDominantHybrid"
    it "Sativa"                $ show Sativa                `shouldEqual` "Sativa"

  describe "Species Eq" do
    it "Indica == Indica"          $ (Indica == Indica)           `shouldEqual` true
    it "Indica /= Sativa"          $ (Indica == Sativa)           `shouldEqual` false
    it "Hybrid == Hybrid"          $ (Hybrid == Hybrid)           `shouldEqual` true

  describe "UserRole Show" do
    it "Customer"  $ show Customer  `shouldEqual` "Customer"
    it "Cashier"   $ show Cashier   `shouldEqual` "Cashier"
    it "Manager"   $ show Manager   `shouldEqual` "Manager"
    it "Admin"     $ show Admin     `shouldEqual` "Admin"

  describe "UserRole Eq" do
    it "Customer == Customer"   $ (Customer == Customer)   `shouldEqual` true
    it "Customer /= Admin"      $ (Customer == Admin)      `shouldEqual` false
    it "Admin == Admin"         $ (Admin == Admin)         `shouldEqual` true
