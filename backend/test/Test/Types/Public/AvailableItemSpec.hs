{-# LANGUAGE OverloadedStrings #-}

module Test.Types.Public.AvailableItemSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Maybe      (isJust, isNothing)
import Data.Time       (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.UUID       (UUID)
import qualified Data.Vector as V
import Test.Hspec

import Infrastructure.AvailabilityState
import Types.Inventory
import Types.Public.AvailableItem

testTime :: UTCTime
testTime = UTCTime (fromGregorian 2024 1 1) 0

testSku :: UUID
testSku = read "00000000-0000-0000-0000-000000000001"

testLocId :: PublicLocationId
testLocId = PublicLocationId (read "00000000-0000-0000-0000-000000000002")

testMenuItem :: MenuItem
testMenuItem = MenuItem
  { sort           = 1
  , sku            = testSku
  , brand          = "Test Brand"
  , name           = "Test Item"
  , price          = 1000
  , measure_unit   = "g"
  , per_package    = "3.5"
  , quantity       = 10
  , category       = Flower
  , subcategory    = "Indoor"
  , description    = "Test"
  , tags           = V.fromList ["test"]
  , effects        = V.fromList ["relaxed"]
  , strain_lineage = StrainLineage
      { thc              = "25%"
      , cbg              = "1%"
      , strain           = "Test Strain"
      , creator          = "Test Creator"
      , species          = Hybrid
      , dominant_terpene = "Myrcene"
      , terpenes         = V.fromList ["Myrcene"]
      , lineage          = V.fromList []
      , leafly_url       = "https://leafly.com/test"
      , img              = "https://example.com/img.jpg"
      }
  }

testState :: AvailabilityState
testState = AvailabilityState
  { asItems       = Map.singleton testSku testMenuItem
  , asReserved    = Map.empty
  , asPublicLocId = testLocId
  , asLocName     = "Test Location"
  }

spec :: Spec
spec = describe "AvailableItem" $ do

  describe "availableQty" $ do
    it "is total minus reserved" $ do
      let st = testState { asReserved = Map.singleton testSku 3 }
      availableQty st testSku `shouldBe` 7

    it "never goes below zero" $ do
      let st = testState { asReserved = Map.singleton testSku 999 }
      availableQty st testSku `shouldBe` 0

    it "is zero for unknown sku" $ do
      let unknownSku = read "00000000-0000-0000-0000-000000000099" :: UUID
      availableQty testState unknownSku `shouldBe` 0

  describe "mkAvailableItem" $ do
    it "inStock is false when availableQty is zero" $ do
      let ai = mkAvailableItem testMenuItem 0 testLocId "Test" testTime
      aiInStock ai `shouldBe` False

    it "inStock is true when availableQty is positive" $ do
      let ai = mkAvailableItem testMenuItem 5 testLocId "Test" testTime
      aiInStock ai `shouldBe` True

    it "aiAvailableQty is clamped to zero for negative input" $ do
      let ai = mkAvailableItem testMenuItem (-3) testLocId "Test" testTime
      aiAvailableQty ai `shouldBe` 0

    it "carries correct price" $ do
      let ai = mkAvailableItem testMenuItem 5 testLocId "Test" testTime
      aiPricePerUnit ai `shouldBe` 1000

    it "has no transaction, employee, session, or register fields in JSON" $ do
      let ai   = mkAvailableItem testMenuItem 5 testLocId "Test" testTime
          json = show ai   -- just structural: the type has no such fields
      json `shouldNotContain` "transactionId"
      json `shouldNotContain` "employeeId"
      json `shouldNotContain` "sessionId"
      json `shouldNotContain` "registerId"

  describe "toAvailableItem" $ do
    it "returns Nothing for unknown sku" $ do
      let unknownSku = read "00000000-0000-0000-0000-000000000099" :: UUID
      toAvailableItem testState unknownSku testTime `shouldSatisfy` isNothing

    it "returns Just for known sku" $ do
      toAvailableItem testState testSku testTime `shouldSatisfy` isJust

    it "reflects reserved quantity" $ do
      let st = testState { asReserved = Map.singleton testSku 4 }
      case toAvailableItem st testSku testTime of
        Nothing -> expectationFailure "expected Just"
        Just ai -> aiAvailableQty ai `shouldBe` 6