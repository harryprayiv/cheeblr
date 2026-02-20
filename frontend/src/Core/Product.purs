module Cheeblr.Core.Product where

import Prelude

import Cheeblr.Core.Domain (Category, Species)
import Cheeblr.Core.Tag (unTag)
import Cheeblr.Core.Tag as Cheeblr.Core.Tag
import Data.Array as Data.Array
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, unwrap)
import Foreign (ForeignError(..), fail)
import Foreign as Foreign
import Foreign.Index (readProp)
import Types.UUID (UUID, parseUUID)
import Yoga.JSON (class ReadForeign, class WriteForeign, readImpl, writeImpl)

----------------------------------------------------------------------
-- Product Metadata (replaces StrainLineage)
----------------------------------------------------------------------

-- | Strain and lineage metadata for cannabis products.
-- | Species is now a Tag rather than an ADT.
-- | Fields are kept as named records for type safety;
-- | THC/CBG are strings because they include the % symbol.
type ProductMeta =
  { thc :: String
  , cbg :: String
  , strain :: String
  , creator :: String
  , species :: Species
  , dominantTerpene :: String
  , terpenes :: Array String
  , lineage :: Array String
  , leaflyUrl :: String
  , img :: String
  }

-- | Default/empty metadata for new products.
emptyMeta :: ProductMeta
emptyMeta =
  { thc: ""
  , cbg: ""
  , strain: ""
  , creator: ""
  , species: Cheeblr.Core.Tag.unsafeTag ""
  , dominantTerpene: ""
  , terpenes: []
  , lineage: []
  , leaflyUrl: ""
  , img: ""
  }

----------------------------------------------------------------------
-- Product (replaces MenuItem)
----------------------------------------------------------------------

type ProductRecord =
  { sort :: Int
  , sku :: UUID
  , brand :: String
  , name :: String
  , price :: Discrete USD        -- stored in cents
  , measureUnit :: String        -- kept as String for now; could be Tag "measure_unit"
  , perPackage :: String
  , quantity :: Int
  , category :: Category         -- Tag "category" instead of ItemCategory ADT
  , subcategory :: String
  , description :: String
  , tags :: Array String
  , effects :: Array String
  , meta :: ProductMeta
  }

newtype Product = Product ProductRecord

derive instance Newtype Product _
derive instance Eq Product
derive instance Ord Product

instance Show Product where
  show (Product p) =
    "{ name: " <> show p.name
      <> ", brand: " <> show p.brand
      <> ", quantity: " <> show p.quantity
      <> " }"

----------------------------------------------------------------------
-- ProductList (replaces Inventory)
----------------------------------------------------------------------

newtype ProductList = ProductList (Array Product)

derive instance Newtype ProductList _
derive instance Eq ProductList

instance Show ProductList where
  show (ProductList items) = "ProductList(" <> show (Data.Array.length items) <> " items)"

----------------------------------------------------------------------
-- API Response (replaces InventoryResponse)
----------------------------------------------------------------------

data ProductResponse
  = ProductData ProductList
  | ProductMessage String

----------------------------------------------------------------------
-- Serialization: WriteForeign
----------------------------------------------------------------------

-- Wire format matches existing backend expectations:
-- { sort, sku, brand, name, price (Int cents), measure_unit, per_package,
--   quantity, category (String), subcategory, description, tags, effects,
--   strain_lineage: { thc, cbg, strain, creator, species (String), ... } }

instance WriteForeign Product where
  writeImpl (Product p) = writeImpl
    { sort: p.sort
    , sku: p.sku
    , brand: p.brand
    , name: p.name
    , price: unwrap p.price                -- Int (cents)
    , measure_unit: p.measureUnit
    , per_package: p.perPackage
    , quantity: p.quantity
    , category: unTag p.category           -- String
    , subcategory: p.subcategory
    , description: p.description
    , tags: p.tags
    , effects: p.effects
    , strain_lineage: writeMetaRecord p.meta
    }
    where
    writeMetaRecord :: ProductMeta -> _
    writeMetaRecord m = writeImpl
      { thc: m.thc
      , cbg: m.cbg
      , strain: m.strain
      , creator: m.creator
      , species: unTag m.species           -- String
      , dominant_terpene: m.dominantTerpene
      , terpenes: m.terpenes
      , lineage: m.lineage
      , leafly_url: m.leaflyUrl
      , img: m.img
      }

instance WriteForeign ProductList where
  writeImpl (ProductList items) = writeImpl items

instance WriteForeign ProductResponse where
  writeImpl (ProductData list) = writeImpl { "type": "data", value: list }
  writeImpl (ProductMessage msg) = writeImpl { "type": "message", value: msg }

----------------------------------------------------------------------
-- Serialization: ReadForeign
----------------------------------------------------------------------

-- Permissive read: category and species are read as raw strings
-- and wrapped in Tags without registry validation. This means
-- the backend can introduce new categories without breaking the
-- frontend parser. Validation is a separate step.

instance ReadForeign Product where
  readImpl json = do
    sort <- readProp "sort" json >>= readImpl
    skuStr <- readProp "sku" json >>= readImpl
    sku <- case parseUUID skuStr of
      Just uuid -> pure uuid
      Nothing -> fail $ ForeignError "Invalid UUID format for sku"
    brand <- readProp "brand" json >>= readImpl
    name <- readProp "name" json >>= readImpl
    priceValue <- readProp "price" json >>= readImpl :: _ Int
    measureUnit <- readProp "measure_unit" json >>= readImpl
    perPackage <- readProp "per_package" json >>= readImpl
    quantity <- readProp "quantity" json >>= readImpl
    categoryStr <- readProp "category" json >>= readImpl :: _ String
    subcategory <- readProp "subcategory" json >>= readImpl
    description <- readProp "description" json >>= readImpl
    tags <- readProp "tags" json >>= readImpl
    effects <- readProp "effects" json >>= readImpl
    metaJson <- readProp "strain_lineage" json
    meta <- readMeta metaJson
    pure $ Product
      { sort
      , sku
      , brand
      , name
      , price: Discrete priceValue
      , measureUnit
      , perPackage
      , quantity
      , category: Cheeblr.Core.Tag.unsafeTag categoryStr  -- permissive
      , subcategory
      , description
      , tags
      , effects
      , meta
      }
    where
    readMeta mj = do
      thc <- readProp "thc" mj >>= readImpl
      cbg <- readProp "cbg" mj >>= readImpl
      strain <- readProp "strain" mj >>= readImpl
      creator <- readProp "creator" mj >>= readImpl
      speciesStr <- readProp "species" mj >>= readImpl :: _ String
      dominantTerpene <- readProp "dominant_terpene" mj >>= readImpl
      terpenes <- readProp "terpenes" mj >>= readImpl
      lineage <- readProp "lineage" mj >>= readImpl
      leaflyUrl <- readProp "leafly_url" mj >>= readImpl
      img <- readProp "img" mj >>= readImpl
      pure
        { thc
        , cbg
        , strain
        , creator
        , species: Cheeblr.Core.Tag.unsafeTag speciesStr  -- permissive
        , dominantTerpene
        , terpenes
        , lineage
        , leaflyUrl
        , img
        }

instance ReadForeign ProductList where
  readImpl json = do
    items <- readImpl json :: _ (Array Product)
    pure $ ProductList items

instance ReadForeign ProductResponse where
  readImpl f = do
    obj <- readImpl f
    case obj of
      array | isArray array -> do
        list <- readImpl array :: _ ProductList
        pure $ ProductData list
      _ -> do
        typeField <- readProp "type" obj >>= readImpl :: _ String
        case typeField of
          "data" -> do
            value <- readProp "value" obj >>= readImpl :: _ ProductList
            pure $ ProductData value
          "message" -> do
            value <- readProp "value" obj >>= readImpl :: _ String
            pure $ ProductMessage value
          _ -> fail $ ForeignError "Invalid response type"
    where
    isArray :: _ -> Boolean
    isArray value = Foreign.typeOf value == "array"

----------------------------------------------------------------------
-- Product accessors and helpers
----------------------------------------------------------------------

productSku :: Product -> UUID
productSku (Product p) = p.sku

productName :: Product -> String
productName (Product p) = p.name

productPrice :: Product -> Discrete USD
productPrice (Product p) = p.price

productCategory :: Product -> Category
productCategory (Product p) = p.category

productQuantity :: Product -> Int
productQuantity (Product p) = p.quantity

productSpecies :: Product -> Species
productSpecies (Product p) = p.meta.species

productInStock :: Product -> Boolean
productInStock (Product p) = p.quantity > 0

findBySku :: UUID -> ProductList -> Maybe Product
findBySku sku (ProductList items) =
  Data.Array.find (\(Product p) -> p.sku == sku) items

findNameBySku :: UUID -> ProductList -> String
findNameBySku sku list =
  case findBySku sku list of
    Just (Product p) -> p.name
    Nothing -> "Unknown Item"