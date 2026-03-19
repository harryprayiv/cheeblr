{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.Effect.InventoryDbSpec (spec) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.UUID (UUID)
import qualified Data.Vector as V
import Effectful ( Eff, runPureEff, runPureEff )
import Test.Hspec

import Effect.InventoryDb
import Types.Inventory

testUUID :: UUID
testUUID = read "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

testUUID2 :: UUID
testUUID2 = read "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

testStrainLineage :: StrainLineage
testStrainLineage = StrainLineage
  { thc              = "20%"
  , cbg              = "1%"
  , strain           = "Test Strain"
  , creator          = "Test"
  , species          = Indica
  , dominant_terpene = "Myrcene"
  , terpenes         = V.fromList ["Myrcene"]
  , lineage          = V.fromList []
  , leafly_url       = "https://leafly.com"
  , img              = "https://example.com/img.jpg"
  }

mkItem :: UUID -> String -> MenuItem
mkItem u n = MenuItem
  { sort           = 1
  , sku            = u
  , brand          = "TestBrand"
  , name           = read (show n)
  , price          = 1000
  , measure_unit   = "g"
  , per_package    = "1"
  , quantity       = 10
  , category       = Flower
  , subcategory    = "Indoor"
  , description    = "Test"
  , tags           = V.empty
  , effects        = V.empty
  , strain_lineage = testStrainLineage
  }

testItem :: MenuItem
testItem = mkItem testUUID "OG Kush"

runPure :: Map UUID MenuItem -> Eff '[InventoryDb] a -> IO (a, Map UUID MenuItem)
runPure store action = pure $ runPureEff $ runInventoryDbPure store action

runPure_ :: Map UUID MenuItem -> Eff '[InventoryDb] a -> IO a
runPure_ store action = fst <$> runPure store action

spec :: Spec
spec = describe "Effect.InventoryDb pure interpreter" $ do

  describe "getAllMenuItems" $ do
    it "returns empty Inventory for empty store" $ do
      Inventory invItems <- runPure_ Map.empty getAllMenuItems
      V.length invItems `shouldBe` 0

    it "returns all items from the store" $ do
      let store = Map.singleton testUUID testItem
      Inventory invItems <- runPure_ store getAllMenuItems
      V.length invItems `shouldBe` 1

    it "returns items with correct SKUs" $ do
      let item2 = mkItem testUUID2 "Blue Dream"
          store = Map.fromList [(testUUID, testItem), (testUUID2, item2)]
      Inventory invItems <- runPure_ store getAllMenuItems
      V.length invItems `shouldBe` 2

  describe "insertMenuItem" $ do
    it "adds item to the store" $ do
      (result, store') <- runPure Map.empty (insertMenuItem testItem)
      case result of
        Left e  -> expectationFailure $ "Expected Right () but got: " <> show e
        Right _ -> Map.size store' `shouldBe` 1

    it "inserted item is retrievable via getAllMenuItems" $ do
      (Inventory invItems, _) <- runPure Map.empty $ do
        _ <- insertMenuItem testItem
        getAllMenuItems
      V.length invItems `shouldBe` 1

    it "inserting two distinct items gives store of size 2" $ do
      let item2 = mkItem testUUID2 "Blue Dream"
      (_, store') <- runPure Map.empty $ do
        _ <- insertMenuItem testItem
        insertMenuItem item2
      Map.size store' `shouldBe` 2
      
  describe "updateMenuItem" $ do
    it "overwrites existing item" $ do
      let updated = testItem { price = 9999 }
          store   = Map.singleton testUUID testItem
      (result, store') <- runPure store (updateMenuItem updated)
      case result of
        Left e  -> expectationFailure $ "Expected Right () but got: " <> show e
        Right _ -> fmap price (Map.lookup testUUID store') `shouldBe` Just 9999

    it "does not change store size" $ do
      let updated = testItem { price = 5000 }
          store   = Map.singleton testUUID testItem
      (result, store') <- runPure store (updateMenuItem updated)
      case result of
        Left e  -> expectationFailure $ "Expected Right () but got: " <> show e
        Right _ -> Map.size store' `shouldBe` 1

  describe "deleteMenuItem" $ do
    it "removes an existing item and reports success" $ do
      let store = Map.singleton testUUID testItem
      (resp, store') <- runPure store (deleteMenuItem testUUID)
      success resp `shouldBe` True
      Map.member testUUID store' `shouldBe` False

    it "returns failure for a non-existent SKU" $ do
      resp <- runPure_ Map.empty (deleteMenuItem testUUID)
      success resp `shouldBe` False

    it "does not affect other items" $ do
      let item2 = mkItem testUUID2 "Blue Dream"
          store = Map.fromList [(testUUID, testItem), (testUUID2, item2)]
      (_, store') <- runPure store (deleteMenuItem testUUID)
      Map.member testUUID2 store' `shouldBe` True
      Map.size store' `shouldBe` 1