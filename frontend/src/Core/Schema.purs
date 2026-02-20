module Cheeblr.Core.Schema where

import Prelude

import Cheeblr.Core.Domain (categoryRegistry, speciesRegistry)
import Cheeblr.Core.Money (formatCentsStrToDecimal)
import Cheeblr.Core.Product (Product(..))
import Cheeblr.Core.Tag (toOptions, unTag)
import Cheeblr.Core.Validation (ValidationRule, allOf, anyOf, alwaysValid, nonEmpty, alphanumeric, extendedAlphanumeric, percentage, dollarAmount, nonNegativeInteger, fraction, commaList, validUrl, validMeasurementUnit, inRegistry, maxLength)
import Data.Array as Data.Array
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Data.String (joinWith, trim)

----------------------------------------------------------------------
-- Field Types
----------------------------------------------------------------------

-- | How a field should be rendered. The UI layer maps these
-- | to concrete Deku components.
data FieldType
  = TextField
  | TextArea { rows :: Int, cols :: Int }
  | PasswordField
  | NumberField
  | Dropdown (Array { value :: String, label :: String })
  | TagDropdown
      { options :: Array { value :: String, label :: String }
      , emptyOption :: Maybe { value :: String, label :: String }
      }

----------------------------------------------------------------------
-- Field Descriptor
----------------------------------------------------------------------

-- | A complete, pure description of a form field.
-- | Contains everything needed to render, validate, and extract values.
-- | No UI types, no Effect, no Poll — just data.
type FieldDescriptor =
  { key :: String                          -- form field key (e.g. "name", "meta.thc")
  , label :: String                        -- display label
  , placeholder :: String
  , fieldType :: FieldType
  , validation :: ValidationRule
  , errorMessage :: String
  , formatInput :: String -> String        -- normalization before validation
  , defaultValue :: String                 -- for create mode
  , extractValue :: Product -> String      -- for edit mode
  }

----------------------------------------------------------------------
-- Form Schema
----------------------------------------------------------------------

-- | An ordered list of field descriptors defining the entire form.
type FormSchema = Array FieldDescriptor

-- | Get all default values as a key-value list (create mode).
defaults :: FormSchema -> Array { key :: String, value :: String }
defaults schema = schema <#> \f -> { key: f.key, value: f.defaultValue }

-- | Get all values from an existing product (edit mode).
extractAll :: FormSchema -> Product -> Array { key :: String, value :: String }
extractAll schema product =
  schema <#> \f -> { key: f.key, value: f.extractValue product }

----------------------------------------------------------------------
-- The product form schema
----------------------------------------------------------------------

-- | Complete schema for the product (MenuItem) form.
-- | This single definition replaces the duplicated field configs
-- | in CreateItem.purs and EditItem.purs.
productSchema :: FormSchema
productSchema =
  [ -- Core fields
    { key: "brand"
    , label: "Brand"
    , placeholder: "Enter brand name"
    , fieldType: TextField
    , validation: allOf [ nonEmpty, extendedAlphanumeric ]
    , errorMessage: "Brand name is required"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> p.brand
    }
  , { key: "name"
    , label: "Name"
    , placeholder: "Enter product name"
    , fieldType: TextField
    , validation: allOf [ nonEmpty, extendedAlphanumeric, maxLength 50 ]
    , errorMessage: "Name is required, max 50 characters"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> p.name
    }
  , { key: "sku"
    , label: "SKU"
    , placeholder: "Enter UUID"
    , fieldType: TextField
    , validation: alwaysValid  -- auto-generated, always valid
    , errorMessage: "Must be a valid UUID"
    , formatInput: trim
    , defaultValue: ""  -- filled at runtime with genUUID
    , extractValue: \(Product p) -> show p.sku
    }
  , { key: "sort"
    , label: "Sort Order"
    , placeholder: "Enter sort position"
    , fieldType: NumberField
    , validation: nonNegativeInteger
    , errorMessage: "Sort order must be a number"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> show p.sort
    }
  , { key: "price"
    , label: "Price"
    , placeholder: "Enter price in dollars (e.g. 12.99)"
    , fieldType: TextField
    , validation: dollarAmount
    , errorMessage: "Price must be a valid dollar amount"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> formatCentsStrToDecimal (show (unwrap p.price))
    }
  , { key: "quantity"
    , label: "Quantity"
    , placeholder: "Enter quantity"
    , fieldType: NumberField
    , validation: nonNegativeInteger
    , errorMessage: "Quantity must be a non-negative number"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> show p.quantity
    }
  , { key: "perPackage"
    , label: "Per Package"
    , placeholder: "Enter amount per package"
    , fieldType: TextField
    , validation: anyOf [ nonNegativeInteger, fraction ]
    , errorMessage: "Must be a number or fraction"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> p.perPackage
    }
  , { key: "measureUnit"
    , label: "Measure Unit"
    , placeholder: "Enter unit (g, mg, etc)"
    , fieldType: TextField
    , validation: validMeasurementUnit
    , errorMessage: "Valid measurement unit required"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> p.measureUnit
    }
  , { key: "subcategory"
    , label: "Subcategory"
    , placeholder: "Enter subcategory"
    , fieldType: TextField
    , validation: allOf [ nonEmpty, alphanumeric ]
    , errorMessage: "Subcategory is required"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> p.subcategory
    }
    -- Dropdowns
  , { key: "category"
    , label: "Category"
    , placeholder: ""
    , fieldType: TagDropdown
        { options: toOptions categoryRegistry
        , emptyOption: Just { value: "", label: "Select..." }
        }
    , validation: inRegistry categoryRegistry
    , errorMessage: "Please select a category"
    , formatInput: identity
    , defaultValue: ""
    , extractValue: \(Product p) -> unTag p.category
    }
    -- Description / freeform
  , { key: "description"
    , label: "Description"
    , placeholder: "Enter description"
    , fieldType: TextArea { rows: 4, cols: 40 }
    , validation: alwaysValid
    , errorMessage: ""
    , formatInput: identity
    , defaultValue: ""
    , extractValue: \(Product p) -> p.description
    }
  , { key: "tags"
    , label: "Tags"
    , placeholder: "Enter tags (comma-separated)"
    , fieldType: TextField
    , validation: commaList
    , errorMessage: "Invalid format"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> joinWith ", " p.tags
    }
  , { key: "effects"
    , label: "Effects"
    , placeholder: "Enter effects (comma-separated)"
    , fieldType: TextField
    , validation: commaList
    , errorMessage: "Invalid format"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> joinWith ", " p.effects
    }
    -- Strain metadata
  , { key: "meta.thc"
    , label: "THC %"
    , placeholder: "Enter THC percentage"
    , fieldType: TextField
    , validation: percentage
    , errorMessage: "Format: XX.XX%"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> p.meta.thc
    }
  , { key: "meta.cbg"
    , label: "CBG %"
    , placeholder: "Enter CBG percentage"
    , fieldType: TextField
    , validation: percentage
    , errorMessage: "Format: XX.XX%"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> p.meta.cbg
    }
  , { key: "meta.species"
    , label: "Species"
    , placeholder: ""
    , fieldType: TagDropdown
        { options: toOptions speciesRegistry
        , emptyOption: Just { value: "", label: "Select..." }
        }
    , validation: inRegistry speciesRegistry
    , errorMessage: "Please select a species"
    , formatInput: identity
    , defaultValue: ""
    , extractValue: \(Product p) -> unTag p.meta.species
    }
  , { key: "meta.strain"
    , label: "Strain"
    , placeholder: "Enter strain name"
    , fieldType: TextField
    , validation: allOf [ nonEmpty, alphanumeric ]
    , errorMessage: "Strain name is required"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> p.meta.strain
    }
  , { key: "meta.dominantTerpene"
    , label: "Dominant Terpene"
    , placeholder: "Enter dominant terpene"
    , fieldType: TextField
    , validation: allOf [ nonEmpty, alphanumeric ]
    , errorMessage: "Required"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> p.meta.dominantTerpene
    }
  , { key: "meta.terpenes"
    , label: "Terpenes"
    , placeholder: "Enter terpenes (comma-separated)"
    , fieldType: TextField
    , validation: commaList
    , errorMessage: "Invalid format"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> joinWith ", " p.meta.terpenes
    }
  , { key: "meta.lineage"
    , label: "Lineage"
    , placeholder: "Enter lineage (comma-separated)"
    , fieldType: TextField
    , validation: commaList
    , errorMessage: "Invalid format"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> joinWith ", " p.meta.lineage
    }
  , { key: "meta.creator"
    , label: "Creator"
    , placeholder: "Enter creator name"
    , fieldType: TextField
    , validation: allOf [ nonEmpty, alphanumeric ]
    , errorMessage: "Required"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> p.meta.creator
    }
  , { key: "meta.leaflyUrl"
    , label: "Leafly URL"
    , placeholder: "Enter Leafly URL"
    , fieldType: TextField
    , validation: validUrl
    , errorMessage: "Valid URL required"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> p.meta.leaflyUrl
    }
  , { key: "meta.img"
    , label: "Image URL"
    , placeholder: "Enter image URL"
    , fieldType: TextField
    , validation: validUrl
    , errorMessage: "Valid URL required"
    , formatInput: trim
    , defaultValue: ""
    , extractValue: \(Product p) -> p.meta.img
    }
  ]

----------------------------------------------------------------------
-- Schema queries
----------------------------------------------------------------------

-- | Find a field descriptor by key.
findField :: String -> FormSchema -> Maybe FieldDescriptor
findField key schema =
  Data.Array.find (\f -> f.key == key) schema

-- | Get just the dropdown/tag fields.
dropdownFields :: FormSchema -> Array FieldDescriptor
dropdownFields = Data.Array.filter \f -> case f.fieldType of
  Dropdown _ -> true
  TagDropdown _ -> true
  _ -> false

-- | Get fields that require non-empty validation (for "required" indicators).
requiredFields :: FormSchema -> Array FieldDescriptor
requiredFields = Data.Array.filter \f ->
  f.errorMessage /= ""

-- | Count of validatable fields (for progress tracking).
fieldCount :: FormSchema -> Int
fieldCount = Data.Array.length