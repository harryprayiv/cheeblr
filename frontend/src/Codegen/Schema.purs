module Codegen.Schema where

import Prelude
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Maybe (Maybe)

data FieldType
  = FString
  | FInt
  | FNumber
  | FBool
  | FMoney
  | FPercentage
  | FUrl
  | FUuid
  | FDateTime
  | FEnum String
  | FArray FieldType
  | FMaybe FieldType
  | FNested String

derive instance eqFieldType :: Eq FieldType

data Validation
  = Required
  | MaxLength Int
  | MinLength Int
  | MinValue Number
  | MaxValue Number
  | NonNegative
  | Alphanumeric
  | ExtendedAlphanumeric
  | CommaList
  | Pattern String
  | ValidUrl
  | ValidUuid
  | ValidMeasurementUnit

derive instance eqValidation :: Eq Validation

data InputType
  = TextInput
  | TextArea { rows :: Int, cols :: Int }
  | NumberInput
  | Dropdown
  | PasswordInput
  | Hidden

derive instance eqInputType :: Eq InputType

type FieldDef =
  { name :: String
  , fieldType :: FieldType
  , validations :: Array Validation
  , inputType :: InputType
  , ui ::
      { label :: String
      , placeholder :: String
      , errorMessage :: String
      }
  }

type EnumDef =
  { name :: String
  , displayName :: String  -- Used for config naming and UI labels (e.g., "Category" for ItemCategory)
  , variants :: NonEmptyArray String
  , description :: Maybe String
  }

data TypeKind = RecordType | NewtypeOver String

derive instance eqTypeKind :: Eq TypeKind

type RecordDef =
  { name :: String
  , kind :: TypeKind
  , fields :: Array FieldDef
  , description :: Maybe String
  }

type DomainSchema =
  { moduleName :: String
  , configModuleName :: String
  , validationModuleName :: String
  , enums :: Array EnumDef
  , records :: Array RecordDef
  }