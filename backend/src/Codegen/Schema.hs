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

  -- * Module Name Helpers
  , generatedTypesModule
  , generatedDbModule
  , generatedApiModule
  , generatedServerModule
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)

data DomainSchema = DomainSchema
  { schemaName :: Text
    -- ^ The domain name (e.g., "Inventory")
  , schemaEnums :: [EnumDef]
    -- ^ Enum type definitions
  , schemaRecords :: [RecordDef]
    -- ^ Record type definitions
  } deriving (Show, Eq, Generic)

-- | Get the generated types module name (e.g., "Generated.Types.Inventory")
generatedTypesModule :: DomainSchema -> Text
generatedTypesModule schema = "Generated.Types." <> schemaName schema

-- | Get the generated DB module name (e.g., "Generated.DB.Inventory")
generatedDbModule :: DomainSchema -> Text
generatedDbModule schema = "Generated.DB." <> schemaName schema

-- | Get the generated API module name (e.g., "Generated.API.Inventory")
generatedApiModule :: DomainSchema -> Text
generatedApiModule schema = "Generated.API." <> schemaName schema

-- | Get the generated Server module name (e.g., "Generated.Server.Inventory")
generatedServerModule :: DomainSchema -> Text
generatedServerModule schema = "Generated.Server." <> schemaName schema

data EnumDef = EnumDef
  { enumName :: Text
  , enumDisplayName :: Text
  , enumVariants :: [Text]
  , enumDescription :: Maybe Text
  , enumDeriving :: [Text]
  } deriving (Show, Eq, Generic)

data RecordDef = RecordDef
  { recordName :: Text
  , recordKind :: TypeKind
  , recordFields :: [FieldDef]
  , recordDescription :: Maybe Text
  , recordDeriving :: [Text]
  } deriving (Show, Eq, Generic)

data TypeKind
  = RecordType
  | NewtypeOver Text
  deriving (Show, Eq, Generic)

data FieldDef = FieldDef
  { fieldName :: Text
  , fieldType :: FieldType
  , fieldValidations :: [Validation]
  , fieldDbColumn :: Maybe Text
  , fieldDescription :: Maybe Text
  } deriving (Show, Eq, Generic)

data FieldType
  = FText
  | FInt
  | FInteger
  | FDouble
  | FBool
  | FUuid
  | FUtcTime
  | FMoney
  | FVector FieldType
  | FList FieldType
  | FMaybe FieldType
  | FEnum Text
  | FNested Text
  | FCustom Text
  deriving (Show, Eq, Generic)

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

-- | Mark a field as required
required :: FieldDef -> FieldDef
required f = f { fieldValidations = Required : fieldValidations f }

-- | Add validations to a field
withValidations :: [Validation] -> FieldDef -> FieldDef
withValidations vs f = f { fieldValidations = fieldValidations f ++ vs }

-- | Set database column name
withDbColumn :: Text -> FieldDef -> FieldDef
withDbColumn col f = f { fieldDbColumn = Just col }

-- | Add description to a field
withDescription :: Text -> FieldDef -> FieldDef
withDescription desc f = f { fieldDescription = Just desc }