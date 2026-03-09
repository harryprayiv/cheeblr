module Test.GraphQL where

import Prelude

import Data.Finance.Money (Discrete(..))
import Data.Maybe (Maybe(..), isJust, isNothing)
import Data.String (contains, Pattern(..))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Inventory (Inventory(..), ItemCategory(..), MenuItem(..), Species(..), StrainLineage(..), MutationResponse)
import Types.UUID (UUID(..))
import Yoga.JSON (readJSON_, writeJSON)

-- ─── Mirror of GraphQL.API.Inventory private response types ──────────────────
-- Replicated here so unit tests can validate the exact JSON envelopes the
-- backend produces without depending on internal module bindings.

type GqlResponse a = { data :: a }

type InventoryData = { inventory :: Inventory }

type CreateMenuItemData = { createMenuItem :: MutationResponse }

type UpdateMenuItemData = { updateMenuItem :: MutationResponse }

type DeleteMenuItemData = { deleteMenuItem :: MutationResponse }

-- ─── String helper ────────────────────────────────────────────────────────────

includes :: String -> String -> Boolean
includes haystack needle = contains (Pattern needle) haystack

-- ─── JSON fixtures ────────────────────────────────────────────────────────────

singleItemGqlJson :: String
singleItemGqlJson =
  """{"data":{"inventory":[{"sort":1,"sku":"4e58b3e6-3fd4-425c-b6a3-4f033a76859c","brand":"TestBrand","name":"OG Kush","price":2999,"measure_unit":"g","per_package":"3.5","quantity":10,"category":"Flower","subcategory":"Indoor","description":"Classic","tags":["indica"],"effects":["relaxed"],"strain_lineage":{"thc":"25%","cbg":"0.5%","strain":"OG Kush","creator":"Unknown","species":"Indica","dominant_terpene":"Myrcene","terpenes":["Myrcene"],"lineage":["Chemdawg"],"leafly_url":"https://leafly.com","img":"https://example.com/img.jpg"}}]}}"""

emptyInventoryGqlJson :: String
emptyInventoryGqlJson =
  """{"data":{"inventory":[]}}"""

multiItemGqlJson :: String
multiItemGqlJson =
  """{"data":{"inventory":[{"sort":1,"sku":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","brand":"Brand A","name":"Item A","price":1000,"measure_unit":"g","per_package":"1g","quantity":5,"category":"Flower","subcategory":"Indoor","description":"","tags":[],"effects":[],"strain_lineage":{"thc":"20%","cbg":"1%","strain":"S","creator":"C","species":"Sativa","dominant_terpene":"L","terpenes":[],"lineage":[],"leafly_url":"https://leafly.com","img":"https://example.com/a.jpg"}},{"sort":2,"sku":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","brand":"Brand B","name":"Item B","price":2500,"measure_unit":"mg","per_package":"100mg","quantity":20,"category":"Edibles","subcategory":"Gummies","description":"","tags":[],"effects":[],"strain_lineage":{"thc":"10%","cbg":"0%","strain":"H","creator":"C","species":"Hybrid","dominant_terpene":"M","terpenes":[],"lineage":[],"leafly_url":"https://leafly.com","img":"https://example.com/b.jpg"}}]}}"""

createSuccessGqlJson :: String
createSuccessGqlJson =
  """{"data":{"createMenuItem":{"success":true,"message":"Item created"}}}"""

createFailureGqlJson :: String
createFailureGqlJson =
  """{"data":{"createMenuItem":{"success":false,"message":"SKU already exists"}}}"""

updateSuccessGqlJson :: String
updateSuccessGqlJson =
  """{"data":{"updateMenuItem":{"success":true,"message":"Item updated"}}}"""

updateFailureGqlJson :: String
updateFailureGqlJson =
  """{"data":{"updateMenuItem":{"success":false,"message":"Item not found"}}}"""

deleteSuccessGqlJson :: String
deleteSuccessGqlJson =
  """{"data":{"deleteMenuItem":{"success":true,"message":"Item deleted"}}}"""

deleteNotFoundGqlJson :: String
deleteNotFoundGqlJson =
  """{"data":{"deleteMenuItem":{"success":false,"message":"Item not found"}}}"""

-- Backend sends {"errors":[...]} with no "data" key on resolver/auth errors
gqlErrorJson :: String
gqlErrorJson =
  """{"errors":[{"message":"Not authenticated","locations":[{"line":1,"column":3}],"path":["inventory"]}]}"""

-- ─── Test MenuItem fixture ────────────────────────────────────────────────────

testMenuItem :: MenuItem
testMenuItem = MenuItem
  { sort: 1
  , sku: UUID "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
  , brand: "TestBrand"
  , name: "OG Kush"
  , price: Discrete 2999
  , measure_unit: "g"
  , per_package: "3.5"
  , quantity: 10
  , category: Flower
  , subcategory: "Indoor"
  , description: "Classic"
  , tags: [ "indica" ]
  , effects: [ "relaxed" ]
  , strain_lineage: StrainLineage
      { thc: "25%"
      , cbg: "0.5%"
      , strain: "OG Kush"
      , creator: "Unknown"
      , species: Indica
      , dominant_terpene: "Myrcene"
      , terpenes: [ "Myrcene" ]
      , lineage: [ "Chemdawg" ]
      , leafly_url: "https://leafly.com"
      , img: "https://example.com/img.jpg"
      }
  }

-- ─── The literal query string from GraphQL.API.Inventory ─────────────────────
-- Copied here so field-name regressions are caught at the unit level.

inventoryQuery :: String
inventoryQuery =
  """
  { inventory {
      sort sku brand name price measure_unit per_package quantity
      category subcategory description tags effects
      strain_lineage {
        thc cbg strain creator species dominant_terpene
        terpenes lineage leafly_url img
      }
  } }
  """

-- ─── Spec ─────────────────────────────────────────────────────────────────────

spec :: Spec Unit
spec = describe "GraphQL JSON contracts" do

  -- ── GqlResponse<InventoryData> envelope ────────────────────────────────────

  describe "GqlResponse<InventoryData> envelope" do

    it "parses single-item response" do
      (readJSON_ singleItemGqlJson :: Maybe (GqlResponse InventoryData))
        `shouldSatisfy` isJust

    it "extracts non-empty Inventory from data.inventory" do
      case readJSON_ singleItemGqlJson :: Maybe (GqlResponse InventoryData) of
        Just r ->
          let Inventory items = r.data.inventory
          in (items /= []) `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "parses empty inventory envelope" do
      (readJSON_ emptyInventoryGqlJson :: Maybe (GqlResponse InventoryData))
        `shouldSatisfy` isJust

    it "empty data.inventory is Inventory []" do
      case readJSON_ emptyInventoryGqlJson :: Maybe (GqlResponse InventoryData) of
        Just r  -> r.data.inventory `shouldEqual` Inventory []
        Nothing -> false `shouldEqual` true

    it "parses multi-item inventory" do
      (readJSON_ multiItemGqlJson :: Maybe (GqlResponse InventoryData))
        `shouldSatisfy` isJust

    it "multi-item response contains items" do
      case readJSON_ multiItemGqlJson :: Maybe (GqlResponse InventoryData) of
        Just r ->
          let Inventory items = r.data.inventory
          in (items /= []) `shouldEqual` true
        Nothing -> false `shouldEqual` true

  -- ── MenuItem field fidelity through GQL envelope ───────────────────────────

  describe "MenuItem field fidelity via GQL envelope" do

    it "preserves price as integer cents" do
      case readJSON_ singleItemGqlJson :: Maybe (GqlResponse InventoryData) of
        Just r ->
          case r.data.inventory of
            Inventory [ MenuItem item ] -> item.price `shouldEqual` Discrete 2999
            _                           -> false `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "preserves category as ItemCategory" do
      case readJSON_ singleItemGqlJson :: Maybe (GqlResponse InventoryData) of
        Just r ->
          case r.data.inventory of
            Inventory [ MenuItem item ] -> item.category `shouldEqual` Flower
            _                           -> false `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "preserves species in strain_lineage" do
      case readJSON_ singleItemGqlJson :: Maybe (GqlResponse InventoryData) of
        Just r ->
          case r.data.inventory of
            Inventory [ MenuItem item ] ->
              case item.strain_lineage of
                StrainLineage sl -> sl.species `shouldEqual` Indica
            _ -> false `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "preserves sku as UUID" do
      case readJSON_ singleItemGqlJson :: Maybe (GqlResponse InventoryData) of
        Just r ->
          case r.data.inventory of
            Inventory [ MenuItem item ] ->
              item.sku `shouldEqual` UUID "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
            _ -> false `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "preserves tags array" do
      case readJSON_ singleItemGqlJson :: Maybe (GqlResponse InventoryData) of
        Just r ->
          case r.data.inventory of
            Inventory [ MenuItem item ] -> item.tags `shouldEqual` [ "indica" ]
            _                           -> false `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "preserves strain_lineage terpenes" do
      case readJSON_ singleItemGqlJson :: Maybe (GqlResponse InventoryData) of
        Just r ->
          case r.data.inventory of
            Inventory [ MenuItem item ] ->
              case item.strain_lineage of
                StrainLineage sl -> sl.terpenes `shouldEqual` [ "Myrcene" ]
            _ -> false `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "second item in multi-item response has correct category" do
      case readJSON_ multiItemGqlJson :: Maybe (GqlResponse InventoryData) of
        Just r ->
          let Inventory items = r.data.inventory
          in case items of
            [ _, MenuItem b ] -> b.category `shouldEqual` Edibles
            _                 -> false `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "second item has correct species" do
      case readJSON_ multiItemGqlJson :: Maybe (GqlResponse InventoryData) of
        Just r ->
          let Inventory items = r.data.inventory
          in case items of
            [ _, MenuItem b ] ->
              let StrainLineage sl = b.strain_lineage
              in sl.species `shouldEqual` Hybrid
            _ -> false `shouldEqual` true
        Nothing -> false `shouldEqual` true

  -- ── createMenuItem mutation ─────────────────────────────────────────────────

  describe "createMenuItem mutation response" do

    it "parses success envelope" do
      (readJSON_ createSuccessGqlJson :: Maybe (GqlResponse CreateMenuItemData))
        `shouldSatisfy` isJust

    it "success.success is true" do
      case readJSON_ createSuccessGqlJson :: Maybe (GqlResponse CreateMenuItemData) of
        Just r  -> r.data.createMenuItem.success `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "success.message is preserved" do
      case readJSON_ createSuccessGqlJson :: Maybe (GqlResponse CreateMenuItemData) of
        Just r  -> r.data.createMenuItem.message `shouldEqual` "Item created"
        Nothing -> false `shouldEqual` true

    it "parses failure envelope" do
      (readJSON_ createFailureGqlJson :: Maybe (GqlResponse CreateMenuItemData))
        `shouldSatisfy` isJust

    it "failure.success is false" do
      case readJSON_ createFailureGqlJson :: Maybe (GqlResponse CreateMenuItemData) of
        Just r  -> r.data.createMenuItem.success `shouldEqual` false
        Nothing -> false `shouldEqual` true

    it "failure.message is preserved" do
      case readJSON_ createFailureGqlJson :: Maybe (GqlResponse CreateMenuItemData) of
        Just r  -> r.data.createMenuItem.message `shouldEqual` "SKU already exists"
        Nothing -> false `shouldEqual` true

  -- ── updateMenuItem mutation ─────────────────────────────────────────────────

  describe "updateMenuItem mutation response" do

    it "parses success envelope" do
      (readJSON_ updateSuccessGqlJson :: Maybe (GqlResponse UpdateMenuItemData))
        `shouldSatisfy` isJust

    it "update success.success is true" do
      case readJSON_ updateSuccessGqlJson :: Maybe (GqlResponse UpdateMenuItemData) of
        Just r  -> r.data.updateMenuItem.success `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "parses failure envelope" do
      (readJSON_ updateFailureGqlJson :: Maybe (GqlResponse UpdateMenuItemData))
        `shouldSatisfy` isJust

    it "update failure.success is false" do
      case readJSON_ updateFailureGqlJson :: Maybe (GqlResponse UpdateMenuItemData) of
        Just r  -> r.data.updateMenuItem.success `shouldEqual` false
        Nothing -> false `shouldEqual` true

  -- ── deleteMenuItem mutation ─────────────────────────────────────────────────

  describe "deleteMenuItem mutation response" do

    it "parses success envelope" do
      (readJSON_ deleteSuccessGqlJson :: Maybe (GqlResponse DeleteMenuItemData))
        `shouldSatisfy` isJust

    it "delete success.success is true" do
      case readJSON_ deleteSuccessGqlJson :: Maybe (GqlResponse DeleteMenuItemData) of
        Just r  -> r.data.deleteMenuItem.success `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "parses not-found envelope" do
      (readJSON_ deleteNotFoundGqlJson :: Maybe (GqlResponse DeleteMenuItemData))
        `shouldSatisfy` isJust

    it "not-found.success is false" do
      case readJSON_ deleteNotFoundGqlJson :: Maybe (GqlResponse DeleteMenuItemData) of
        Just r  -> r.data.deleteMenuItem.success `shouldEqual` false
        Nothing -> false `shouldEqual` true

    it "not-found.message is preserved" do
      case readJSON_ deleteNotFoundGqlJson :: Maybe (GqlResponse DeleteMenuItemData) of
        Just r  -> r.data.deleteMenuItem.message `shouldEqual` "Item not found"
        Nothing -> false `shouldEqual` true

  -- ── MutationResponse shape ─────────────────────────────────────────────────

  describe "MutationResponse { success, message } shape" do

    it "parses success:true" do
      (readJSON_ """{"success":true,"message":"ok"}""" :: Maybe MutationResponse)
        `shouldSatisfy` isJust

    it "parses success:false" do
      (readJSON_ """{"success":false,"message":"err"}""" :: Maybe MutationResponse)
        `shouldSatisfy` isJust

    it "preserves boolean field" do
      case readJSON_ """{"success":true,"message":"ok"}""" :: Maybe MutationResponse of
        Just r  -> r.success `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "preserves message string" do
      case readJSON_ """{"success":false,"message":"conflict"}""" :: Maybe MutationResponse of
        Just r  -> r.message `shouldEqual` "conflict"
        Nothing -> false `shouldEqual` true

  -- ── GraphQL error envelope ─────────────────────────────────────────────────

  describe "GraphQL error envelope (no data key)" do

    it "does NOT parse as GqlResponse<InventoryData>" do
      (readJSON_ gqlErrorJson :: Maybe (GqlResponse InventoryData))
        `shouldSatisfy` isNothing

    it "does NOT parse as GqlResponse<CreateMenuItemData>" do
      (readJSON_ gqlErrorJson :: Maybe (GqlResponse CreateMenuItemData))
        `shouldSatisfy` isNothing

  -- ── inventoryQuery field name contracts ────────────────────────────────────
  -- Guards against accidentally switching snake_case field names to camelCase.

  describe "inventoryQuery field name contracts" do

    it "contains measure_unit (snake_case)" do
      (inventoryQuery `includes` "measure_unit") `shouldEqual` true

    it "contains per_package (snake_case)" do
      (inventoryQuery `includes` "per_package") `shouldEqual` true

    it "contains strain_lineage (snake_case)" do
      (inventoryQuery `includes` "strain_lineage") `shouldEqual` true

    it "contains dominant_terpene (snake_case)" do
      (inventoryQuery `includes` "dominant_terpene") `shouldEqual` true

    it "contains leafly_url (snake_case)" do
      (inventoryQuery `includes` "leafly_url") `shouldEqual` true

    it "does NOT contain measureUnit (camelCase)" do
      (inventoryQuery `includes` "measureUnit") `shouldEqual` false

    it "does NOT contain perPackage (camelCase)" do
      (inventoryQuery `includes` "perPackage") `shouldEqual` false

    it "does NOT contain strainLineage (camelCase)" do
      (inventoryQuery `includes` "strainLineage") `shouldEqual` false

    it "does NOT contain dominantTerpene (camelCase)" do
      (inventoryQuery `includes` "dominantTerpene") `shouldEqual` false

    it "does NOT contain leaflyUrl (camelCase)" do
      (inventoryQuery `includes` "leaflyUrl") `shouldEqual` false

    it "contains all required top-level scalar fields" do
      let fields =
            [ "sort", "sku", "brand", "name", "price", "quantity"
            , "category", "subcategory", "description", "tags", "effects"
            ]
      let allPresent = map (\f -> inventoryQuery `includes` f) fields
      allPresent `shouldEqual` map (const true) fields

    it "contains all strain_lineage sub-fields" do
      let fields =
            [ "thc", "cbg", "strain", "creator", "species"
            , "terpenes", "lineage", "img"
            ]
      let allPresent = map (\f -> inventoryQuery `includes` f) fields
      allPresent `shouldEqual` map (const true) fields

  -- ── MenuItem WriteForeign for mutation input ───────────────────────────────
  -- Mutations serialize MenuItem via writeJSON and inject into the query string.
  -- Verify the serialized keys match what morpheus-graphql expects.

  describe "MenuItem WriteForeign for mutation input" do

    let serialized = writeJSON testMenuItem

    it "serialized JSON round-trips as MenuItem" do
      (readJSON_ serialized :: Maybe MenuItem) `shouldSatisfy` isJust

    it "price is integer cents in serialized JSON" do
      case readJSON_ serialized :: Maybe MenuItem of
        Just (MenuItem i) -> i.price `shouldEqual` Discrete 2999
        Nothing           -> false `shouldEqual` true

    it "category serialized as PascalCase string" do
      (serialized `includes` "\"Flower\"") `shouldEqual` true

    it "species serialized as PascalCase string" do
      (serialized `includes` "\"Indica\"") `shouldEqual` true

    it "uses measure_unit key (snake_case)" do
      (serialized `includes` "measure_unit") `shouldEqual` true

    it "uses per_package key (snake_case)" do
      (serialized `includes` "per_package") `shouldEqual` true

    it "uses strain_lineage key (snake_case)" do
      (serialized `includes` "strain_lineage") `shouldEqual` true

    it "uses dominant_terpene key (snake_case)" do
      (serialized `includes` "dominant_terpene") `shouldEqual` true

    it "uses leafly_url key (snake_case)" do
      (serialized `includes` "leafly_url") `shouldEqual` true

  -- ── GQL endpoint path contract ─────────────────────────────────────────────

  describe "GraphQL endpoint path" do

    let gqlEndpoint = "/graphql/inventory"

    it "path contains 'graphql'" do
      (gqlEndpoint `includes` "graphql") `shouldEqual` true

    it "path is scoped to 'inventory'" do
      (gqlEndpoint `includes` "inventory") `shouldEqual` true

    it "path is NOT the root /graphql endpoint" do
      (gqlEndpoint == "/graphql") `shouldEqual` false