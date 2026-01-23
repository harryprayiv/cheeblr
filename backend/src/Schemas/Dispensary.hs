{-# LANGUAGE OverloadedStrings #-}

module Schemas.Dispensary
  ( dispensarySchema
  ) where

import Codegen.Schema

dispensarySchema :: DomainSchema
dispensarySchema = DomainSchema
  { schemaModuleName = "Types.Inventory"
  , schemaDbModuleName = "DB.Inventory"
  , schemaApiModuleName = "API.Inventory"
  , schemaEnums =
      [ speciesEnum
      , itemCategoryEnum
      ]
  , schemaRecords =
      [ strainLineageRecord
      , menuItemRecord
      , inventoryRecord
      , inventoryResponseRecord
      ]
  }

speciesEnum :: EnumDef
speciesEnum = EnumDef
  { enumName = "Species"
  , enumDisplayName = "Species"
  , enumVariants =
      [ "Indica"
      , "IndicaDominantHybrid"
      , "Hybrid"
      , "SativaDominantHybrid"
      , "Sativa"
      ]
  , enumDescription = Just "Cannabis species classification"
  , enumDeriving = ["Show", "Eq", "Ord", "Generic", "FromJSON", "ToJSON", "Read"]
  }

itemCategoryEnum :: EnumDef
itemCategoryEnum = EnumDef
  { enumName = "ItemCategory"
  , enumDisplayName = "Category"
  , enumVariants =
      [ "Flower"
      , "PreRolls"
      , "Vaporizers"
      , "Edibles"
      , "Drinks"
      , "Concentrates"
      , "Topicals"
      , "Tinctures"
      , "Accessories"
      ]
  , enumDescription = Just "Product categories for dispensary inventory"
  , enumDeriving = ["Show", "Eq", "Ord", "Generic", "FromJSON", "ToJSON", "Read"]
  }

strainLineageRecord :: RecordDef
strainLineageRecord = RecordDef
  { recordName = "StrainLineage"
  , recordKind = RecordType
  , recordFields =
      [ (field "thc" FText) { fieldValidations = [Required] }
      , (field "cbg" FText) { fieldValidations = [Required] }
      , (field "strain" FText) { fieldValidations = [Required] }
      , (field "creator" FText) { fieldValidations = [Required] }
      , (field "species" (FEnum "Species")) { fieldValidations = [Required] }
      , (field "dominant_terpene" FText) { fieldValidations = [Required] }
      , field "terpenes" (FVector FText)
      , field "lineage" (FVector FText)
      , (field "leafly_url" FText) { fieldValidations = [Required, ValidUrl] }
      , (field "img" FText) { fieldValidations = [Required, ValidUrl] }
      ]
  , recordDescription = Just "Cannabis strain metadata"
  , recordDeriving = ["Show", "Generic"]
  }

menuItemRecord :: RecordDef
menuItemRecord = RecordDef
  { recordName = "MenuItem"
  , recordKind = RecordType
  , recordFields =
      [ (field "sort" FInt) { fieldValidations = [Required, NonNegative] }
      , (field "sku" FUuid) { fieldValidations = [Required] }
      , (field "brand" FText) { fieldValidations = [Required] }
      , (field "name" FText) { fieldValidations = [Required, MaxLength 50] }
      , (field "price" FMoney) { fieldValidations = [Required, NonNegative] }
      , (field "measure_unit" FText) { fieldValidations = [Required] }
      , (field "per_package" FText) { fieldValidations = [Required] }
      , (field "quantity" FInt) { fieldValidations = [Required, NonNegative] }
      , (field "category" (FEnum "ItemCategory")) { fieldValidations = [Required] }
      , (field "subcategory" FText) { fieldValidations = [Required] }
      , field "description" FText
      , field "tags" (FVector FText)
      , field "effects" (FVector FText)
      , field "strain_lineage" (FNested "StrainLineage")
      ]
  , recordDescription = Just "A single inventory item"
  , recordDeriving = ["Show", "Generic"]
  }

inventoryRecord :: RecordDef
inventoryRecord = RecordDef
  { recordName = "Inventory"
  , recordKind = NewtypeOver "V.Vector MenuItem"
  , recordFields = []
  , recordDescription = Just "Collection of menu items"
  , recordDeriving = ["Show", "Generic"]
  }

inventoryResponseRecord :: RecordDef
inventoryResponseRecord = RecordDef
  { recordName = "InventoryResponse"
  , recordKind = RecordType
  , recordFields = []
  , recordDescription = Just "API response wrapper"
  , recordDeriving = ["Show", "Generic"]
  }