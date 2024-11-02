module BudView where

import Prelude

import Control.Monad.Except (ExceptT)
import Data.Either (Either(..))
import Data.Identity (Identity)
import Data.List.NonEmpty (NonEmptyList)
import Effect.Aff (Aff, attempt)
import Effect.Class (liftEffect)
import Effect.Class.Console (log)
import Effect.Now (now)
import Fetch (Method(..), fetch)
import Fetch.Yoga.Json (fromJSON)
import Foreign (Foreign, ForeignError(..), fail)
import Foreign.Index (readProp)
import Yoga.JSON (class ReadForeign, class WriteForeign, readImpl, writeImpl, unsafeStringify)


newtype ForeignRequestBody = ForeignRequestBody Foreign

data InventoryResponse
  = InventoryData Inventory
  | Message String

data QueryMode = JsonMode | HttpMode

newtype Inventory = Inventory (Array MenuItem)

data ItemCategory = Flower | PreRolls | Vaporizers | Edibles | Drinks | Concentrates | Topicals | Tinctures | Accessories

-- convert ItemCategory to a specific string like some kind of animal compared to the Haskell Generic derivations technique
itemCategoryToString :: ItemCategory -> String
itemCategoryToString category = case category of
  Flower -> "Flower"
  PreRolls -> "PreRolls"
  Vaporizers -> "Vaporizers"
  Edibles -> "Edibles"
  Drinks -> "Drinks"
  Concentrates -> "Concentrates"
  Topicals -> "Topicals"
  Tinctures -> "Tinctures"
  Accessories -> "Accessories"

-- Define StrainLineage as a data type with a record to use it in instances
data StrainLineage = StrainLineage
  { thc :: String
  , cbg :: String
  , strain :: String
  , creator :: String
  , species :: String
  , dominant_tarpene :: String
  , tarpenes :: Array String
  , lineage :: Array String
  , leafly_url :: String
  , img :: String
  }

-- Define MenuItem as a data type with a record to use it in instances
data MenuItem = MenuItem
  { sort :: Int
  , sku :: String
  , brand :: String
  , name :: String
  , price :: Number
  , measure_unit :: String
  , per_package :: String
  , quantity :: Int
  , category :: ItemCategory
  , subcategory :: String
  , description :: String
  , tags :: Array String
  , strain_lineage :: StrainLineage
  }

-- WriteForeign instance for StrainLineage
instance writeForeignStrainLineage :: WriteForeign StrainLineage where
  writeImpl (StrainLineage lineage) = writeImpl
    { thc: lineage.thc
    , cbg: lineage.cbg
    , strain: lineage.strain
    , creator: lineage.creator
    , species: lineage.species
    , dominant_tarpene: lineage.dominant_tarpene
    , tarpenes: lineage.tarpenes
    , lineage: lineage.lineage
    , leafly_url: lineage.leafly_url
    , img: lineage.img
    }

-- WriteForeign instance for MenuItem
instance writeForeignMenuItem :: WriteForeign MenuItem where
  writeImpl (MenuItem item) = writeImpl
    { sort: item.sort
    , sku: item.sku
    , brand: item.brand
    , name: item.name
    , price: item.price
    , measure_unit: item.measure_unit
    , per_package: item.per_package
    , quantity: item.quantity
    , category: itemCategoryToString item.category
    , subcategory: item.subcategory
    , description: item.description
    , tags: item.tags
    , strain_lineage: writeImpl item.strain_lineage
    }

-- ReadForeign instance for StrainLineage
instance readForeignStrainLineage :: ReadForeign StrainLineage where
  readImpl json = do
    thc <- readProp "thc" json >>= readImpl
    cbg <- readProp "cbg" json >>= readImpl
    strain <- readProp "strain" json >>= readImpl
    creator <- readProp "creator" json >>= readImpl
    species <- readProp "species" json >>= readImpl
    dominant_tarpene <- readProp "dominant_tarpene" json >>= readImpl
    tarpenes <- readProp "tarpenes" json >>= readImpl
    lineage <- readProp "lineage" json >>= readImpl
    leafly_url <- readProp "leafly_url" json >>= readImpl
    img <- readProp "img" json >>= readImpl
    pure $ StrainLineage { thc, cbg, strain, creator, species, dominant_tarpene, tarpenes, lineage, leafly_url, img }

-- ReadForeign instance for MenuItem
instance readForeignMenuItem :: ReadForeign MenuItem where
  readImpl json = do
    sort <- readProp "sort" json >>= readImpl
    sku <- readProp "sku" json >>= readImpl
    brand <- readProp "brand" json >>= readImpl
    name <- readProp "name" json >>= readImpl
    price <- readProp "price" json >>= readImpl
    measure_unit <- readProp "measure_unit" json >>= readImpl
    per_package <- readProp "per_package" json >>= readImpl
    quantity <- readProp "quantity" json >>= readImpl
    categoryStr <- readProp "category" json >>= readImpl
    category <- case categoryStr of
      "Flower" -> pure Flower
      "PreRolls" -> pure PreRolls
      "Vaporizers" -> pure Vaporizers
      "Edibles" -> pure Edibles
      "Drinks" -> pure Drinks
      "Concentrates" -> pure Concentrates
      "Topicals" -> pure Topicals
      "Tinctures" -> pure Tinctures
      "Accessories" -> pure Accessories
      _ -> fail (ForeignError "Invalid ItemCategory value")
    subcategory <- readProp "subcategory" json >>= readImpl
    description <- readProp "description" json >>= readImpl
    tags <- readProp "tags" json >>= readImpl
    strain_lineage <- readProp "strain_lineage" json >>= readImpl
    pure $ MenuItem { sort, sku, brand, name, price, measure_unit, per_package, quantity, category, subcategory, description, tags, strain_lineage }

-- WriteForeign and ReadForeign instances for Inventory
instance writeForeignInventory :: WriteForeign Inventory where
  writeImpl (Inventory items) = writeImpl items

instance readForeignInventory :: ReadForeign Inventory where
  readImpl json = do
    items <- readImpl json :: ExceptT (NonEmptyList ForeignError) Identity (Array MenuItem)
    pure $ Inventory items

-- Fetch functions for inventory
fetchInventory :: QueryMode -> Aff (Either String InventoryResponse)
fetchInventory mode = case mode of
  JsonMode -> fetchInventoryFromJson
  HttpMode -> fetchInventoryFromHttp

fetchInventoryFromJson :: Aff (Either String InventoryResponse)
fetchInventoryFromJson = do
  result <- attempt do
    timestamp <- liftEffect $ show <$> now
    let url = "/inventory.json?t=" <> timestamp
    liftEffect $ log ("Fetching URL: " <> url)
    coreResponse <- fetch url {}
    inventory <- fromJSON coreResponse.json :: Aff Inventory
    pure inventory

  case result of
    Left err -> pure $ Left $ "Fetch error: " <> show err
    Right inventory -> pure $ Right $ InventoryData inventory

fetchInventoryFromHttp :: Aff (Either String InventoryResponse)
fetchInventoryFromHttp = do
  result <- attempt do
    let requestHeaders = { "Content-Type": "application/json" }
    -- Convert ForeignRequestBody to a JSON string
    let requestBody = unsafeStringify (writeImpl { hello: "world" })
    coreResponse <- fetch "https://httpbin.org/post"
      { method: POST
      , body: requestBody
      , headers: requestHeaders
      }
    res <- fromJSON coreResponse.json :: Aff Foreign
    pure $ "Received response: " <> unsafeStringify res

  case result of
    Left err -> pure $ Left $ "Fetch error: " <> show err
    Right msg -> pure $ Right $ Message msg