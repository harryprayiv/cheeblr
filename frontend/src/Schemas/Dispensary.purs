module Schemas.Dispensary where

import Codegen.Schema (DomainSchema, FieldType(..), InputType(..), TypeKind(..), Validation(..))
import Data.Array.NonEmpty as NEA
import Data.Maybe (Maybe(..))

dispensarySchema :: DomainSchema
dispensarySchema =
  { moduleName: "Generated.Types.Inventory"
  , configModuleName: "Generated.Config.InventoryFields"
  , validationModuleName: "Generated.Utils.InventoryValidation"
  , enums:
      [ { name: "ItemCategory"
        , variants: NEA.cons' "Flower" 
            ["PreRolls", "Vaporizers", "Edibles", "Drinks", "Concentrates", "Topicals", "Tinctures", "Accessories"]
        , description: Just "Product categories for dispensary inventory"
        }
      , { name: "Species"
        , variants: NEA.cons' "Indica" 
            ["IndicaDominantHybrid", "Hybrid", "SativaDominantHybrid", "Sativa"]
        , description: Just "Cannabis species classification"
        }
      ]
  , records:
      [ { name: "MenuItem"
        , kind: RecordType
        , description: Just "A single inventory item"
        , fields:
            [ { name: "sku"
              , fieldType: FUuid
              , validations: [Required]
              , inputType: TextInput
              , ui: { label: "SKU", placeholder: "Enter UUID", errorMessage: "Valid UUID required" }
              }
            , { name: "name"
              , fieldType: FString
              , validations: [Required, ExtendedAlphanumeric, MaxLength 50]
              , inputType: TextInput
              , ui: { label: "Name", placeholder: "Enter product name", errorMessage: "Name required, max 50 chars" }
              }
            , { name: "brand"
              , fieldType: FString
              , validations: [Required, ExtendedAlphanumeric]
              , inputType: TextInput
              , ui: { label: "Brand", placeholder: "Enter brand name", errorMessage: "Brand is required" }
              }
            , { name: "price"
              , fieldType: FMoney
              , validations: [Required]
              , inputType: TextInput
              , ui: { label: "Price", placeholder: "Enter price (e.g. 12.99)", errorMessage: "Valid dollar amount required" }
              }
            , { name: "quantity"
              , fieldType: FInt
              , validations: [Required, NonNegative]
              , inputType: NumberInput
              , ui: { label: "Quantity", placeholder: "Enter quantity", errorMessage: "Must be non-negative" }
              }
            , { name: "category"
              , fieldType: FEnum "ItemCategory"
              , validations: [Required]
              , inputType: Dropdown
              , ui: { label: "Category", placeholder: "Select...", errorMessage: "Category required" }
              }
            , { name: "subcategory"
              , fieldType: FString
              , validations: [Required, Alphanumeric]
              , inputType: TextInput
              , ui: { label: "Subcategory", placeholder: "Enter subcategory", errorMessage: "Subcategory required" }
              }
            , { name: "description"
              , fieldType: FString
              , validations: []
              , inputType: TextArea { rows: 4, cols: 40 }
              , ui: { label: "Description", placeholder: "Enter description", errorMessage: "" }
              }
            , { name: "tags"
              , fieldType: FArray FString
              , validations: [CommaList]
              , inputType: TextInput
              , ui: { label: "Tags", placeholder: "Enter tags (comma-separated)", errorMessage: "Invalid format" }
              }
            , { name: "effects"
              , fieldType: FArray FString
              , validations: [CommaList]
              , inputType: TextInput
              , ui: { label: "Effects", placeholder: "Enter effects (comma-separated)", errorMessage: "Invalid format" }
              }
            , { name: "strain_lineage"
              , fieldType: FNested "StrainLineage"
              , validations: []
              , inputType: Hidden
              , ui: { label: "", placeholder: "", errorMessage: "" }
              }
            ]
        }
      , { name: "StrainLineage"
        , kind: RecordType
        , description: Just "Cannabis strain metadata"
        , fields:
            [ { name: "thc", fieldType: FPercentage, validations: [Required]
              , inputType: TextInput
              , ui: { label: "THC %", placeholder: "e.g. 22.50%", errorMessage: "Format: XX.XX%" }
              }
            , { name: "cbg", fieldType: FPercentage, validations: [Required]
              , inputType: TextInput
              , ui: { label: "CBG %", placeholder: "e.g. 0.50%", errorMessage: "Format: XX.XX%" }
              }
            , { name: "strain", fieldType: FString, validations: [Required, Alphanumeric]
              , inputType: TextInput
              , ui: { label: "Strain", placeholder: "Enter strain name", errorMessage: "Strain required" }
              }
            , { name: "creator", fieldType: FString, validations: [Required, Alphanumeric]
              , inputType: TextInput
              , ui: { label: "Creator", placeholder: "Enter creator", errorMessage: "Creator required" }
              }
            , { name: "species", fieldType: FEnum "Species", validations: [Required]
              , inputType: Dropdown
              , ui: { label: "Species", placeholder: "Select...", errorMessage: "Species required" }
              }
            , { name: "dominant_terpene", fieldType: FString, validations: [Required, Alphanumeric]
              , inputType: TextInput
              , ui: { label: "Dominant Terpene", placeholder: "Enter terpene", errorMessage: "Required" }
              }
            , { name: "terpenes", fieldType: FArray FString, validations: [CommaList]
              , inputType: TextInput
              , ui: { label: "Terpenes", placeholder: "Comma-separated", errorMessage: "Invalid format" }
              }
            , { name: "lineage", fieldType: FArray FString, validations: [CommaList]
              , inputType: TextInput
              , ui: { label: "Lineage", placeholder: "Comma-separated", errorMessage: "Invalid format" }
              }
            , { name: "leafly_url", fieldType: FUrl, validations: [Required, ValidUrl]
              , inputType: TextInput
              , ui: { label: "Leafly URL", placeholder: "https://...", errorMessage: "Valid URL required" }
              }
            , { name: "img", fieldType: FUrl, validations: [Required, ValidUrl]
              , inputType: TextInput
              , ui: { label: "Image URL", placeholder: "https://...", errorMessage: "Valid URL required" }
              }
            ]
        }
      ]
  }