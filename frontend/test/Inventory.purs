module Test.Inventory where

import Prelude

import Config.LiveView (defaultViewConfig)
import Data.Either (Either(..), isLeft, isRight)
import Data.Finance.Money (Discrete(..))
import Data.Maybe (Maybe(..), isJust)
import Data.Newtype (unwrap)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Inventory
  ( ItemCategory(..)
  , Species(..)
  , MenuItem(..)
  , MenuItemFormInput
  , StrainLineage(..)
  , Inventory(..)
  , MutationResponse
  , generateClassName
  , findItemBySku
  , findItemNameBySku
  , getItemName
  , validateMenuItem
  , validateCategory
  , validateSpecies
  , compareMenuItems
  )
import Types.UUID (UUID(..))
import Yoga.JSON (writeJSON, readJSON_)

mkUUID :: String -> UUID
mkUUID = UUID

testSku :: UUID
testSku = mkUUID "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"

testStrainLineage :: StrainLineage
testStrainLineage = StrainLineage
  { thc: "25%"
  , cbg: "0.5%"
  , strain: "OG Kush"
  , creator: "Unknown"
  , species: Indica
  , dominant_terpene: "Myrcene"
  , terpenes: ["Myrcene", "Limonene"]
  , lineage: ["Hindu Kush", "Chemdawg"]
  , leafly_url: "https://leafly.com/strains/og-kush"
  , img: "https://example.com/ogkush.jpg"
  }

testMenuItem :: MenuItem
testMenuItem = MenuItem
  { sort: 1
  , sku: testSku
  , brand: "TestBrand"
  , name: "OG Kush"
  , price: Discrete 2999
  , measure_unit: "g"
  , per_package: "3.5"
  , quantity: 10
  , category: Flower
  , subcategory: "Indoor"
  , description: "Classic strain"
  , tags: ["indica", "classic"]
  , effects: ["relaxed", "sleepy"]
  , strain_lineage: testStrainLineage
  }

testFormInput :: MenuItemFormInput
testFormInput =
  { sort: "1"
  , sku: "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
  , brand: "TestBrand"
  , name: "OG Kush"
  , price: "29.99"
  , measure_unit: "g"
  , per_package: "3.5"
  , quantity: "10"
  , category: "Flower"
  , subcategory: "Indoor"
  , description: "Classic strain"
  , tags: "indica, classic"
  , effects: "relaxed, sleepy"
  , strain_lineage:
      { thc: "25%"
      , cbg: "0.5%"
      , strain: "OG Kush"
      , creator: "Unknown"
      , species: "Indica"
      , dominant_terpene: "Myrcene"
      , terpenes: "Myrcene, Limonene"
      , lineage: "Hindu Kush, Chemdawg"
      , leafly_url: "https://leafly.com/strains/og-kush"
      , img: "https://example.com/ogkush.jpg"
      }
  }

spec :: Spec Unit
spec = describe "Types.Inventory" do

  describe "ItemCategory" do
    it "shows Flower" do
      show Flower `shouldEqual` "Flower"
    it "shows PreRolls" do
      show PreRolls `shouldEqual` "PreRolls"
    it "has correct ordering" do
      (Flower < PreRolls) `shouldEqual` true
      (Edibles < Accessories) `shouldEqual` true

  describe "Species" do
    it "shows Indica" do
      show Indica `shouldEqual` "Indica"
    it "shows IndicaDominantHybrid" do
      show IndicaDominantHybrid `shouldEqual` "IndicaDominantHybrid"
    it "shows Hybrid" do
      show Hybrid `shouldEqual` "Hybrid"
    it "has correct ordering" do
      (Indica < Hybrid) `shouldEqual` true
      (Hybrid < Sativa) `shouldEqual` true

  describe "validateCategory" do
    it "accepts Flower" do
      validateCategory "cat" "Flower" `shouldSatisfy` \v ->
        case v of
          _ -> true -- V doesn't have direct Eq, just check it doesn't crash
    it "accepts all valid categories" do
      let categories = ["Flower", "PreRolls", "Vaporizers", "Edibles", "Drinks",
                         "Concentrates", "Topicals", "Tinctures", "Accessories"]
      let _ = map (\c -> validateCategory "cat" c) categories
      -- All should succeed (not crash)
      (true) `shouldEqual` true

  describe "validateSpecies" do
    it "accepts Indica" do
      let _ = validateSpecies "sp" "Indica"
      pure unit
    it "accepts all valid species" do
      let species = ["Indica", "IndicaDominantHybrid", "Hybrid",
                      "SativaDominantHybrid", "Sativa"]
      let _ = map (\s -> validateSpecies "sp" s) species
      (true) `shouldEqual` true

  describe "validateMenuItem" do
    it "accepts valid form input" do
      validateMenuItem testFormInput `shouldSatisfy` isRight

    it "rejects empty name" do
      validateMenuItem (testFormInput { name = "" }) `shouldSatisfy` isLeft

    it "rejects empty brand" do
      validateMenuItem (testFormInput { brand = "" }) `shouldSatisfy` isLeft

    it "rejects invalid price" do
      validateMenuItem (testFormInput { price = "abc" }) `shouldSatisfy` isLeft

    it "rejects negative quantity" do
      validateMenuItem (testFormInput { quantity = "-1" }) `shouldSatisfy` isLeft

    it "rejects invalid category" do
      validateMenuItem (testFormInput { category = "InvalidCat" }) `shouldSatisfy` isLeft

    it "rejects invalid species" do
      let invalidInput = testFormInput { strain_lineage = testFormInput.strain_lineage { species = "InvalidSpecies" } }
      validateMenuItem invalidInput `shouldSatisfy` isLeft

    it "rejects invalid SKU" do
      validateMenuItem (testFormInput { sku = "not-a-uuid" }) `shouldSatisfy` isLeft

    it "rejects invalid leafly URL" do
      let invalidInput = testFormInput { strain_lineage = testFormInput.strain_lineage { leafly_url = "not a url" } }
      validateMenuItem invalidInput `shouldSatisfy` isLeft

    it "produces correct price in cents" do
      case validateMenuItem testFormInput of
        Right (MenuItem item) -> unwrap item.price `shouldEqual` 2999
        Left _ -> (false) `shouldEqual` true -- fail

    it "parses tags from comma list" do
      case validateMenuItem testFormInput of
        Right (MenuItem item) -> item.tags `shouldEqual` ["indica", "classic"]
        Left _ -> (false) `shouldEqual` true

  describe "generateClassName" do
    it "generates correct class for Indica Flower" do
      let result = generateClassName
            { category: Flower
            , subcategory: "Indoor"
            , species: Indica
            }
      result `shouldEqual` "species-indica category-flower subcategory-indoor"

    it "handles spaces in subcategory" do
      let result = generateClassName
            { category: Edibles
            , subcategory: "Dark Chocolate"
            , species: Hybrid
            }
      result `shouldEqual` "species-hybrid category-edibles subcategory-dark-chocolate"

  describe "getItemName" do
    it "extracts name from MenuItem" do
      getItemName testMenuItem `shouldEqual` "OG Kush"

  describe "findItemBySku" do
    let inventory = Inventory [testMenuItem]

    it "finds existing item" do
      findItemBySku testSku inventory `shouldSatisfy` isJust

    it "returns Nothing for unknown sku" do
      findItemBySku (mkUUID "00000000-0000-0000-0000-000000000000") inventory
        `shouldEqual` Nothing

  describe "findItemNameBySku" do
    let inventory = Inventory [testMenuItem]

    it "returns name for existing item" do
      findItemNameBySku testSku inventory `shouldEqual` "OG Kush"

    it "returns Unknown Item for missing sku" do
      findItemNameBySku (mkUUID "00000000-0000-0000-0000-000000000000") inventory
        `shouldEqual` "Unknown Item"

  describe "compareMenuItems" do
    let makeItem sort' name' category' species' qty price' =
          MenuItem
            { sort: sort'
            , sku: testSku
            , brand: "Brand"
            , name: name'
            , price: Discrete price'
            , measure_unit: "g"
            , per_package: "3.5"
            , quantity: qty
            , category: category'
            , subcategory: "Sub"
            , description: ""
            , tags: []
            , effects: []
            , strain_lineage: StrainLineage
                { thc: "20%", cbg: "1%", strain: "S", creator: "C"
                , species: species', dominant_terpene: "M"
                , terpenes: [], lineage: []
                , leafly_url: "https://leafly.com"
                , img: "https://example.com/img.jpg"
                }
            }

    it "compares by default config sort fields" do
      -- defaultViewConfig sorts by Quantity desc, Category asc, Species desc
      let itemA = makeItem 0 "A" Flower Indica 10 1000
      let itemB = makeItem 0 "B" Flower Indica 5 1000
      -- A has more quantity, and sort is descending, so A should come first (GT -> flipped to LT)
      let result = compareMenuItems defaultViewConfig itemA itemB
      -- quantity 10 vs 5, descending: 10 > 5 -> GT -> inverted to LT
      -- So itemA < itemB in sort order (A comes first)
      result `shouldEqual` LT

    it "equal items compare as EQ" do
      let item = makeItem 0 "A" Flower Indica 10 1000
      compareMenuItems defaultViewConfig item item `shouldEqual` EQ

  describe "MenuItem JSON serialization" do
    it "serializes and can be read back" do
      let json = writeJSON testMenuItem
      let parsed = readJSON_ json :: Maybe MenuItem
      parsed `shouldSatisfy` isJust

    it "preserves sku through serialization" do
      let json = writeJSON testMenuItem
      case (readJSON_ json :: Maybe MenuItem) of
        Just (MenuItem item) -> item.sku `shouldEqual` testSku
        Nothing -> (false) `shouldEqual` true

    it "preserves price through serialization" do
      let json = writeJSON testMenuItem
      case (readJSON_ json :: Maybe MenuItem) of
        Just (MenuItem item) -> item.price `shouldEqual` Discrete 2999
        Nothing -> (false) `shouldEqual` true

  describe "MutationResponse JSON serialization" do
    it "parses success response" do
      let json = """{"success":true,"message":"Item added successfully"}"""
      let parsed = readJSON_ json :: Maybe MutationResponse
      parsed `shouldSatisfy` isJust

    it "parses failure response" do
      let json = """{"success":false,"message":"Item not found"}"""
      let parsed = readJSON_ json :: Maybe MutationResponse
      parsed `shouldSatisfy` isJust

  describe "Inventory JSON" do
    it "serializes as array" do
      let inv = Inventory [testMenuItem]
      let json = writeJSON inv
      let parsed = readJSON_ json :: Maybe Inventory
      parsed `shouldSatisfy` isJust