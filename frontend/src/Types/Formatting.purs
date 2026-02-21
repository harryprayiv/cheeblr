module Types.Formatting where

import Prelude

import Data.Either (Either(..))
import Data.Generic.Rep (class Generic)
import Data.Int (fromString)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Number (fromString) as Number
import Data.String (trim)
import Effect (Effect)
import Type.Proxy (Proxy(..))
import Types.Inventory (ItemCategory(..), Species(..))
import Types.UUID (UUID, parseUUID)
import Yoga.JSON (class WriteForeign, writeImpl)

type HTMLFormField (r :: Row Type) =
  ( __tag :: Proxy "HTMLFormField"
  , value :: String
  , validation :: ValidationRule
  , onUpdate :: String -> Effect Unit
  | r
  )

type TextAreaConfig =
  { label :: String
  , placeholder :: String
  , defaultValue :: String
  , rows :: String
  , cols :: String
  , errorMessage :: String
  }

type FieldConfig = Record (FieldConfigRow ())

newtype FieldConfigRecord r = FieldConfigRecord (Record (FieldConfigRow r))

type FieldConfigRow r =
  ( label :: String
  , placeholder :: String
  , defaultValue :: String
  , validation :: ValidationRule
  , errorMessage :: String
  , formatInput :: String -> String
  | r
  )

type DropdownConfig =
  { label :: String
  , options :: Array { value :: String, label :: String }
  , defaultValue :: String
  , emptyOption :: Maybe { value :: String, label :: String }
  }

type TextFieldConfig r =
  ( maxLength :: Int
  | FieldConfigRow r
  )

type NumberFieldConfig r =
  ( min :: Number
  , max :: Number
  | FieldConfigRow r
  )

toFieldConfigRecord
  :: forall r. Record (FieldConfigRow r) -> FieldConfigRecord r
toFieldConfigRecord = FieldConfigRecord

fromFieldConfigRecord
  :: forall r. FieldConfigRecord r -> Record (FieldConfigRow r)
fromFieldConfigRecord (FieldConfigRecord record) = record

data ValidationResult a
  = ValidationSuccess a
  | ValidationError String

newtype ValidationRule = ValidationRule (String -> Boolean)

newtype Validated a = Validated a

derive instance genericValidated :: Generic (Validated a) _
derive instance functorValidated :: Functor Validated

class FormValue a where
  fromFormValue :: String -> ValidationResult a

class FieldValidator a where
  validateField :: String -> Either String a
  validationError :: Proxy a -> String

type ValidationPreset =
  { validation :: ValidationRule
  , errorMessage :: String
  , formatInput :: String -> String
  }

instance writeForeignFieldConfigRecord :: WriteForeign (FieldConfigRecord r) where
  writeImpl (FieldConfigRecord config) = writeImpl
    { label: config.label
    , placeholder: config.placeholder
    , validation: config.validation
    , errorMessage: config.errorMessage
    , formatInput: "<format function>"
    }

instance writeForeignValidationRule :: WriteForeign ValidationRule where
  writeImpl _ = writeImpl "<validation function>"

instance showValidationRule :: Show ValidationRule where
  show _ = "<validation function>"

instance formValueString :: FormValue String where
  fromFormValue = ValidationSuccess <<< trim

instance formValueNumber :: FormValue Number where
  fromFormValue str = case Number.fromString (trim str) of
    Just n -> ValidationSuccess n
    Nothing -> ValidationError "Invalid number format"

instance formValueInt :: FormValue Int where
  fromFormValue str = case Int.fromString (trim str) of
    Just n -> ValidationSuccess n
    Nothing -> ValidationError "Invalid integer format"

instance formValueItemCategory :: FormValue ItemCategory where
  fromFormValue str = case str of
    "Flower" -> ValidationSuccess Flower
    "PreRolls" -> ValidationSuccess PreRolls
    "Vaporizers" -> ValidationSuccess Vaporizers
    "Edibles" -> ValidationSuccess Edibles
    "Drinks" -> ValidationSuccess Drinks
    "Concentrates" -> ValidationSuccess Concentrates
    "Topicals" -> ValidationSuccess Topicals
    "Tinctures" -> ValidationSuccess Tinctures
    "Accessories" -> ValidationSuccess Accessories
    _ -> ValidationError "Invalid category value"

instance formValueSpecies :: FormValue Species where
  fromFormValue str = case str of
    "Indica" -> ValidationSuccess Indica
    "IndicaDominantHybrid" -> ValidationSuccess IndicaDominantHybrid
    "Hybrid" -> ValidationSuccess Hybrid
    "SativaDominantHybrid" -> ValidationSuccess SativaDominantHybrid
    "Sativa" -> ValidationSuccess Sativa
    _ -> ValidationError "Invalid species value"

instance formValueUUID :: FormValue UUID where
  fromFormValue str = case parseUUID (trim str) of
    Just uuid -> ValidationSuccess uuid
    Nothing -> ValidationError "Invalid UUID format"

instance formValueValidated :: (FieldValidator a) => FormValue (Validated a) where
  fromFormValue str = case validateField str of
    Right value -> ValidationSuccess value
    Left err -> ValidationError err

instance fieldValidatorValidated ::
  ( FieldValidator a
  ) =>
  FieldValidator (Validated a) where
  validateField str = do
    result <- validateField str
    pure $ Validated result
  validationError _ = "Validated: " <> validationError (Proxy :: Proxy a)

instance fieldValidatorString :: FieldValidator String where
  validateField str = Right (trim str)
  validationError _ = "Invalid string format"

instance fieldValidatorNumber :: FieldValidator Number where
  validateField str = case Number.fromString (trim str) of
    Just n ->
      if n >= 0.0 then Right n
      else Left "Must be a positive number"
    Nothing -> Left "Must be a valid number"
  validationError _ = "Must be a valid number"

instance fieldValidatorInt :: FieldValidator Int where
  validateField str = case fromString (trim str) of
    Just n -> Right n
    Nothing -> Left "Must be a valid integer"
  validationError _ = "Must be a valid integer"

instance fieldValidatorUUID :: FieldValidator UUID where
  validateField str = case parseUUID (trim str) of
    Just uuid -> Right uuid
    Nothing -> Left "Must be a valid UUID"
  validationError _ = "Invalid UUID format"

instance fieldValidatorItemCategory :: FieldValidator ItemCategory where
  validateField str = case fromFormValue str of
    ValidationSuccess cat -> Right cat
    ValidationError err -> Left err
  validationError _ = "Must be a valid category"

instance fieldValidatorSpecies :: FieldValidator Species where
  validateField str = case fromFormValue str of
    ValidationSuccess species -> Right species
    ValidationError err -> Left err
  validationError _ = "Must be a valid species"