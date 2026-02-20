module Cheeblr.Core.Validation where

import Prelude

import Cheeblr.Core.Domain (categoryRegistry, speciesRegistry)
import Cheeblr.Core.Product (Product(..))
import Cheeblr.Core.Tag (Registry, memberStr)
import Cheeblr.Core.Tag as Tag
import Data.Array (all, any)
import Data.Array as Data.Array
import Data.Either (Either(..))
import Data.Finance.Money (Discrete(..))
import Data.Int (floor, fromString) as Int
import Data.Maybe (Maybe(..))
import Data.Number (fromString) as Number
import Data.String (Pattern(..), joinWith, length, split, toLower, trim)
import Data.String.Regex (Regex, regex, test)
import Data.String.Regex.Flags (RegexFlags, noFlags)
import Data.Validation.Semigroup (V, invalid, toEither, andThen)
import Partial.Unsafe (unsafeCrashWith)
import Types.UUID (UUID, parseUUID)

----------------------------------------------------------------------
-- Validation Rule (kept compatible with existing code)
----------------------------------------------------------------------

newtype ValidationRule = ValidationRule (String -> Boolean)

runValidation :: ValidationRule -> String -> Boolean
runValidation (ValidationRule f) = f

instance Show ValidationRule where
  show _ = "<ValidationRule>"

----------------------------------------------------------------------
-- Combinators
----------------------------------------------------------------------

-- | Combine rules: all must pass.
allOf :: Array ValidationRule -> ValidationRule
allOf rules = ValidationRule \str ->
  all (\(ValidationRule f) -> f str) rules

-- | Combine rules: at least one must pass.
anyOf :: Array ValidationRule -> ValidationRule
anyOf rules = ValidationRule \str ->
  any (\(ValidationRule f) -> f str) rules

-- | Always passes.
alwaysValid :: ValidationRule
alwaysValid = ValidationRule \_ -> true

-- | Non-empty after trimming.
nonEmpty :: ValidationRule
nonEmpty = ValidationRule \str -> trim str /= ""

-- | Alphanumeric plus spaces and hyphens.
alphanumeric :: ValidationRule
alphanumeric = ValidationRule \str ->
  testPattern "^[A-Za-z0-9-\\s]+$" str

-- | Extended alphanumeric: includes common product-name punctuation.
extendedAlphanumeric :: ValidationRule
extendedAlphanumeric = ValidationRule \str ->
  testPattern "^[A-Za-z0-9\\s\\-_&+',\\.\\(\\)]+$" str

-- | Percentage format: "12.34%"
percentage :: ValidationRule
percentage = ValidationRule \str ->
  testPattern "^\\d{1,3}(\\.\\d{1,2})?%$" str

-- | Non-negative dollar amount.
dollarAmount :: ValidationRule
dollarAmount = ValidationRule \str ->
  case Number.fromString str of
    Just n -> n >= 0.0
    Nothing -> false

-- | Non-negative integer.
nonNegativeInteger :: ValidationRule
nonNegativeInteger = ValidationRule \str ->
  case Int.fromString str of
    Just n -> n >= 0
    Nothing -> false

-- | Positive integer.
positiveInteger :: ValidationRule
positiveInteger = ValidationRule \str ->
  case Int.fromString str of
    Just n -> n > 0
    Nothing -> false

-- | Fraction format: "1/4"
fraction :: ValidationRule
fraction = ValidationRule \str ->
  testPattern "^\\d+\\/\\d+$" str

-- | Comma-separated list.
commaList :: ValidationRule
commaList = ValidationRule \str ->
  testPattern "^[^,]*(,[^,]*)*$" str

-- | Valid UUID format.
validUUID :: ValidationRule
validUUID = ValidationRule \str ->
  case parseUUID (trim str) of
    Just _ -> true
    Nothing -> false

-- | Maximum string length.
maxLength :: Int -> ValidationRule
maxLength n = ValidationRule \str -> length str <= n

-- | Valid URL.
validUrl :: ValidationRule
validUrl = ValidationRule \str ->
  testPattern
    "^(https?:\\/\\/)?(www\\.)?[a-zA-Z0-9][a-zA-Z0-9-]*(\\.[a-zA-Z0-9][a-zA-Z0-9-]*)+(\\/[\\w\\-\\.~:\\/?#[\\]@!$&'()*+,;=]*)*$"
    str

-- | Value must be a member of the given registry.
inRegistry :: forall k. Registry k -> ValidationRule
inRegistry reg = ValidationRule \str -> memberStr reg str

-- | Measurement unit validation (uses registry).
validMeasurementUnit :: ValidationRule
validMeasurementUnit = ValidationRule \str ->
  let low = toLower (trim str) in
  any (\unit -> unit == low) knownUnits
  where
  knownUnits =
    [ "g", "mg", "kg", "oz", "lb", "ml", "l"
    , "ea", "unit", "units", "pack", "packs"
    , "eighth", "quarter", "half", "1/8", "1/4", "1/2"
    ]

----------------------------------------------------------------------
-- Preset bundles (for form field configs)
----------------------------------------------------------------------

type ValidationPreset =
  { validation :: ValidationRule
  , errorMessage :: String
  , formatInput :: String -> String
  }

requiredText :: ValidationPreset
requiredText =
  { validation: allOf [ nonEmpty, alphanumeric ]
  , errorMessage: "Required, text only"
  , formatInput: trim
  }

requiredExtended :: Int -> ValidationPreset
requiredExtended limit =
  { validation: allOf [ nonEmpty, extendedAlphanumeric, maxLength limit ]
  , errorMessage: "Required, max " <> show limit <> " characters"
  , formatInput: trim
  }

percentagePreset :: ValidationPreset
percentagePreset =
  { validation: percentage
  , errorMessage: "Format: XX.XX%"
  , formatInput: trim
  }

moneyPreset :: ValidationPreset
moneyPreset =
  { validation: allOf [ nonEmpty, dollarAmount ]
  , errorMessage: "Valid dollar amount required"
  , formatInput: identity
  }

urlPreset :: ValidationPreset
urlPreset =
  { validation: allOf [ nonEmpty, validUrl ]
  , errorMessage: "Valid URL required"
  , formatInput: trim
  }

----------------------------------------------------------------------
-- Product form validation (V-based accumulating errors)
----------------------------------------------------------------------

-- | Raw form input — all strings, mirrors what the form produces.
type ProductFormInput =
  { sort :: String
  , sku :: String
  , brand :: String
  , name :: String
  , price :: String
  , measureUnit :: String
  , perPackage :: String
  , quantity :: String
  , category :: String
  , subcategory :: String
  , description :: String
  , tags :: String
  , effects :: String
  , meta ::
      { thc :: String
      , cbg :: String
      , strain :: String
      , creator :: String
      , species :: String
      , dominantTerpene :: String
      , terpenes :: String
      , lineage :: String
      , leaflyUrl :: String
      , img :: String
      }
  }

validateProduct :: ProductFormInput -> Either String Product
validateProduct input =
  case toEither result of
    Left errors -> Left (joinWith ", " errors)
    Right product -> Right product
  where
  result =
    vUUID "SKU" input.sku `andThen` \sku ->
    vString "Name" input.name `andThen` \name ->
    vString "Brand" input.brand `andThen` \brand ->
    vNumber "Price" input.price `andThen` \priceValue ->
    vInt "Quantity" input.quantity `andThen` \quantity ->
    vString "Measure Unit" input.measureUnit `andThen` \measureUnit ->
    vString "Per Package" input.perPackage `andThen` \perPackage ->
    vTag "Category" categoryRegistry input.category `andThen` \category ->
    vString "Subcategory" input.subcategory `andThen` \subcategory ->
    vInt "Sort" input.sort `andThen` \sort ->
    validateMeta input.meta `andThen` \meta ->
      let priceCents = Int.floor (priceValue * 100.0) in
      pure $ Product
        { sort
        , sku
        , brand
        , name
        , price: Discrete priceCents
        , measureUnit
        , perPackage
        , quantity
        , category
        , subcategory
        , description: input.description
        , tags: parseCommaList input.tags
        , effects: parseCommaList input.effects
        , meta
        }

  validateMeta m =
    vPercentage "THC" m.thc `andThen` \thc ->
    vPercentage "CBG" m.cbg `andThen` \cbg ->
    vString "Strain" m.strain `andThen` \strain ->
    vString "Creator" m.creator `andThen` \creator ->
    vTag "Species" speciesRegistry m.species `andThen` \species ->
    vString "Dominant Terpene" m.dominantTerpene `andThen` \dominantTerpene ->
    vUrl "Leafly URL" m.leaflyUrl `andThen` \leaflyUrl ->
    vUrl "Image URL" m.img `andThen` \img ->
      pure
        { thc, cbg, strain, creator, species, dominantTerpene
        , terpenes: parseCommaList m.terpenes
        , lineage: parseCommaList m.lineage
        , leaflyUrl, img
        }

----------------------------------------------------------------------
-- Validation helpers (V-based)
----------------------------------------------------------------------

vString :: String -> String -> V (Array String) String
vString fieldName str =
  if trim str == "" then invalid [ fieldName <> " is required" ]
  else pure str

vInt :: String -> String -> V (Array String) Int
vInt fieldName str =
  case Int.fromString (trim str) of
    Just n | n >= 0 -> pure n
    _ -> invalid [ fieldName <> " must be a non-negative integer" ]

vNumber :: String -> String -> V (Array String) Number
vNumber fieldName str =
  case Number.fromString (trim str) of
    Just n | n >= 0.0 -> pure n
    _ -> invalid [ fieldName <> " must be a non-negative number" ]

vUUID :: String -> String -> V (Array String) UUID
vUUID fieldName str =
  case parseUUID (trim str) of
    Just uuid -> pure uuid
    Nothing -> invalid [ fieldName <> " must be a valid UUID" ]

vPercentage :: String -> String -> V (Array String) String
vPercentage fieldName str =
  if trim str == "" then invalid [ fieldName <> " is required" ]
  else if not (testPattern "^\\d{1,3}(\\.\\d{1,2})?%$" str) then
    invalid [ fieldName <> " must be in format XX.XX%" ]
  else pure str

vUrl :: String -> String -> V (Array String) String
vUrl fieldName str =
  if trim str == "" then invalid [ fieldName <> " is required" ]
  else if not (runValidation validUrl str) then
    invalid [ fieldName <> " must be a valid URL" ]
  else pure str

vTag :: forall k. String -> Registry k -> String -> V (Array String) (Tag.Tag k)
vTag fieldName reg str =
  case Tag.mkTag reg str of
    Just tag -> pure tag
    Nothing -> invalid [ fieldName <> " has invalid value: " <> str ]

----------------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------------

parseCommaList :: String -> Array String
parseCommaList str =
  if str == "" then []
  else
    str
      # split (Pattern ",")
      # map trim
      # Data.Array.filter (_ /= "")

testPattern :: String -> String -> Boolean
testPattern pattern str =
  case regex pattern noFlags of
    Left _ -> false
    Right r -> test r str

unsafeRegex :: String -> RegexFlags -> Regex
unsafeRegex pattern flags =
  case regex pattern flags of
    Left _ -> unsafeCrashWith $ "Invalid regex: " <> pattern
    Right r -> r