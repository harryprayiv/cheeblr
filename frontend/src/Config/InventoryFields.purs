module Config.InventoryFields where

import Prelude

import Data.Maybe (Maybe(..))
import Data.String (trim)
import Types.Formatting (DropdownConfig, ValidationRule(..), FieldConfig)
import Types.Inventory (ItemCategory, Species)
import Utils.Formatting (formatCentsToDisplayDollars, getAllEnumValues)
import Utils.Validation (allOf, alphanumeric, anyOf, commaList, dollarAmount, extendedAlphanumeric, fraction, maxLength, nonEmpty, nonNegativeInteger, percentage, validMeasurementUnit, validUrl)

nameConfig :: String -> FieldConfig
nameConfig defaultValue =
  { label: "Name"
  , placeholder: "Enter product name"
  , defaultValue
  , validation: allOf [ nonEmpty, extendedAlphanumeric, maxLength 50 ]
  , errorMessage: "Name is required and must be less than 50 characters"
  , formatInput: trim
  }

passwordConfig :: String -> FieldConfig
passwordConfig defaultValue =
  { label: "Password"
  , placeholder: "Enter password"
  , defaultValue
  , validation: nonEmpty
  , errorMessage: "Password is required"
  , formatInput: identity
  }

skuConfig :: String -> FieldConfig
skuConfig defaultValue =
  { label: "SKU"
  , placeholder: "Enter UUID"
  , defaultValue
  , validation: ValidationRule \_ -> true
  , errorMessage: "Required, must be a valid UUID"
  , formatInput: trim
  }

brandConfig :: String -> FieldConfig
brandConfig defaultValue =
  { label: "Brand"
  , placeholder: "Enter brand name"
  , defaultValue
  , validation: allOf [ nonEmpty, extendedAlphanumeric ]
  , errorMessage: "Brand name is required"
  , formatInput: trim
  }

priceConfig :: String -> FieldConfig
priceConfig defaultValue =
  { label: "Price"
  , placeholder: "Enter price in dollars (e.g. 12.99)"
  , defaultValue: formatCentsToDisplayDollars defaultValue
  , validation: dollarAmount
  , errorMessage: "Price must be a valid dollar amount"
  , formatInput: trim
  }

quantityConfig :: String -> FieldConfig
quantityConfig defaultValue =
  { label: "Quantity"
  , placeholder: "Enter quantity"
  , defaultValue
  , validation: nonNegativeInteger
  , errorMessage: "Quantity must be a non-negative number"
  , formatInput: trim
  }

sortConfig :: String -> FieldConfig
sortConfig defaultValue =
  { label: "Sort Order"
  , placeholder: "Enter sort position"
  , defaultValue
  , validation: nonNegativeInteger
  , errorMessage: "Sort order must be a number"
  , formatInput: trim
  }

measureUnitConfig :: String -> FieldConfig
measureUnitConfig defaultValue =
  { label: "Measure Unit"
  , placeholder: "Enter unit (g, mg, etc)"
  , defaultValue
  , validation: validMeasurementUnit
  , errorMessage: "Measure unit is required"
  , formatInput: trim
  }

perPackageConfig :: String -> FieldConfig
perPackageConfig defaultValue =
  { label: "Per Package"
  , placeholder: "Enter amount per package"
  , defaultValue
  , validation: anyOf [ nonNegativeInteger, fraction ]
  , errorMessage: "Per package must be a whole number or fraction"
  , formatInput: trim
  }

subcategoryConfig :: String -> FieldConfig
subcategoryConfig defaultValue =
  { label: "Subcategory"
  , placeholder: "Enter subcategory"
  , defaultValue
  , validation: allOf [ nonEmpty, alphanumeric ]
  , errorMessage: "Subcategory is required"
  , formatInput: trim
  }

descriptionConfig :: String -> FieldConfig
descriptionConfig defaultValue =
  { label: "Description"
  , placeholder: "Enter description"
  , defaultValue: defaultValue
  , validation: ValidationRule \_ -> true
  , errorMessage: "Description is required"
  , formatInput: identity
  }

tagsConfig :: String -> FieldConfig
tagsConfig defaultValue =
  { label: "Tags"
  , placeholder: "Enter tags (comma-separated)"
  , defaultValue
  , validation: commaList
  , errorMessage: "Invalid format"
  , formatInput: trim
  }

effectsConfig :: String -> FieldConfig
effectsConfig defaultValue =
  { label: "Effects"
  , placeholder: "Enter effects (comma-separated)"
  , defaultValue
  , validation: commaList
  , errorMessage: "Invalid format"
  , formatInput: trim
  }

thcConfig :: String -> FieldConfig
thcConfig defaultValue =
  { label: "THC %"
  , placeholder: "Enter THC percentage"
  , defaultValue
  , validation: percentage
  , errorMessage: "THC % must be in format XX.XX%"
  , formatInput: trim
  }

cbgConfig :: String -> FieldConfig
cbgConfig defaultValue =
  { label: "CBG %"
  , placeholder: "Enter CBG percentage"
  , defaultValue
  , validation: percentage
  , errorMessage: "CBG % must be in format XX.XX%"
  , formatInput: trim
  }

strainConfig :: String -> FieldConfig
strainConfig defaultValue =
  { label: "Strain"
  , placeholder: "Enter strain name"
  , defaultValue
  , validation: allOf [ nonEmpty, alphanumeric ]
  , errorMessage: "Strain name is required"
  , formatInput: trim
  }

creatorConfig :: String -> FieldConfig
creatorConfig defaultValue =
  { label: "Creator"
  , placeholder: "Enter creator name"
  , defaultValue
  , validation: allOf [ nonEmpty, alphanumeric ]
  , errorMessage: "Creator name is required"
  , formatInput: trim
  }

dominantTerpeneConfig :: String -> FieldConfig
dominantTerpeneConfig defaultValue =
  { label: "Dominant Terpene"
  , placeholder: "Enter dominant terpene"
  , defaultValue
  , validation: allOf [ nonEmpty, alphanumeric ]
  , errorMessage: "Dominant terpene is required"
  , formatInput: trim
  }

terpenesConfig :: String -> FieldConfig
terpenesConfig defaultValue =
  { label: "Terpenes"
  , placeholder: "Enter terpenes (comma-separated)"
  , defaultValue
  , validation: commaList
  , errorMessage: "Invalid format"
  , formatInput: trim
  }

lineageConfig :: String -> FieldConfig
lineageConfig defaultValue =
  { label: "Lineage"
  , placeholder: "Enter lineage (comma-separated)"
  , defaultValue
  , validation: commaList
  , errorMessage: "Invalid format"
  , formatInput: trim
  }

leaflyUrlConfig :: String -> FieldConfig
leaflyUrlConfig defaultValue =
  { label: "Leafly URL"
  , placeholder: "Enter Leafly URL"
  , defaultValue
  , validation: validUrl
  , errorMessage: "URL must be valid"
  , formatInput: trim
  }

imgConfig :: String -> FieldConfig
imgConfig defaultValue =
  { label: "Image URL"
  , placeholder: "Enter image URL"
  , defaultValue
  , validation: validUrl
  , errorMessage: "URL must be valid"
  , formatInput: trim
  }

categoryConfig
  :: { defaultValue :: String, forNewItem :: Boolean } -> DropdownConfig
categoryConfig { defaultValue, forNewItem } =
  { label: "Category"
  , options: map (\val -> { value: show val, label: show val })
      (getAllEnumValues :: Array ItemCategory)
  , defaultValue
  , emptyOption:
      if forNewItem then Just { value: "", label: "Select..." }
      else Nothing
  }

speciesConfig
  :: { defaultValue :: String, forNewItem :: Boolean } -> DropdownConfig
speciesConfig { defaultValue, forNewItem } =
  { label: "Species"
  , options: map (\val -> { value: show val, label: show val })
      (getAllEnumValues :: Array Species)
  , defaultValue
  , emptyOption:
      if forNewItem then Just { value: "", label: "Select..." }
      else Nothing
  }