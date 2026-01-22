module Codegen.Schema where

import Prelude
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Maybe (Maybe)

-- | Core field types
data FieldType
  = FString
  | FInt
  | FNumber
  | FBool
  | FMoney          -- Stored as cents (Int), displayed as dollars
  | FPercentage     -- "XX.XX%" format
  | FUrl
  | FUuid
  | FDateTime
  | FEnum String    -- Reference an enum by name
  | FArray FieldType
  | FMaybe FieldType
  | FNested String  -- Reference another record by name

derive instance eqFieldType :: Eq FieldType

-- | Validation rules
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

-- | UI input type hints
data InputType
  = TextInput
  | TextArea { rows :: Int, cols :: Int }
  | NumberInput
  | Dropdown
  | PasswordInput
  | Hidden

derive instance eqInputType :: Eq InputType

-- | Field definition
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

-- | Enum definition
type EnumDef =
  { name :: String
  , variants :: NonEmptyArray String
  , description :: Maybe String
  }

-- | Record/newtype definition
data TypeKind = RecordType | NewtypeOver String

derive instance eqTypeKind :: Eq TypeKind

type RecordDef =
  { name :: String
  , kind :: TypeKind
  , fields :: Array FieldDef
  , description :: Maybe String
  }

-- | Complete domain schema
type DomainSchema =
  { moduleName :: String
  , configModuleName :: String
  , validationModuleName :: String
  , enums :: Array EnumDef
  , records :: Array RecordDef
  }