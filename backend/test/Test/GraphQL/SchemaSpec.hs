{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot   #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# OPTIONS_GHC -Wno-ambiguous-fields #-}

module Test.GraphQL.SchemaSpec (spec) where

import Test.Hspec
import GraphQL.Schema

-- ──────────────────────────────────────────────
-- Fixtures
-- ──────────────────────────────────────────────

testStrainLineageGql :: StrainLineageGql
testStrainLineageGql = StrainLineageGql
  { thc              = "25%"
  , cbg              = "0.5%"
  , strain           = "OG Kush"
  , creator          = "Unknown"
  , species          = "Indica"
  , dominant_terpene = "Myrcene"
  , terpenes         = ["Myrcene", "Limonene", "Caryophyllene"]
  , lineage          = ["Hindu Kush", "Chemdawg"]
  , leafly_url       = "https://www.leafly.com/strains/og-kush"
  , img              = "https://example.com/ogkush.jpg"
  }

testStrainLineageInputGql :: StrainLineageInputGql
testStrainLineageInputGql = StrainLineageInputGql
  { thc              = "25%"
  , cbg              = "0.5%"
  , strain           = "OG Kush"
  , creator          = "Unknown"
  , species          = "Indica"
  , dominant_terpene = "Myrcene"
  , terpenes         = ["Myrcene", "Limonene"]
  , lineage          = ["Hindu Kush", "Chemdawg"]
  , leafly_url       = "https://www.leafly.com/strains/og-kush"
  , img              = "https://example.com/ogkush.jpg"
  }

testMenuItemGql :: MenuItemGql
testMenuItemGql = MenuItemGql
  { sort           = 1
  , sku            = "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
  , brand          = "TestBrand"
  , name           = "OG Kush"
  , price          = 2999
  , measure_unit   = "g"
  , per_package    = "3.5"
  , quantity       = 10
  , category       = "Flower"
  , subcategory    = "Indoor"
  , description    = "Classic indica-dominant strain"
  , tags           = ["indica", "classic", "relaxing"]
  , effects        = ["relaxed", "sleepy", "happy"]
  , strain_lineage = testStrainLineageGql
  }

testMenuItemInputGql :: MenuItemInputGql
testMenuItemInputGql = MenuItemInputGql
  { sort           = 1
  , sku            = "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
  , brand          = "TestBrand"
  , name           = "OG Kush"
  , price          = 2999
  , measure_unit   = "g"
  , per_package    = "3.5"
  , quantity       = 10
  , category       = "Flower"
  , subcategory    = "Indoor"
  , description    = "Classic indica-dominant strain"
  , tags           = ["indica", "classic"]
  , effects        = ["relaxed", "sleepy"]
  , strain_lineage = testStrainLineageInputGql
  }

spec :: Spec
spec = describe "GraphQL.Schema" $ do

  -- ──────────────────────────────────────────────
  -- StrainLineageGql
  -- ──────────────────────────────────────────────
  describe "StrainLineageGql" $ do
    it "preserves strain"           $ testStrainLineageGql.strain           `shouldBe` "OG Kush"
    it "preserves thc"              $ testStrainLineageGql.thc               `shouldBe` "25%"
    it "preserves cbg"              $ testStrainLineageGql.cbg               `shouldBe` "0.5%"
    it "preserves creator"          $ testStrainLineageGql.creator           `shouldBe` "Unknown"
    it "preserves species as Text"  $ testStrainLineageGql.species           `shouldBe` "Indica"
    it "preserves dominant_terpene" $ testStrainLineageGql.dominant_terpene  `shouldBe` "Myrcene"
    it "preserves leafly_url"       $ testStrainLineageGql.leafly_url        `shouldBe` "https://www.leafly.com/strains/og-kush"
    it "preserves img"              $ testStrainLineageGql.img               `shouldBe` "https://example.com/ogkush.jpg"

    it "preserves terpenes list" $
      testStrainLineageGql.terpenes `shouldBe` ["Myrcene", "Limonene", "Caryophyllene"]

    it "preserves lineage list" $
      testStrainLineageGql.lineage `shouldBe` ["Hindu Kush", "Chemdawg"]

    -- Use mkSL helper to avoid DuplicateRecordFields ambiguous-update warnings
    it "accepts empty terpenes list" $
      (mkSL testStrainLineageGql (\sl -> sl { terpenes = [] })).terpenes `shouldBe` []

    it "accepts empty lineage list" $
      (mkSL testStrainLineageGql (\sl -> sl { lineage = [] })).lineage `shouldBe` []

    it "accepts all species as Text" $ do
      let speciesValues = ["Indica", "IndicaDominantHybrid", "Hybrid", "SativaDominantHybrid", "Sativa"]
      mapM_ (\s ->
        (mkSL testStrainLineageGql (\sl -> sl { species = s })).species `shouldBe` s
        ) speciesValues

  -- ──────────────────────────────────────────────
  -- MenuItemGql
  -- ──────────────────────────────────────────────
  describe "MenuItemGql" $ do
    it "preserves name"         $ testMenuItemGql.name         `shouldBe` "OG Kush"
    it "preserves sort"         $ testMenuItemGql.sort         `shouldBe` 1
    it "preserves sku as Text"  $ testMenuItemGql.sku          `shouldBe` "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
    it "preserves brand"        $ testMenuItemGql.brand        `shouldBe` "TestBrand"
    it "preserves price"        $ testMenuItemGql.price        `shouldBe` 2999
    it "preserves measure_unit" $ testMenuItemGql.measure_unit `shouldBe` "g"
    it "preserves per_package"  $ testMenuItemGql.per_package  `shouldBe` "3.5"
    it "preserves quantity"     $ testMenuItemGql.quantity     `shouldBe` 10
    it "preserves category"     $ testMenuItemGql.category     `shouldBe` "Flower"
    it "preserves subcategory"  $ testMenuItemGql.subcategory  `shouldBe` "Indoor"
    it "preserves description"  $ testMenuItemGql.description  `shouldBe` "Classic indica-dominant strain"

    it "preserves tags list" $
      testMenuItemGql.tags `shouldBe` ["indica", "classic", "relaxing"]

    it "preserves effects list" $
      testMenuItemGql.effects `shouldBe` ["relaxed", "sleepy", "happy"]

    -- StrainLineageGql has no Eq — compare fields individually.
    -- Add `deriving Eq` to StrainLineageGql in GraphQL.Schema to
    -- restore the single-line `shouldBe testStrainLineageGql` version.
    it "preserves nested strain_lineage" $ do
      let sl = testMenuItemGql.strain_lineage
      sl.thc              `shouldBe` testStrainLineageGql.thc
      sl.cbg              `shouldBe` testStrainLineageGql.cbg
      sl.strain           `shouldBe` testStrainLineageGql.strain
      sl.creator          `shouldBe` testStrainLineageGql.creator
      sl.species          `shouldBe` testStrainLineageGql.species
      sl.dominant_terpene `shouldBe` testStrainLineageGql.dominant_terpene
      sl.terpenes         `shouldBe` testStrainLineageGql.terpenes
      sl.lineage          `shouldBe` testStrainLineageGql.lineage
      sl.leafly_url       `shouldBe` testStrainLineageGql.leafly_url
      sl.img              `shouldBe` testStrainLineageGql.img

    it "accepts all category strings" $ do
      let cats = ["Flower", "PreRolls", "Vaporizers", "Edibles", "Drinks",
                  "Concentrates", "Topicals", "Tinctures", "Accessories"]
      mapM_ (\c ->
        (mkMI testMenuItemGql (\i -> i { category = c })).category `shouldBe` c
        ) cats

    it "accepts empty tags" $
      (mkMI testMenuItemGql (\i -> i { tags = [] })).tags `shouldBe` []

    it "accepts empty effects" $
      (mkMI testMenuItemGql (\i -> i { effects = [] })).effects `shouldBe` []

  -- ──────────────────────────────────────────────
  -- MutationResponseGql
  -- ──────────────────────────────────────────────
  describe "MutationResponseGql" $ do
    it "constructs success response" $ do
      let r = MutationResponseGql True "Item created successfully"
      r.success `shouldBe` True
      r.message `shouldBe` "Item created successfully"

    it "constructs failure response" $ do
      let r = MutationResponseGql False "Forbidden: cannot create items"
      r.success `shouldBe` False
      r.message `shouldBe` "Forbidden: cannot create items"

  -- ──────────────────────────────────────────────
  -- MenuItemInputGql
  -- ──────────────────────────────────────────────
  describe "MenuItemInputGql" $ do
    it "preserves name"     $ testMenuItemInputGql.name     `shouldBe` "OG Kush"
    it "preserves sku"      $ testMenuItemInputGql.sku      `shouldBe` "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
    it "preserves category" $ testMenuItemInputGql.category `shouldBe` "Flower"

    it "preserves nested strain_lineage species" $
      testMenuItemInputGql.strain_lineage.species `shouldBe` "Indica"

  -- ──────────────────────────────────────────────
  -- StrainLineageInputGql
  -- ──────────────────────────────────────────────
  describe "StrainLineageInputGql" $ do
    it "preserves strain"  $ testStrainLineageInputGql.strain  `shouldBe` "OG Kush"
    it "preserves species" $ testStrainLineageInputGql.species `shouldBe` "Indica"

    it "preserves terpenes list" $
      testStrainLineageInputGql.terpenes `shouldBe` ["Myrcene", "Limonene"]

    it "preserves lineage list" $
      testStrainLineageInputGql.lineage `shouldBe` ["Hindu Kush", "Chemdawg"]

  -- ──────────────────────────────────────────────
  -- Arg types
  -- ──────────────────────────────────────────────
  describe "MenuItemArgs" $ do
    it "preserves sku field" $ do
      let args = MenuItemArgs { sku = "some-uuid" }
      args.sku `shouldBe` "some-uuid"

  describe "CreateMenuItemArgs" $ do
    it "preserves input.name" $ do
      let args = CreateMenuItemArgs { input = testMenuItemInputGql }
      args.input.name `shouldBe` "OG Kush"

  describe "UpdateMenuItemArgs" $ do
    it "preserves input.price" $ do
      let args = UpdateMenuItemArgs { input = testMenuItemInputGql }
      args.input.price `shouldBe` 2999

  describe "DeleteMenuItemArgs" $ do
    it "preserves sku field" $ do
      let args = DeleteMenuItemArgs { sku = "4e58b3e6-3fd4-425c-b6a3-4f033a76859c" }
      args.sku `shouldBe` "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"

-- ──────────────────────────────────────────────
-- Helpers: avoid DuplicateRecordFields ambiguous-update
-- warnings by wrapping record updates in typed helpers.
-- ──────────────────────────────────────────────

mkSL :: StrainLineageGql -> (StrainLineageGql -> StrainLineageGql) -> StrainLineageGql
mkSL base f = f base

mkMI :: MenuItemGql -> (MenuItemGql -> MenuItemGql) -> MenuItemGql
mkMI base f = f base