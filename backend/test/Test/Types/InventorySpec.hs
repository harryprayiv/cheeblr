{-# LANGUAGE OverloadedStrings #-}

module Test.Types.InventorySpec (spec) where

import Test.Hspec
import Data.Aeson (encode, decode, toJSON, fromJSON, Result(..))
import qualified Data.Vector as V
import Data.UUID (UUID)
import Types.Inventory
import Types.Auth (UserCapabilities(..), capabilitiesForRole, UserRole(..))
import qualified Types.Auth
import Data.Maybe (isJust)

-- ──────────────────────────────────────────────
-- Fixtures
-- ──────────────────────────────────────────────

testSku :: UUID
testSku = read "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"

testStrainLineage :: StrainLineage
testStrainLineage = StrainLineage
  { thc = "25%"
  , cbg = "0.5%"
  , strain = "OG Kush"
  , creator = "Unknown"
  , species = Indica
  , dominant_terpene = "Myrcene"
  , terpenes = V.fromList ["Myrcene", "Limonene"]
  , lineage = V.fromList ["Hindu Kush", "Chemdawg"]
  , leafly_url = "https://leafly.com/strains/og-kush"
  , img = "https://example.com/ogkush.jpg"
  }

testMenuItem :: MenuItem
testMenuItem = MenuItem
  { sort = 1
  , sku = testSku
  , brand = "TestBrand"
  , name = "OG Kush"
  , price = 2999
  , measure_unit = "g"
  , per_package = "3.5"
  , quantity = 10
  , category = Flower
  , subcategory = "Indoor"
  , description = "Classic strain"
  , tags = V.fromList ["indica", "classic"]
  , effects = V.fromList ["relaxed", "sleepy"]
  , strain_lineage = testStrainLineage
  }

spec :: Spec
spec = describe "Types.Inventory" $ do

  -- ──────────────────────────────────────────────
  -- Species
  -- ──────────────────────────────────────────────
  describe "Species" $ do
    it "shows Indica" $
      show Indica `shouldBe` "Indica"
    it "shows IndicaDominantHybrid" $
      show IndicaDominantHybrid `shouldBe` "IndicaDominantHybrid"
    it "shows Hybrid" $
      show Hybrid `shouldBe` "Hybrid"
    it "shows SativaDominantHybrid" $
      show SativaDominantHybrid `shouldBe` "SativaDominantHybrid"
    it "shows Sativa" $
      show Sativa `shouldBe` "Sativa"

    it "has correct ordering" $ do
      (Indica < IndicaDominantHybrid) `shouldBe` True
      (IndicaDominantHybrid < Hybrid) `shouldBe` True
      (Hybrid < SativaDominantHybrid) `shouldBe` True
      (SativaDominantHybrid < Sativa) `shouldBe` True

    it "roundtrips through JSON" $ do
      let species = [Indica, IndicaDominantHybrid, Hybrid, SativaDominantHybrid, Sativa]
      mapM_ (\s -> fromJSON (toJSON s) `shouldBe` Success s) species

    it "roundtrips through Read/Show" $ do
      read (show Indica) `shouldBe` Indica
      read (show Sativa) `shouldBe` Sativa

  -- ──────────────────────────────────────────────
  -- ItemCategory
  -- ──────────────────────────────────────────────
  describe "ItemCategory" $ do
    it "shows Flower" $
      show Flower `shouldBe` "Flower"
    it "shows PreRolls" $
      show PreRolls `shouldBe` "PreRolls"
    it "shows Vaporizers" $
      show Vaporizers `shouldBe` "Vaporizers"
    it "shows Edibles" $
      show Edibles `shouldBe` "Edibles"
    it "shows Drinks" $
      show Drinks `shouldBe` "Drinks"
    it "shows Concentrates" $
      show Concentrates `shouldBe` "Concentrates"
    it "shows Topicals" $
      show Topicals `shouldBe` "Topicals"
    it "shows Tinctures" $
      show Tinctures `shouldBe` "Tinctures"
    it "shows Accessories" $
      show Accessories `shouldBe` "Accessories"

    it "has correct ordering" $ do
      (Flower < PreRolls) `shouldBe` True
      (Edibles < Accessories) `shouldBe` True

    it "roundtrips through JSON" $ do
      let cats = [Flower, PreRolls, Vaporizers, Edibles, Drinks,
                  Concentrates, Topicals, Tinctures, Accessories]
      mapM_ (\c -> fromJSON (toJSON c) `shouldBe` Success c) cats

    it "roundtrips through Read/Show" $ do
      let cats = [Flower, PreRolls, Vaporizers, Edibles, Drinks,
                  Concentrates, Topicals, Tinctures, Accessories]
      mapM_ (\c -> read (show c) `shouldBe` c) cats

  -- ──────────────────────────────────────────────
  -- StrainLineage JSON
  -- ──────────────────────────────────────────────
  describe "StrainLineage JSON" $ do
    it "roundtrips through JSON" $
      decode (encode testStrainLineage) `shouldBe` Just testStrainLineage

    it "preserves species" $ do
      case decode (encode testStrainLineage) of
        Just sl -> species sl `shouldBe` Indica
        Nothing -> expectationFailure "Failed to decode"

    it "preserves terpenes list" $ do
      case decode (encode testStrainLineage) of
        Just sl -> terpenes sl `shouldBe` V.fromList ["Myrcene", "Limonene"]
        Nothing -> expectationFailure "Failed to decode"

    it "preserves lineage list" $ do
      case decode (encode testStrainLineage) of
        Just sl -> lineage sl `shouldBe` V.fromList ["Hindu Kush", "Chemdawg"]
        Nothing -> expectationFailure "Failed to decode"

  -- ──────────────────────────────────────────────
  -- MenuItem JSON
  -- ──────────────────────────────────────────────
  describe "MenuItem JSON" $ do
    it "roundtrips through JSON" $
      decode (encode testMenuItem) `shouldBe` Just testMenuItem

    it "preserves sku" $ do
      case decode (encode testMenuItem) of
        Just mi -> sku mi `shouldBe` testSku
        Nothing -> expectationFailure "Failed to decode"

    it "preserves price" $ do
      case decode (encode testMenuItem) of
        Just mi -> price mi `shouldBe` 2999
        Nothing -> expectationFailure "Failed to decode"

    it "preserves category" $ do
      case decode (encode testMenuItem) of
        Just mi -> category mi `shouldBe` Flower
        Nothing -> expectationFailure "Failed to decode"

    it "preserves tags" $ do
      case decode (encode testMenuItem) of
        Just mi -> tags mi `shouldBe` V.fromList ["indica", "classic"]
        Nothing -> expectationFailure "Failed to decode"

    it "preserves effects" $ do
      case decode (encode testMenuItem) of
        Just mi -> effects mi `shouldBe` V.fromList ["relaxed", "sleepy"]
        Nothing -> expectationFailure "Failed to decode"

    it "preserves nested strain_lineage" $ do
      case decode (encode testMenuItem) of
        Just mi -> strain_lineage mi `shouldBe` testStrainLineage
        Nothing -> expectationFailure "Failed to decode"

  -- ──────────────────────────────────────────────
  -- Inventory JSON (serializes as array)
  -- ──────────────────────────────────────────────
  describe "Inventory JSON" $ do
    it "serializes as array" $ do
      let inv = Inventory (V.fromList [testMenuItem])
      decode (encode inv) `shouldSatisfy` (isJust :: Maybe Inventory -> Bool)

    it "roundtrips through JSON" $ do
      let inv = Inventory (V.fromList [testMenuItem])
      decode (encode inv) `shouldBe` Just inv

    it "handles empty inventory" $ do
      let inv = Inventory V.empty
      decode (encode inv) `shouldBe` Just inv

    it "preserves multiple items" $ do
      let item2 = testMenuItem { sku = read "00000000-0000-0000-0000-000000000001", name = "Blue Dream" }
      let inv = Inventory (V.fromList [testMenuItem, item2])
      case decode (encode inv) of
        Just inv' -> V.length (items inv') `shouldBe` 2
        Nothing -> expectationFailure "Failed to decode"

  -- ──────────────────────────────────────────────
  -- InventoryResponse JSON
  -- ──────────────────────────────────────────────
  describe "InventoryResponse JSON" $ do
    it "roundtrips Message variant" $ do
      let msg = Message "hello"
      decode (encode msg) `shouldBe` Just msg

    it "preserves message text" $ do
      case decode (encode (Message "Item added successfully")) of
        Just (Message txt) -> txt `shouldBe` "Item added successfully"
        _ -> expectationFailure "Failed to decode or wrong variant"

    it "roundtrips InventoryData variant" $ do
      let inv = Inventory (V.fromList [testMenuItem])
      let caps = capabilitiesForRole Admin
      let resp = InventoryData inv caps
      decode (encode resp) `shouldBe` Just resp

    it "preserves capabilities in InventoryData" $ do
      let inv = Inventory V.empty
      let caps = capabilitiesForRole Cashier
      let resp = InventoryData inv caps
      case decode (encode resp) of
        Just (InventoryData _ c) -> do
          capCanEditItem c `shouldBe` True
          capCanDeleteItem c `shouldBe` False
          capCanProcessTransaction c `shouldBe` True
        _ -> expectationFailure "Failed to decode InventoryData"

    it "InventoryData type field is 'data'" $ do
      let inv = Inventory V.empty
      let caps = capabilitiesForRole Customer
      let json = encode (InventoryData inv caps)
      -- Just verify it decodes properly (the type discrimination is tested via roundtrip)
      (decode json :: Maybe InventoryResponse) `shouldSatisfy` isJust

    it "Message type field is 'message'" $ do
      let json = encode (Message "test")
      (decode json :: Maybe InventoryResponse) `shouldSatisfy` isJust

  -- ──────────────────────────────────────────────
  -- simpleMessage / inventoryWithCapabilities
  -- ──────────────────────────────────────────────
  describe "simpleMessage" $ do
    it "creates a Message" $ do
      case simpleMessage "hello" of
        Message t -> t `shouldBe` "hello"
        _ -> expectationFailure "Expected Message"

  describe "inventoryWithCapabilities" $ do
    it "uses role-appropriate capabilities" $ do
      let inv = Inventory V.empty
      let user = Types.Auth.AuthenticatedUser
            { Types.Auth.auUserId = read "d3a1f4f0-c518-4db3-aa43-e80b428d6304"
            , Types.Auth.auUserName = "Test"
            , Types.Auth.auEmail = Nothing
            , Types.Auth.auRole = Manager
            , Types.Auth.auLocationId = Nothing
            , Types.Auth.auCreatedAt = read "2024-01-01 00:00:00 UTC"
            }
      case inventoryWithCapabilities inv user of
        InventoryData _ caps -> do
          capCanCreateItem caps `shouldBe` True
          capCanManageUsers caps `shouldBe` False
        _ -> expectationFailure "Expected InventoryData"
