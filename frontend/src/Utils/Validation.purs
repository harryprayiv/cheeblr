module Utils.Validation where

import Prelude

import Data.Array (all, any)
import Data.Either (Either(..))
import Data.Int (fromString)
import Data.Maybe (Maybe(..))
import Data.Number (fromString) as Number
import Data.String (length, toLower, trim) as String
import Data.String.Regex (Regex, regex, test)
import Data.String.Regex.Flags (RegexFlags, noFlags)
import Data.Validation.Semigroup (V, invalid)
import Partial.Unsafe (unsafeCrashWith)
import Types.Formatting (ValidationRule(..))
import Types.UUID (parseUUID)

mkValidationRule :: (String -> Boolean) -> ValidationRule
mkValidationRule = ValidationRule

runValidation :: ValidationRule -> String -> Boolean
runValidation (ValidationRule f) = f

nonEmpty :: ValidationRule
nonEmpty = ValidationRule \str -> String.trim str /= ""

alphanumeric :: ValidationRule
alphanumeric = ValidationRule \str -> case regex "^[A-Za-z0-9-\\s]+$" noFlags of
  Left _ -> false
  Right validRegex -> test validRegex str

extendedAlphanumeric :: ValidationRule
extendedAlphanumeric = ValidationRule \str ->
  case regex "^[A-Za-z0-9\\s\\-_&+',\\.\\(\\)]+$" noFlags of
    Left _ -> false
    Right validRegex -> test validRegex str

percentage :: ValidationRule
percentage = ValidationRule \str ->
  case regex "^\\d{1,3}(\\.\\d{1,2})?%$" noFlags of
    Left _ -> false
    Right validRegex -> test validRegex str

dollarAmount :: ValidationRule
dollarAmount = ValidationRule \str -> case Number.fromString str of
  Just n -> n >= 0.0
  Nothing -> false

validMeasurementUnit :: ValidationRule
validMeasurementUnit = ValidationRule \str ->
  let
    units =
      [ "g"
      , "mg"
      , "kg"
      , "oz"
      , "lb"
      , "ml"
      , "l"
      , "ea"
      , "unit"
      , "units"
      , "pack"
      , "packs"
      , "eighth"
      , "quarter"
      , "half"
      , "1/8"
      , "1/4"
      , "1/2"
      ]
    lowercaseStr = String.trim (str # String.toLower)
  in
    any (\unit -> unit == lowercaseStr) units

validUrl :: ValidationRule
validUrl = ValidationRule \str ->
  case
    regex
      "^(https?:\\/\\/)?(www\\.)?[a-zA-Z0-9][a-zA-Z0-9-]*(\\.[a-zA-Z0-9][a-zA-Z0-9-]*)+(\\/[\\w\\-\\.~:\\/?#[\\]@!$&'()*+,;=]*)*$"
      noFlags
    of
    Left _ -> false
    Right validRegex -> test validRegex str

positiveInteger :: ValidationRule
positiveInteger = ValidationRule \str -> case fromString str of
  Just n -> n > 0
  Nothing -> false

nonNegativeInteger :: ValidationRule
nonNegativeInteger = ValidationRule \str -> case fromString str of
  Just n -> n >= 0
  Nothing -> false

fraction :: ValidationRule
fraction = ValidationRule \str -> case regex "^\\d+\\/\\d+$" noFlags of
  Left _ -> false
  Right validRegex -> test validRegex str

commaList :: ValidationRule
commaList = ValidationRule \str -> case regex "^[^,]*(,[^,]*)*$" noFlags of
  Left _ -> false
  Right validRegex -> test validRegex str

validUUID :: ValidationRule
validUUID = ValidationRule \str -> case parseUUID (String.trim str) of
  Just _ -> true
  Nothing -> false

maxLength :: Int -> ValidationRule
maxLength n = ValidationRule \str -> String.length str <= n

allOf :: Array ValidationRule -> ValidationRule
allOf rules = ValidationRule \str ->
  all (\(ValidationRule rule) -> rule str) rules

anyOf :: Array ValidationRule -> ValidationRule
anyOf rules = ValidationRule \str ->
  any (\(ValidationRule rule) -> rule str) rules

requiredText
  :: { validation :: ValidationRule
     , errorMessage :: String
     , formatInput :: String -> String
     }
requiredText =
  { validation: allOf [ nonEmpty, alphanumeric ]
  , errorMessage: "Required, text only"
  , formatInput: String.trim
  }

requiredTextWithLimit
  :: Int
  -> { validation :: ValidationRule
     , errorMessage :: String
     , formatInput :: String -> String
     }
requiredTextWithLimit limit =
  { validation: allOf [ nonEmpty, extendedAlphanumeric, maxLength limit ]
  , errorMessage: "Required, text only (max " <> show limit <> " chars)"
  , formatInput: String.trim
  }

percentageField
  :: { validation :: ValidationRule
     , errorMessage :: String
     , formatInput :: String -> String
     }
percentageField =
  { validation: percentage
  , errorMessage: "Required format: XX.XX%"
  , formatInput: String.trim
  }

moneyField
  :: { validation :: ValidationRule
     , errorMessage :: String
     , formatInput :: String -> String
     }
moneyField =
  { validation: allOf [ nonEmpty, dollarAmount ]
  , errorMessage: "Required, valid dollar amount"
  , formatInput: identity
  }

urlField
  :: { validation :: ValidationRule
     , errorMessage :: String
     , formatInput :: String -> String
     }
urlField =
  { validation: allOf [ nonEmpty, validUrl ]
  , errorMessage: "Required, valid URL"
  , formatInput: String.trim
  }

quantityField
  :: { validation :: ValidationRule
     , errorMessage :: String
     , formatInput :: String -> String
     }
quantityField =
  { validation: allOf [ nonEmpty, nonNegativeInteger ]
  , errorMessage: "Required, non-negative whole number"
  , formatInput: String.trim
  }

commaListField
  :: { validation :: ValidationRule
     , errorMessage :: String
     , formatInput :: String -> String
     }
commaListField =
  { validation: commaList
  , errorMessage: "Must be a comma-separated list"
  , formatInput: String.trim
  }

multilineText
  :: { validation :: ValidationRule
     , errorMessage :: String
     , formatInput :: String -> String
     }
multilineText =
  { validation: nonEmpty
  , errorMessage: "Required"
  , formatInput: identity
  }

validateString :: String -> String -> V (Array String) String
validateString fieldName str =
  if String.trim str == "" then invalid [ fieldName <> " is required" ]
  else pure str

validatePercentage :: String -> String -> V (Array String) String
validatePercentage fieldName str =
  if String.trim str == "" then invalid [ fieldName <> " is required" ]
  else if not (test (unsafeRegex "^\\d{1,3}(\\.\\d{1,2})?%$" noFlags) str) then
    invalid [ fieldName <> " must be in the format XX.XX%" ]
  else pure str

validateNumber :: String -> String -> V (Array String) Number
validateNumber fieldName str =
  case Number.fromString (String.trim str) of
    Just n | n >= 0.0 -> pure n
    _ -> invalid [ fieldName <> " must be a non-negative number" ]

validateInt :: String -> String -> V (Array String) Int
validateInt fieldName str =
  case fromString (String.trim str) of
    Just n | n >= 0 -> pure n
    _ -> invalid [ fieldName <> " must be a non-negative integer" ]

validateUrl :: String -> String -> V (Array String) String
validateUrl fieldName str =
  if String.trim str == "" then invalid [ fieldName <> " is required" ]
  else if
    not
      ( test
          ( unsafeRegex
              "^(https?:\\/\\/)?(www\\.)?[a-zA-Z0-9][a-zA-Z0-9-]*(\\.[a-zA-Z0-9][a-zA-Z0-9-]*)+(\\/[\\w\\-\\.~:\\/?#[\\]@!$&'()*+,;=]*)*$"
              noFlags
          )
          str
      ) then invalid [ fieldName <> " must be a valid URL" ]
  else pure str

unsafeRegex :: String -> RegexFlags -> Regex
unsafeRegex pattern flags =
  case regex pattern flags of
    Left _ -> unsafeCrashWith $ "Invalid regex pattern: " <> pattern
    Right r -> r