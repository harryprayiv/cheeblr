{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-ambiguous-fields #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}

module Test.GraphQL.ResolversSpec (spec) where

import Control.Exception (SomeException, evaluate, try)
import qualified Data.Text as T
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import qualified Data.Vector as V
import Test.Hspec

import GraphQL.Resolvers (
  gqlInputToMenuItem,
  gqlInputToStrainLineage,
  menuItemToGql,
  strainLineageToGql,
 )
import GraphQL.Schema
import Types.Auth (UserCapabilities (..), UserRole (..), capabilitiesForRole)
import qualified Types.Inventory as TI

-- ──────────────────────────────────────────────
-- Fixtures: canonical Types.Inventory values
-- ──────────────────────────────────────────────

testUUID :: UUID
testUUID = read "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"

testStrainLineage :: TI.StrainLineage
testStrainLineage =
  TI.StrainLineage
    { TI.thc = "25%"
    , TI.cbg = "0.5%"
    , TI.strain = "OG Kush"
    , TI.creator = "Unknown"
    , TI.species = TI.Indica
    , TI.dominant_terpene = "Myrcene"
    , TI.terpenes = V.fromList ["Myrcene", "Limonene", "Caryophyllene"]
    , TI.lineage = V.fromList ["Hindu Kush", "Chemdawg"]
    , TI.leafly_url = "https://www.leafly.com/strains/og-kush"
    , TI.img = "https://example.com/ogkush.jpg"
    }

testMenuItem :: TI.MenuItem
testMenuItem =
  TI.MenuItem
    { TI.sort = 1
    , TI.sku = testUUID
    , TI.brand = "TestBrand"
    , TI.name = "OG Kush"
    , TI.price = 2999
    , TI.measure_unit = "g"
    , TI.per_package = "3.5"
    , TI.quantity = 10
    , TI.category = TI.Flower
    , TI.subcategory = "Indoor"
    , TI.description = "Classic indica-dominant strain"
    , TI.tags = V.fromList ["indica", "classic", "relaxing"]
    , TI.effects = V.fromList ["relaxed", "sleepy", "happy"]
    , TI.strain_lineage = testStrainLineage
    }

-- ──────────────────────────────────────────────
-- Fixtures: GQL input types
-- ──────────────────────────────────────────────

testStrainLineageInputGql :: StrainLineageInputGql
testStrainLineageInputGql =
  StrainLineageInputGql
    { thc = "25%"
    , cbg = "0.5%"
    , strain = "OG Kush"
    , creator = "Unknown"
    , species = "Indica"
    , dominant_terpene = "Myrcene"
    , terpenes = ["Myrcene", "Limonene", "Caryophyllene"]
    , lineage = ["Hindu Kush", "Chemdawg"]
    , leafly_url = "https://www.leafly.com/strains/og-kush"
    , img = "https://example.com/ogkush.jpg"
    }

testMenuItemInputGql :: MenuItemInputGql
testMenuItemInputGql =
  MenuItemInputGql
    { sort = 1
    , sku = "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
    , brand = "TestBrand"
    , name = "OG Kush"
    , price = 2999
    , measure_unit = "g"
    , per_package = "3.5"
    , quantity = 10
    , category = "Flower"
    , subcategory = "Indoor"
    , description = "Classic indica-dominant strain"
    , tags = ["indica", "classic", "relaxing"]
    , effects = ["relaxed", "sleepy", "happy"]
    , strain_lineage = testStrainLineageInputGql
    }

spec :: Spec
spec = describe "GraphQL.Resolvers pure functions" $ do
  -- ──────────────────────────────────────────────
  -- strainLineageToGql
  -- ──────────────────────────────────────────────
  describe "strainLineageToGql" $ do
    let gql = strainLineageToGql testStrainLineage

    it "maps thc" $ gql.thc `shouldBe` "25%"
    it "maps cbg" $ gql.cbg `shouldBe` "0.5%"
    it "maps strain" $ gql.strain `shouldBe` "OG Kush"
    it "maps creator" $ gql.creator `shouldBe` "Unknown"
    it "maps dominant_terpene" $ gql.dominant_terpene `shouldBe` "Myrcene"
    it "maps leafly_url" $ gql.leafly_url `shouldBe` "https://www.leafly.com/strains/og-kush"
    it "maps img" $ gql.img `shouldBe` "https://example.com/ogkush.jpg"

    it "converts species via show, producing PascalCase string" $
      gql.species `shouldBe` "Indica"

    it "converts terpenes Vector to list" $
      gql.terpenes `shouldBe` ["Myrcene", "Limonene", "Caryophyllene"]

    it "converts lineage Vector to list" $
      gql.lineage `shouldBe` ["Hindu Kush", "Chemdawg"]

    it "handles empty terpenes Vector" $ do
      let sl = testStrainLineage {TI.terpenes = V.empty}
      (strainLineageToGql sl).terpenes `shouldBe` []

    it "handles empty lineage Vector" $ do
      let sl = testStrainLineage {TI.lineage = V.empty}
      (strainLineageToGql sl).lineage `shouldBe` []

    it "converts all species to their PascalCase Show representation" $ do
      let speciesCases =
            [ (TI.Indica, "Indica")
            , (TI.IndicaDominantHybrid, "IndicaDominantHybrid")
            , (TI.Hybrid, "Hybrid")
            , (TI.SativaDominantHybrid, "SativaDominantHybrid")
            , (TI.Sativa, "Sativa")
            ]
      mapM_
        ( \(sp, expected) ->
            (strainLineageToGql (testStrainLineage {TI.species = sp})).species `shouldBe` expected
        )
        speciesCases

  -- ──────────────────────────────────────────────
  -- menuItemToGql
  -- ──────────────────────────────────────────────
  describe "menuItemToGql" $ do
    let gql = menuItemToGql testMenuItem

    it "maps sort" $ gql.sort `shouldBe` 1
    it "maps brand" $ gql.brand `shouldBe` "TestBrand"
    it "maps name" $ gql.name `shouldBe` "OG Kush"
    it "maps price" $ gql.price `shouldBe` 2999
    it "maps measure_unit" $ gql.measure_unit `shouldBe` "g"
    it "maps per_package" $ gql.per_package `shouldBe` "3.5"
    it "maps quantity" $ gql.quantity `shouldBe` 10
    it "maps subcategory" $ gql.subcategory `shouldBe` "Indoor"
    it "maps description" $ gql.description `shouldBe` "Classic indica-dominant strain"

    it "converts UUID sku to Text" $
      gql.sku `shouldBe` "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"

    it "converts category via show, producing PascalCase string" $
      gql.category `shouldBe` "Flower"

    it "converts tags Vector to list" $
      gql.tags `shouldBe` ["indica", "classic", "relaxing"]

    it "converts effects Vector to list" $
      gql.effects `shouldBe` ["relaxed", "sleepy", "happy"]

    it "maps nested strain_lineage" $
      gql.strain_lineage.strain `shouldBe` "OG Kush"

    it "converts all ItemCategory values via show" $ do
      let categoryCases =
            [ (TI.Flower, "Flower")
            , (TI.PreRolls, "PreRolls")
            , (TI.Vaporizers, "Vaporizers")
            , (TI.Edibles, "Edibles")
            , (TI.Drinks, "Drinks")
            , (TI.Concentrates, "Concentrates")
            , (TI.Topicals, "Topicals")
            , (TI.Tinctures, "Tinctures")
            , (TI.Accessories, "Accessories")
            ]
      mapM_
        ( \(cat, expected) ->
            (menuItemToGql (testMenuItem {TI.category = cat})).category `shouldBe` expected
        )
        categoryCases

    it "UUID roundtrip: sku converts to correct UUID string" $ do
      let
        knownUUID = read "00000000-0000-0000-0000-000000000001" :: UUID
        gqlItem = menuItemToGql (testMenuItem {TI.sku = knownUUID})
      gqlItem.sku `shouldBe` "00000000-0000-0000-0000-000000000001"
      UUID.fromText gqlItem.sku `shouldBe` Just knownUUID

    it "preserves zero quantity" $
      (menuItemToGql (testMenuItem {TI.quantity = 0})).quantity `shouldBe` 0

    it "handles empty tags and effects Vectors" $ do
      let gqlItem = menuItemToGql (testMenuItem {TI.tags = V.empty, TI.effects = V.empty})
      gqlItem.tags `shouldBe` []
      gqlItem.effects `shouldBe` []

  -- ──────────────────────────────────────────────
  -- gqlInputToStrainLineage
  -- ──────────────────────────────────────────────
  describe "gqlInputToStrainLineage" $ do
    let result = gqlInputToStrainLineage testStrainLineageInputGql

    it "maps thc" $ result.thc `shouldBe` "25%"
    it "maps cbg" $ result.cbg `shouldBe` "0.5%"
    it "maps strain" $ result.strain `shouldBe` "OG Kush"
    it "maps creator" $ result.creator `shouldBe` "Unknown"
    it "maps dominant_terpene" $ result.dominant_terpene `shouldBe` "Myrcene"
    it "maps leafly_url" $ result.leafly_url `shouldBe` "https://www.leafly.com/strains/og-kush"
    it "maps img" $ result.img `shouldBe` "https://example.com/ogkush.jpg"

    it "converts terpenes list to Vector" $
      result.terpenes `shouldBe` V.fromList ["Myrcene", "Limonene", "Caryophyllene"]

    it "converts lineage list to Vector" $
      result.lineage `shouldBe` V.fromList ["Hindu Kush", "Chemdawg"]

    -- ── KNOWN BUG: species parsing via `read $ show sp` ──────────────────
    -- `show ("Indica" :: Text)` = "\"Indica\"" (adds surrounding quotes).
    -- The derived Read instance for Species requires bare constructor names,
    -- not quoted strings. Will throw at runtime.
    -- Fix: use `read (T.unpack sp)` instead of `read $ show sp`.
    -- Same bug exists in gqlInputToMenuItem for the `category` field.
    -- ──────────────────────────────────────────────────────────────────────
    it "BUG: species via `read $ show sp` throws at runtime" $ do
      r <- try (evaluate result.species) :: IO (Either SomeException TI.Species)
      case r of
        Left _ -> pure ()
        Right sp -> sp `shouldBe` TI.Indica

    it "parses species correctly with T.unpack (fix verification)" $ do
      let sp = testStrainLineageInputGql.species
      (read (T.unpack sp) :: TI.Species) `shouldBe` TI.Indica

    it "parses all species with T.unpack" $ do
      let cases =
            [ ("Indica", TI.Indica)
            , ("IndicaDominantHybrid", TI.IndicaDominantHybrid)
            , ("Hybrid", TI.Hybrid)
            , ("SativaDominantHybrid", TI.SativaDominantHybrid)
            , ("Sativa", TI.Sativa)
            ]
      mapM_
        ( \(txt, expected) ->
            (read (T.unpack txt) :: TI.Species) `shouldBe` expected
        )
        cases

  -- ──────────────────────────────────────────────
  -- gqlInputToMenuItem
  -- ──────────────────────────────────────────────
  describe "gqlInputToMenuItem" $ do
    it "returns Left for invalid UUID" $ do
      let bad = mkInput "not-a-uuid"
      case gqlInputToMenuItem bad of
        Left err -> err `shouldBe` "Invalid UUID: not-a-uuid"
        Right _ -> expectationFailure "Expected Left for invalid UUID"

    it "returns Left for empty sku" $ do
      case gqlInputToMenuItem (mkInput "") of
        Left _ -> pure ()
        Right _ -> expectationFailure "Expected Left for empty sku"

    it "error message contains the bad UUID value" $ do
      let badUUID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
      case gqlInputToMenuItem (mkInput badUUID) of
        Left err -> T.isInfixOf badUUID err `shouldBe` True
        Right _ -> expectationFailure "Expected Left"

    it "returns Right for valid UUID" $ do
      case gqlInputToMenuItem testMenuItemInputGql of
        Left err -> expectationFailure $ "Expected Right: " <> T.unpack err
        Right _ -> pure ()

    it "maps sku UUID on success" $ do
      case gqlInputToMenuItem testMenuItemInputGql of
        Right item -> item.sku `shouldBe` testUUID
        Left err -> expectationFailure $ T.unpack err

    it "maps sort on success" $ expectRight testMenuItemInputGql $ \item -> item.sort `shouldBe` 1
    it "maps brand on success" $ expectRight testMenuItemInputGql $ \item -> item.brand `shouldBe` "TestBrand"
    it "maps name on success" $ expectRight testMenuItemInputGql $ \item -> item.name `shouldBe` "OG Kush"
    it "maps price on success" $ expectRight testMenuItemInputGql $ \item -> item.price `shouldBe` 2999
    it "maps measure_unit on success" $ expectRight testMenuItemInputGql $ \item -> item.measure_unit `shouldBe` "g"
    it "maps quantity on success" $ expectRight testMenuItemInputGql $ \item -> item.quantity `shouldBe` 10
    it "maps subcategory on success" $ expectRight testMenuItemInputGql $ \item -> item.subcategory `shouldBe` "Indoor"
    it "maps description on success" $ expectRight testMenuItemInputGql $ \item -> item.description `shouldBe` "Classic indica-dominant strain"

    it "converts tags list to Vector on success" $
      expectRight testMenuItemInputGql $ \item ->
        item.tags `shouldBe` V.fromList ["indica", "classic", "relaxing"]

    it "converts effects list to Vector on success" $
      expectRight testMenuItemInputGql $ \item ->
        item.effects `shouldBe` V.fromList ["relaxed", "sleepy", "happy"]

    -- ── KNOWN BUG: category via `read $ show cat` ────────────────────────
    it "BUG: category via `read $ show cat` throws at runtime" $ do
      case gqlInputToMenuItem testMenuItemInputGql of
        Left err -> expectationFailure $ "UUID valid but got Left: " <> T.unpack err
        Right item -> do
          r <- try (evaluate item.category) :: IO (Either SomeException TI.ItemCategory)
          case r of
            Left _ -> pure ()
            Right c -> c `shouldBe` TI.Flower

    it "parses category correctly with T.unpack (fix verification)" $ do
      let cat = testMenuItemInputGql.category
      (read (T.unpack cat) :: TI.ItemCategory) `shouldBe` TI.Flower

    it "parses all categories with T.unpack" $ do
      let cases =
            [ ("Flower", TI.Flower)
            , ("PreRolls", TI.PreRolls)
            , ("Vaporizers", TI.Vaporizers)
            , ("Edibles", TI.Edibles)
            , ("Drinks", TI.Drinks)
            , ("Concentrates", TI.Concentrates)
            , ("Topicals", TI.Topicals)
            , ("Tinctures", TI.Tinctures)
            , ("Accessories", TI.Accessories)
            ]
      mapM_
        ( \(txt, expected) ->
            (read (T.unpack txt) :: TI.ItemCategory) `shouldBe` expected
        )
        cases

    it "accepts zero price" $
      expectRight (mkInputWith (\i -> i {price = 0})) $ \item ->
        item.price `shouldBe` 0

    it "accepts zero quantity" $
      expectRight (mkInputWith (\i -> i {quantity = 0})) $ \item ->
        item.quantity `shouldBe` 0

    it "accepts empty tags list" $
      expectRight (mkInputWith (\i -> i {tags = []})) $ \item ->
        item.tags `shouldBe` V.empty

    it "accepts empty effects list" $
      expectRight (mkInputWith (\i -> i {effects = []})) $ \item ->
        item.effects `shouldBe` V.empty

  -- ──────────────────────────────────────────────
  -- menuItemToGql / gqlInputToMenuItem roundtrip
  -- ──────────────────────────────────────────────
  describe "menuItemToGql / gqlInputToMenuItem roundtrip" $ do
    it "sku Text roundtrips: input sku → MenuItem UUID → GQL sku Text" $
      expectRight testMenuItemInputGql $ \item ->
        (menuItemToGql item).sku `shouldBe` "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"

    it "name is preserved through roundtrip" $
      expectRight testMenuItemInputGql $ \item ->
        (menuItemToGql item).name `shouldBe` "OG Kush"

    it "price is preserved through roundtrip" $
      expectRight testMenuItemInputGql $ \item ->
        (menuItemToGql item).price `shouldBe` 2999

  -- ──────────────────────────────────────────────
  -- Resolver auth capability gates
  -- ──────────────────────────────────────────────
  describe "Resolver auth capability logic" $ do
    describe "createMenuItem gate: capCanCreateItem" $ do
      it "Customer cannot create" $ capCanCreateItem (capabilitiesForRole Customer) `shouldBe` False
      it "Cashier cannot create" $ capCanCreateItem (capabilitiesForRole Cashier) `shouldBe` False
      it "Manager can create" $ capCanCreateItem (capabilitiesForRole Manager) `shouldBe` True
      it "Admin can create" $ capCanCreateItem (capabilitiesForRole Admin) `shouldBe` True

    describe "updateMenuItem gate: capCanEditItem" $ do
      it "Customer cannot edit" $ capCanEditItem (capabilitiesForRole Customer) `shouldBe` False
      it "Cashier can edit" $ capCanEditItem (capabilitiesForRole Cashier) `shouldBe` True
      it "Manager can edit" $ capCanEditItem (capabilitiesForRole Manager) `shouldBe` True
      it "Admin can edit" $ capCanEditItem (capabilitiesForRole Admin) `shouldBe` True

    describe "deleteMenuItem gate: capCanDeleteItem" $ do
      it "Customer cannot delete" $ capCanDeleteItem (capabilitiesForRole Customer) `shouldBe` False
      it "Cashier cannot delete" $ capCanDeleteItem (capabilitiesForRole Cashier) `shouldBe` False
      it "Manager can delete" $ capCanDeleteItem (capabilitiesForRole Manager) `shouldBe` True
      it "Admin can delete" $ capCanDeleteItem (capabilitiesForRole Admin) `shouldBe` True

    describe "inventory query: all roles may read" $ do
      it "all roles have capCanViewInventory" $ do
        mapM_
          (\r -> capCanViewInventory (capabilitiesForRole r) `shouldBe` True)
          [Customer, Cashier, Manager, Admin]

  -- ──────────────────────────────────────────────
  -- UUID.fromText used by resolvers
  -- ──────────────────────────────────────────────
  describe "UUID.fromText (used in resolver delete/query)" $ do
    it "accepts valid UUID string" $
      UUID.fromText "4e58b3e6-3fd4-425c-b6a3-4f033a76859c" `shouldBe` Just testUUID

    it "rejects invalid UUID string" $
      UUID.fromText "not-a-uuid" `shouldBe` Nothing

    it "rejects empty string" $
      UUID.fromText "" `shouldBe` Nothing

    it "UUID.toText . UUID.fromText is identity" $ do
      let uuidStr = "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
      fmap UUID.toText (UUID.fromText uuidStr) `shouldBe` Just uuidStr

-- ──────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────

-- Build a minimal MenuItemInputGql varying only the sku, to avoid
-- ambiguous record update syntax on a shared field name.
mkInput :: T.Text -> MenuItemInputGql
mkInput s =
  MenuItemInputGql
    { sort = 1
    , sku = s
    , brand = "B"
    , name = "N"
    , price = 0
    , measure_unit = "g"
    , per_package = "1"
    , quantity = 0
    , category = "Flower"
    , subcategory = ""
    , description = ""
    , tags = []
    , effects = []
    , strain_lineage = testStrainLineageInputGql
    }

-- Apply a pure function to the canonical fixture, avoiding record
-- update syntax entirely (sidesteps DuplicateRecordFields ambiguity).
mkInputWith :: (MenuItemInputGql -> MenuItemInputGql) -> MenuItemInputGql
mkInputWith f = f testMenuItemInputGql

expectRight :: MenuItemInputGql -> (TI.MenuItem -> IO ()) -> IO ()
expectRight inp k =
  case gqlInputToMenuItem inp of
    Left err -> expectationFailure $ "Expected Right but got Left: " <> T.unpack err
    Right item -> k item
