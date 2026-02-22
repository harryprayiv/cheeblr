module Types.Inventory where

import Prelude

import Config.LiveView (LiveViewConfig, SortField(..), SortOrder(..))
import Data.Array (find)
import Data.Array as Array
import Data.Either (Either(..))
import Data.Enum (class BoundedEnum, class Enum, Cardinality(Cardinality))
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Generic.Rep (class Generic)
import Data.Int (floor, toNumber) as Int
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, unwrap)
import Data.Show.Generic (genericShow)
import Data.String (Pattern(..), joinWith, replace, toLower)
import Data.String.Pattern (Replacement(..))
import Data.Tuple (Tuple)
import Data.Tuple.Nested ((/\))
import Data.Validation.Semigroup (V, invalid, toEither, andThen)
import Foreign (Foreign, F, ForeignError(..), fail, typeOf)
import Foreign.Index (readProp)
import Types.UUID (UUID, parseUUID, validateUUID)
import Utils.Formatting (invertOrdering, parseCommaList)
import Utils.Validation (validateInt, validateNumber, validatePercentage, validateString, validateUrl)
import Yoga.JSON (class ReadForeign, class WriteForeign, readImpl, writeImpl)


data InventoryResponse
  = InventoryData Inventory
  | Message String

derive instance genericInventory :: Generic Inventory _
instance showInventory :: Show Inventory where
  show = genericShow

derive instance genericInventoryResponse :: Generic InventoryResponse _
instance showInventoryResponse :: Show InventoryResponse where
  show = genericShow

newtype Inventory = Inventory (Array MenuItem)

derive instance eqInventory :: Eq Inventory

type MenuItemRecord =
  { sort :: Int
  , sku :: UUID
  , brand :: String
  , name :: String
  , price :: Discrete USD
  , measure_unit :: String
  , per_package :: String
  , quantity :: Int
  , category :: ItemCategory
  , subcategory :: String
  , description :: String
  , tags :: Array String
  , effects :: Array String
  , strain_lineage :: StrainLineage
  }

newtype MenuItem = MenuItem MenuItemRecord

derive instance Newtype MenuItem _
derive instance eqMenuItem :: Eq MenuItem
derive instance ordMenuItem :: Ord MenuItem

data ItemCategory
  = Flower
  | PreRolls
  | Vaporizers
  | Edibles
  | Drinks
  | Concentrates
  | Topicals
  | Tinctures
  | Accessories

derive instance eqItemCategory :: Eq ItemCategory
derive instance ordItemCategory :: Ord ItemCategory

data StrainLineage = StrainLineage
  { thc :: String
  , cbg :: String
  , strain :: String
  , creator :: String
  , species :: Species
  , dominant_terpene :: String
  , terpenes :: Array String
  , lineage :: Array String
  , leafly_url :: String
  , img :: String
  }

derive instance genericStrainLineage :: Generic StrainLineage _
derive instance eqStrainLineage :: Eq StrainLineage
derive instance ordStrainLineage :: Ord StrainLineage

data Species
  = Indica
  | IndicaDominantHybrid
  | Hybrid
  | SativaDominantHybrid
  | Sativa

derive instance eqItemSpecies :: Eq Species
derive instance ordItemSpecies :: Ord Species

type MenuItemFormInput =
  { sort :: String
  , sku :: String
  , brand :: String
  , name :: String
  , price :: String
  , measure_unit :: String
  , per_package :: String
  , quantity :: String
  , category :: String
  , subcategory :: String
  , description :: String
  , tags :: String
  , effects :: String
  , strain_lineage :: StrainLineageFormInput
  }

type StrainLineageFormInput =
  { thc :: String
  , cbg :: String
  , strain :: String
  , creator :: String
  , species :: String
  , dominant_terpene :: String
  , terpenes :: String
  , lineage :: String
  , leafly_url :: String
  , img :: String
  }

instance Enum ItemCategory where
  succ Flower = Just PreRolls
  succ PreRolls = Just Vaporizers
  succ Vaporizers = Just Edibles
  succ Edibles = Just Drinks
  succ Drinks = Just Concentrates
  succ Concentrates = Just Topicals
  succ Topicals = Just Tinctures
  succ Tinctures = Just Accessories
  succ Accessories = Nothing

  pred PreRolls = Just Flower
  pred Vaporizers = Just PreRolls
  pred Edibles = Just Vaporizers
  pred Drinks = Just Edibles
  pred Concentrates = Just Drinks
  pred Topicals = Just Concentrates
  pred Tinctures = Just Topicals
  pred Accessories = Just Tinctures
  pred Flower = Nothing

instance Bounded ItemCategory where
  bottom = Flower
  top = Accessories

instance BoundedEnum ItemCategory where
  cardinality = Cardinality 9
  fromEnum Flower = 0
  fromEnum PreRolls = 1
  fromEnum Vaporizers = 2
  fromEnum Edibles = 3
  fromEnum Drinks = 4
  fromEnum Concentrates = 5
  fromEnum Topicals = 6
  fromEnum Tinctures = 7
  fromEnum Accessories = 8

  toEnum 0 = Just Flower
  toEnum 1 = Just PreRolls
  toEnum 2 = Just Vaporizers
  toEnum 3 = Just Edibles
  toEnum 4 = Just Drinks
  toEnum 5 = Just Concentrates
  toEnum 6 = Just Topicals
  toEnum 7 = Just Tinctures
  toEnum 8 = Just Accessories
  toEnum _ = Nothing

instance Show ItemCategory where
  show Flower = "Flower"
  show PreRolls = "PreRolls"
  show Vaporizers = "Vaporizers"
  show Edibles = "Edibles"
  show Drinks = "Drinks"
  show Concentrates = "Concentrates"
  show Topicals = "Topicals"
  show Tinctures = "Tinctures"
  show Accessories = "Accessories"

instance Enum Species where
  succ Indica = Just IndicaDominantHybrid
  succ IndicaDominantHybrid = Just Hybrid
  succ Hybrid = Just SativaDominantHybrid
  succ SativaDominantHybrid = Just Sativa
  succ Sativa = Nothing

  pred IndicaDominantHybrid = Just Indica
  pred Hybrid = Just IndicaDominantHybrid
  pred SativaDominantHybrid = Just Hybrid
  pred Sativa = Just SativaDominantHybrid
  pred Indica = Nothing

instance Bounded Species where
  bottom = Indica
  top = Sativa

instance BoundedEnum Species where
  cardinality = Cardinality 5
  fromEnum Indica = 0
  fromEnum IndicaDominantHybrid = 1
  fromEnum Hybrid = 2
  fromEnum SativaDominantHybrid = 3
  fromEnum Sativa = 4

  toEnum 0 = Just Indica
  toEnum 1 = Just IndicaDominantHybrid
  toEnum 2 = Just Hybrid
  toEnum 3 = Just SativaDominantHybrid
  toEnum 4 = Just Sativa
  toEnum _ = Nothing

instance Show Species where
  show Indica = "Indica"
  show IndicaDominantHybrid = "IndicaDominantHybrid"
  show Hybrid = "Hybrid"
  show SativaDominantHybrid = "SativaDominantHybrid"
  show Sativa = "Sativa"

instance writeForeignMenuItem :: WriteForeign MenuItem where
  writeImpl (MenuItem item) = writeImpl
    { sort: item.sort
    , sku: item.sku
    , brand: item.brand
    , name: item.name
    , price: unwrap item.price
    , measure_unit: item.measure_unit
    , per_package: item.per_package
    , quantity: item.quantity
    , category: show item.category
    , subcategory: item.subcategory
    , description: item.description
    , tags: item.tags
    , effects: item.effects
    , strain_lineage: item.strain_lineage
    }

instance writeForeignStrainLineage :: WriteForeign StrainLineage where
  writeImpl (StrainLineage lineage) = writeImpl
    { thc: lineage.thc
    , cbg: lineage.cbg
    , strain: lineage.strain
    , creator: lineage.creator
    , species: show lineage.species
    , dominant_terpene: lineage.dominant_terpene
    , terpenes: lineage.terpenes
    , lineage: lineage.lineage
    , leafly_url: lineage.leafly_url
    , img: lineage.img
    }

instance writeForeignInventory :: WriteForeign Inventory where
  writeImpl (Inventory items) = writeImpl items

instance writeForeignSpecies :: WriteForeign Species where
  writeImpl = writeImpl <<< show

instance writeForeignInventoryResponse :: WriteForeign InventoryResponse where
  writeImpl (InventoryData inventory) = writeImpl
    { type: "data", value: inventory }
  writeImpl (Message msg) = writeImpl { type: "message", value: msg }

instance readForeignMenuItem :: ReadForeign MenuItem where
  readImpl json = do
    sort <- readProp "sort" json >>= readImpl
    skuStr <- readProp "sku" json >>= readImpl
    sku <- case parseUUID skuStr of
      Just uuid -> pure uuid
      Nothing -> fail $ ForeignError "Invalid UUID format for sku"
    brand <- readProp "brand" json >>= readImpl
    name <- readProp "name" json >>= readImpl
    priceValue <-
      readProp "price" json >>= readImpl :: F Int -- Expect Int from backend
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
    effects <- readProp "effects" json >>= readImpl
    strain_lineage <- readProp "strain_lineage" json >>= readImpl

    -- The backend is sending price as Int (cents), create Discrete USD directly
    pure $ MenuItem
      { sort
      , sku
      , brand
      , name
      , price: Discrete priceValue -- Create Discrete USD directly from the Int value
      , measure_unit
      , per_package
      , quantity
      , category
      , subcategory
      , description
      , tags
      , effects
      , strain_lineage
      }

-- Helper function to check if a number has no decimal component
isWholeNumber :: Number -> Boolean
isWholeNumber n = n == Int.toNumber (Int.floor n)

-- Helper function to determine if a value is an integer
isInt :: Number -> Boolean
isInt n = n == Int.toNumber (Int.floor n)

instance readForeignInventory :: ReadForeign Inventory where
  readImpl json = do
    items <- readImpl json :: F (Array MenuItem)
    pure $ Inventory items

instance readForeignSpecies :: ReadForeign Species where
  readImpl json = do
    str <- readImpl json
    case str of
      "Indica" -> pure Indica
      "IndicaDominantHybrid" -> pure IndicaDominantHybrid
      "Hybrid" -> pure Hybrid
      "SativaDominantHybrid" -> pure SativaDominantHybrid
      "Sativa" -> pure Sativa
      _ -> fail (ForeignError "Invalid Species value")

instance readForeignStrainLineage :: ReadForeign StrainLineage where
  readImpl json = do
    thc <- readProp "thc" json >>= readImpl
    cbg <- readProp "cbg" json >>= readImpl
    strain <- readProp "strain" json >>= readImpl
    creator <- readProp "creator" json >>= readImpl
    species <- readProp "species" json >>= readImpl
    dominant_terpene <- readProp "dominant_terpene" json >>= readImpl
    terpenes <- readProp "terpenes" json >>= readImpl
    lineage <- readProp "lineage" json >>= readImpl
    leafly_url <- readProp "leafly_url" json >>= readImpl
    img <- readProp "img" json >>= readImpl
    pure $ StrainLineage
      { thc
      , cbg
      , strain
      , creator
      , species
      , dominant_terpene
      , terpenes
      , lineage
      , leafly_url
      , img
      }

instance readForeignInventoryResponse :: ReadForeign InventoryResponse where
  readImpl f = do
    obj <- readImpl f
    case obj of

      array | isArray array -> do
        inventory <- readImpl array :: F Inventory
        pure $ InventoryData inventory

      _ -> do
        typeField <- readProp "type" obj >>= readImpl :: F String
        case typeField of
          "data" -> do
            value <- readProp "value" obj >>= readImpl :: F Inventory
            pure $ InventoryData value
          "message" -> do
            value <- readProp "value" obj >>= readImpl :: F String
            pure $ Message value
          _ -> fail $ ForeignError "Invalid response type"
    where
    isArray :: Foreign -> Boolean
    isArray value = typeOf value == "array"

derive instance Generic MenuItem _

instance showMenuItem :: Show MenuItem where
  show (MenuItem item) =
    "{ name: " <> show item.name
      <> ", brand: "
      <> show item.brand
      <> ", quantity: "
      <> show item.quantity
      <> " }"

instance showStrainLineage :: Show StrainLineage where
  show (StrainLineage lineage) =
    "{ strain: " <> show lineage.strain
      <> ", species: "
      <> show lineage.species
      <> " }"

getItemName :: MenuItem -> String
getItemName (MenuItem item) = item.name

findItemNameBySku :: UUID -> Inventory -> String
findItemNameBySku sku (Inventory items) =
  case find (\(MenuItem item) -> item.sku == sku) items of
    Just (MenuItem item) -> item.name
    Nothing -> "Unknown Item"

findItemBySku :: UUID -> Inventory -> Maybe MenuItem
findItemBySku sku (Inventory items) =
  find (\(MenuItem item) -> item.sku == sku) items

generateClassName
  :: { category :: ItemCategory, subcategory :: String, species :: Species }
  -> String
generateClassName item =
  "species-" <> toClassName (show item.species)
    <> " category-"
    <> toClassName (show item.category)
    <> " subcategory-"
    <> toClassName item.subcategory

toClassName :: String -> String
toClassName str = toLower (replace (Pattern " ") (Replacement "-") str)


validateCategory :: String -> String -> V (Array String) ItemCategory
validateCategory fieldName str = case str of
  "Flower" -> pure Flower
  "PreRolls" -> pure PreRolls
  "Vaporizers" -> pure Vaporizers
  "Edibles" -> pure Edibles
  "Drinks" -> pure Drinks
  "Concentrates" -> pure Concentrates
  "Topicals" -> pure Topicals
  "Tinctures" -> pure Tinctures
  "Accessories" -> pure Accessories
  _ -> invalid [ fieldName <> " has invalid category value" ]

validateSpecies :: String -> String -> V (Array String) Species
validateSpecies fieldName str = case str of
  "Indica" -> pure Indica
  "IndicaDominantHybrid" -> pure IndicaDominantHybrid
  "Hybrid" -> pure Hybrid
  "SativaDominantHybrid" -> pure SativaDominantHybrid
  "Sativa" -> pure Sativa
  _ -> invalid [ fieldName <> " has invalid species value" ]

mapValidationErrors :: forall a. V (Array String) a -> Either String a
mapValidationErrors validation =
  case toEither validation of
    Left errors -> Left (joinWith ", " errors)
    Right value -> Right value

validateMenuItem :: MenuItemFormInput -> Either String MenuItem
validateMenuItem input =
  case toEither validationResult of
    Left errors -> Left (joinWith ", " errors)
    Right result -> Right result
  where
  validationResult =
    validateUUID "SKU" input.sku `andThen` \sku ->
      validateString "Name" input.name `andThen` \name ->
        validateString "Brand" input.brand `andThen` \brand ->
          validateNumber "Price" input.price `andThen` \priceValue ->
            validateInt "Quantity" input.quantity `andThen` \quantity ->
              validateString "Measure Unit" input.measure_unit `andThen`
                \measure_unit ->
                  validateString "Per Package" input.per_package `andThen`
                    \per_package ->
                      validateCategory "Category" input.category `andThen`
                        \category ->
                          validateString "Subcategory" input.subcategory
                            `andThen` \subcategory ->
                              validateStrainLineage input.strain_lineage
                                `andThen` \strain_lineage ->
                                  validateInt "Sort" input.sort `andThen`
                                    \sort ->
                                      -- Convert dollars to cents and create Discrete value
                                      let
                                        priceCents = Int.floor
                                          (priceValue * 100.0)
                                      in
                                        pure $ MenuItem
                                          { sort
                                          , sku
                                          , brand
                                          , name
                                          , price: Discrete priceCents
                                          , measure_unit
                                          , per_package
                                          , quantity
                                          , category
                                          , subcategory
                                          , description: input.description
                                          , tags: parseCommaList input.tags
                                          , effects: parseCommaList
                                              input.effects
                                          , strain_lineage
                                          }

validateStrainLineage
  :: StrainLineageFormInput -> V (Array String) StrainLineage
validateStrainLineage input =
  validatePercentage "THC" input.thc `andThen` \thc ->
    validatePercentage "CBG" input.cbg `andThen` \cbg ->
      validateString "Strain" input.strain `andThen` \strain ->
        validateString "Creator" input.creator `andThen` \creator ->
          validateSpecies "Species" input.species `andThen` \species ->
            validateString "Dominant Terpene" input.dominant_terpene `andThen`
              \dominant_terpene ->
                validateUrl "Leafly URL" input.leafly_url `andThen`
                  \leafly_url ->
                    validateUrl "Image URL" input.img `andThen` \img ->
                      pure $ StrainLineage
                        { thc
                        , cbg
                        , strain
                        , creator
                        , species
                        , dominant_terpene
                        , terpenes: parseCommaList input.terpenes
                        , lineage: parseCommaList input.lineage
                        , leafly_url
                        , img
                        }

compareMenuItems :: LiveViewConfig -> MenuItem -> MenuItem -> Ordering
compareMenuItems config (MenuItem item1) (MenuItem item2) =
  let
    StrainLineage meta1 = item1.strain_lineage
    StrainLineage meta2 = item2.strain_lineage

    compareByField :: Tuple SortField SortOrder -> Ordering
    compareByField (sortField /\ sortOrder) =
      let
        fieldComparison = case sortField of
          SortByOrder -> compare item1.sort item2.sort
          SortByName -> compare item1.name item2.name
          SortByCategory -> compare item1.category item2.category
          SortBySubCategory -> compare item1.subcategory item2.subcategory
          SortBySpecies -> compare meta1.species meta2.species
          SortBySKU -> compare item1.sku item2.sku
          SortByPrice -> compare item1.price item2.price
          SortByQuantity -> compare item1.quantity item2.quantity
      in
        case sortOrder of
          Ascending -> fieldComparison
          Descending -> invertOrdering fieldComparison

    compareWithPriority :: Array (Tuple SortField SortOrder) -> Ordering
    compareWithPriority priorities = case Array.uncons priorities of
      Nothing -> EQ
      Just { head: priority, tail: rest } ->
        case compareByField priority of
          EQ -> compareWithPriority rest
          result -> result
  in
    compareWithPriority config.sortFields