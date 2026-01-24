{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Codegen.Schema
  ( -- * Schema Types
    DomainSchema(..)
  , RecordDef(..)
  , EnumDef(..)
  , FieldDef(..)
  , FieldType(..)
  , Validation(..)
  , TypeKind(..)
  
  -- * Smart Constructors
  , field
  , enum
  , record
  , newtypeOver
  
  -- * Field Modifiers
  , required
  , withValidations
  , withDbColumn
  , withDescription
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)

-- | Complete domain schema definition
data DomainSchema = DomainSchema
  { schemaModuleName :: Text       -- ^ e.g. "Types.Inventory"
  , schemaDbModuleName :: Text     -- ^ e.g. "DB.Inventory"
  , schemaApiModuleName :: Text    -- ^ e.g. "API.Inventory"
  , schemaEnums :: [EnumDef]
  , schemaRecords :: [RecordDef]
  } deriving (Show, Eq, Generic)

-- | Enum type definition
data EnumDef = EnumDef
  { enumName :: Text
  , enumDisplayName :: Text
  , enumVariants :: [Text]
  , enumDescription :: Maybe Text
  , enumDeriving :: [Text]
  } deriving (Show, Eq, Generic)

-- | Record type definition
data RecordDef = RecordDef
  { recordName :: Text
  , recordKind :: TypeKind
  , recordFields :: [FieldDef]
  , recordDescription :: Maybe Text
  , recordDeriving :: [Text]
  } deriving (Show, Eq, Generic)

-- | Whether a record is a regular data type or a newtype wrapper
data TypeKind
  = RecordType
  | NewtypeOver Text  -- ^ Wraps the given type
  deriving (Show, Eq, Generic)

-- | Field definition within a record
data FieldDef = FieldDef
  { fieldName :: Text
  , fieldType :: FieldType
  , fieldValidations :: [Validation]
  , fieldDbColumn :: Maybe Text      -- ^ Override column name in DB
  , fieldDescription :: Maybe Text
  } deriving (Show, Eq, Generic)

-- | Supported field types
data FieldType
  = FText
  | FInt
  | FInteger
  | FDouble
  | FBool
  | FUuid
  | FUtcTime
  | FMoney                    -- ^ Stored as Int (cents)
  | FVector FieldType         -- ^ Vector of items
  | FList FieldType           -- ^ List of items
  | FMaybe FieldType          -- ^ Optional field
  | FEnum Text                -- ^ Reference to enum type
  | FNested Text              -- ^ Reference to nested record
  | FCustom Text              -- ^ Custom Haskell type
  deriving (Show, Eq, Generic)

-- | Validation rules for fields
data Validation
  = Required
  | MaxLength Int
  | MinLength Int
  | MinValue Double
  | MaxValue Double
  | NonNegative
  | ValidUrl
  | ValidUuid
  | Pattern Text
  deriving (Show, Eq, Generic)

-- ============================================
-- Smart Constructors
-- ============================================

-- | Create a basic field
field :: Text -> FieldType -> FieldDef
field name typ = FieldDef
  { fieldName = name
  , fieldType = typ
  , fieldValidations = []
  , fieldDbColumn = Nothing
  , fieldDescription = Nothing
  }

-- | Create an enum definition
enum :: Text -> Text -> [Text] -> EnumDef
enum name displayName variants = EnumDef
  { enumName = name
  , enumDisplayName = displayName
  , enumVariants = variants
  , enumDescription = Nothing
  , enumDeriving = ["Show", "Eq", "Ord", "Generic", "Read"]
  }

-- | Create a record definition
record :: Text -> [FieldDef] -> RecordDef
record name fields = RecordDef
  { recordName = name
  , recordKind = RecordType
  , recordFields = fields
  , recordDescription = Nothing
  , recordDeriving = ["Show", "Generic"]
  }

-- | Create a newtype wrapper
newtypeOver :: Text -> Text -> RecordDef
newtypeOver name innerType = RecordDef
  { recordName = name
  , recordKind = NewtypeOver innerType
  , recordFields = []
  , recordDescription = Nothing
  , recordDeriving = ["Show", "Generic"]
  }

-- ============================================
-- Field Modifiers
-- ============================================

-- | Mark a field as required
required :: FieldDef -> FieldDef
required f = f { fieldValidations = Required : fieldValidations f }

-- | Add validations to a field
withValidations :: [Validation] -> FieldDef -> FieldDef
withValidations vs f = f { fieldValidations = fieldValidations f ++ vs }

-- | Set custom database column name
withDbColumn :: Text -> FieldDef -> FieldDef
withDbColumn col f = f { fieldDbColumn = Just col }

-- | Add description to a field
withDescription :: Text -> FieldDef -> FieldDef
withDescription desc f = f { fieldDescription = Just desc }