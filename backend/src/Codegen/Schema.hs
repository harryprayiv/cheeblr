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
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- | Top-level schema definition
data DomainSchema = DomainSchema
  { schemaModuleName :: Text           -- ^ e.g., "Types.Inventory"
  , schemaDbModuleName :: Text         -- ^ e.g., "DB.Database"  
  , schemaApiModuleName :: Text        -- ^ e.g., "API.Inventory"
  , schemaEnums :: [EnumDef]
  , schemaRecords :: [RecordDef]
  } deriving (Show, Eq, Generic)

-- | Enum type definition
data EnumDef = EnumDef
  { enumName :: Text
  , enumDisplayName :: Text            -- ^ For UI/config naming
  , enumVariants :: [Text]             -- ^ Non-empty list of constructors
  , enumDescription :: Maybe Text
  , enumDeriving :: [Text]             -- ^ Additional deriving clauses
  } deriving (Show, Eq, Generic)

-- | Record/newtype definition
data RecordDef = RecordDef
  { recordName :: Text
  , recordKind :: TypeKind
  , recordFields :: [FieldDef]
  , recordDescription :: Maybe Text
  , recordDeriving :: [Text]           -- ^ e.g., ["Generic", "Show"]
  } deriving (Show, Eq, Generic)

data TypeKind
  = RecordType                         -- ^ Regular record with fields
  | NewtypeOver Text                   -- ^ Newtype wrapper over another type
  deriving (Show, Eq, Generic)

-- | Field definition within a record
data FieldDef = FieldDef
  { fieldName :: Text                  -- ^ Haskell field name (e.g., "strain_lineage")
  , fieldType :: FieldType
  , fieldValidations :: [Validation]
  , fieldDbColumn :: Maybe Text        -- ^ DB column name if different from fieldName
  , fieldDescription :: Maybe Text
  } deriving (Show, Eq, Generic)

-- | Supported field types
data FieldType
  = FText                              -- ^ Text
  | FInt                               -- ^ Int
  | FInteger                           -- ^ Integer (arbitrary precision)
  | FDouble                            -- ^ Double
  | FBool                              -- ^ Bool
  | FUuid                              -- ^ UUID
  | FUtcTime                           -- ^ UTCTime
  | FMoney                             -- ^ Int (cents) - special handling for JSON
  | FVector FieldType                  -- ^ Vector a (maps to PGArray)
  | FList FieldType                    -- ^ [a]
  | FMaybe FieldType                   -- ^ Maybe a
  | FEnum Text                         -- ^ Reference to an enum type
  | FNested Text                       -- ^ Nested record type
  | FCustom Text                       -- ^ Custom type name (pass-through)
  deriving (Show, Eq, Generic)

-- | Validation rules (for documentation and potential runtime validation)
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

-- =============================================================================
-- Smart Constructors
-- =============================================================================

-- | Create a simple field
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