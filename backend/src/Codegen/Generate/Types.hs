{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}

module Codegen.Generate.Types
  ( generateTypesModule
  ) where

import Codegen.Schema
import Codegen.Generate.Common (GeneratedModule(..), moduleNameToPath)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (fromMaybe, mapMaybe)

generateTypesModule :: DomainSchema -> GeneratedModule
generateTypesModule schema = GeneratedModule
  { modulePath = moduleNameToPath (schemaModuleName schema <> ".Generated")
  , moduleContent = T.unlines $ filter (not . T.null)
      [ generatePragmas
      , ""
      , generateModuleDecl schema
      , ""
      , generateImports
      , ""
      , "-- ============================================"
      , "-- Enum Types"
      , "-- ============================================"
      , ""
      , T.intercalate "\n\n" $ map generateEnum (schemaEnums schema)
      , ""
      , "-- ============================================"
      , "-- Record Types"
      , "-- ============================================"
      , ""
      , T.intercalate "\n\n" $ map (generateRecord schema)
          (filter isRegularRecord $ schemaRecords schema)
      , ""
      , "-- ============================================"
      , "-- Newtype Wrappers"
      , "-- ============================================"
      , ""
      , T.intercalate "\n\n" $ map generateNewtype
          (filter isNewtype $ schemaRecords schema)
      , ""
      , "-- ============================================"
      , "-- Response Types"
      , "-- ============================================"
      , ""
      , generateInventoryResponse
      , ""
      , "-- ============================================"
      , "-- JSON Instances"
      , "-- ============================================"
      , ""
      , T.intercalate "\n" $ map generateAesonInstances (schemaEnums schema)
      , T.intercalate "\n" $ map (generateRecordAesonInstances schema)
          (filter isRegularRecord $ schemaRecords schema)
      , generateNewtypeAesonInstances
      , generateInventoryResponseAeson
      , ""
      , "-- ============================================"
      , "-- PostgreSQL Instances"
      , "-- ============================================"
      , ""
      , T.intercalate "\n\n" $ concatMap (generatePgInstances schema) (schemaRecords schema)
      ]
  }
  where
    isRegularRecord r = case recordKind r of
      RecordType -> recordName r /= "InventoryResponse"
      _ -> False

    isNewtype r = case recordKind r of
      NewtypeOver _ -> True
      _ -> False

generatePragmas :: Text
generatePragmas = T.unlines
  [ "{-# LANGUAGE DeriveAnyClass #-}"
  , "{-# LANGUAGE DeriveGeneric #-}"
  , "{-# LANGUAGE OverloadedStrings #-}"
  , "{-# LANGUAGE RecordWildCards #-}"
  ]

generateModuleDecl :: DomainSchema -> Text
generateModuleDecl schema = "module " <> schemaModuleName schema <> ".Generated where"

generateImports :: Text
generateImports = T.unlines
  [ "import Data.Aeson"
  , "    ( ToJSON(toJSON), FromJSON(parseJSON), object, KeyValue((.=)) )"
  , "import Data.Text (Text)"
  , "import qualified Data.Text as T"
  , "import Data.UUID (UUID)"
  , "import qualified Data.Vector as V"
  , "import Database.PostgreSQL.Simple.FromRow (FromRow(..), field)"
  , "import Database.PostgreSQL.Simple.ToField (ToField(..))"
  , "import Database.PostgreSQL.Simple.ToRow (ToRow(..))"
  , "import Database.PostgreSQL.Simple.Types (PGArray(..))"
  , "import GHC.Generics (Generic)"
  ]

generateEnum :: EnumDef -> Text
generateEnum EnumDef{..} = T.unlines $
  [ "data " <> enumName ]
  ++ zipWith mkVariant [0::Int ..] enumVariants
  ++ [ "  deriving (" <> T.intercalate ", " enumDeriving <> ")" ]
  where
    mkVariant 0 v = "  = " <> v
    mkVariant _ v = "  | " <> v

generateAesonInstances :: EnumDef -> Text
generateAesonInstances EnumDef{..} = T.unlines
  [ "instance ToJSON " <> enumName
  , "instance FromJSON " <> enumName
  ]

generateRecord :: DomainSchema -> RecordDef -> Text
generateRecord schema RecordDef{..} = T.unlines $
  [ "data " <> recordName <> " = " <> recordName ]
  ++ formatRecordFields schema recordFields
  ++ [ "  deriving (" <> T.intercalate ", " recordDeriving <> ")" ]

formatRecordFields :: DomainSchema -> [FieldDef] -> [Text]
formatRecordFields _ [] = ["  {}"]
formatRecordFields schema fields =
  zipWith (formatField schema) [0::Int ..] fields ++ ["  }"]
  where
    formatField s 0 f = "  { " <> fieldName f <> " :: " <> fieldTypeToHaskell s (fieldType f)
    formatField s _ f = "  , " <> fieldName f <> " :: " <> fieldTypeToHaskell s (fieldType f)

generateNewtype :: RecordDef -> Text
generateNewtype RecordDef{..} = case recordKind of
  NewtypeOver inner -> T.unlines
    [ "newtype " <> recordName <> " = " <> recordName
    , "  { items :: " <> inner
    , "  }"
    , "  deriving (" <> T.intercalate ", " recordDeriving <> ")"
    ]
  _ -> ""

generateInventoryResponse :: Text
generateInventoryResponse = T.unlines
  [ "data InventoryResponse"
  , "  = InventoryData Inventory"
  , "  | Message Text"
  , "  deriving (Show, Generic)"
  ]

generateRecordAesonInstances :: DomainSchema -> RecordDef -> Text
generateRecordAesonInstances _ RecordDef{..} = T.unlines
  [ "instance ToJSON " <> recordName
  , "instance FromJSON " <> recordName
  ]

generateNewtypeAesonInstances :: Text
generateNewtypeAesonInstances = T.unlines
  [ "instance ToJSON Inventory where"
  , "  toJSON (Inventory {items = items}) = toJSON items"
  , ""
  , "instance FromJSON Inventory where"
  , "  parseJSON v = Inventory <$> parseJSON v"
  ]

generateInventoryResponseAeson :: Text
generateInventoryResponseAeson = T.unlines
  [ "instance ToJSON InventoryResponse where"
  , "  toJSON (InventoryData inv) ="
  , "    object"
  , "      [ \"type\" .= T.pack \"data\""
  , "      , \"value\" .= toJSON inv"
  , "      ]"
  , "  toJSON (Message msg) ="
  , "    object"
  , "      [ \"type\" .= T.pack \"message\""
  , "      , \"value\" .= msg"
  , "      ]"
  , ""
  , "instance FromJSON InventoryResponse"
  ]

generatePgInstances :: DomainSchema -> RecordDef -> [Text]
generatePgInstances schema rec@RecordDef{..} = case recordKind of
  NewtypeOver _ -> []
  RecordType
    | recordName == "InventoryResponse" -> []
    | otherwise ->
        [ generateToRowInstance schema rec
        , generateFromRowInstance schema rec
        ]

generateToRowInstance :: DomainSchema -> RecordDef -> Text
generateToRowInstance schema RecordDef{..} = T.unlines
  [ "instance ToRow " <> recordName <> " where"
  , "  toRow " <> recordName <> " {..} ="
  , "    [ " <> T.intercalate "\n    , " (map (toRowField schema) simpleFields) <> "\n    ]"
  ]
  where
    simpleFields = filter (not . isNestedField) recordFields
    isNestedField f = case fieldType f of
      FNested _ -> True
      _ -> False

toRowField :: DomainSchema -> FieldDef -> Text
toRowField _ FieldDef{..} = case fieldType of
  FEnum _ -> "toField (show " <> fieldName <> ")"
  FVector _ -> "toField (PGArray $ V.toList " <> fieldName <> ")"
  _ -> "toField " <> fieldName

generateFromRowInstance :: DomainSchema -> RecordDef -> Text
generateFromRowInstance schema rec@RecordDef{..}
  | hasNestedRecord rec = generateFromRowWithNested schema rec
  | otherwise = generateSimpleFromRow schema rec

hasNestedRecord :: RecordDef -> Bool
hasNestedRecord RecordDef{..} = any isNested recordFields
  where
    isNested f = case fieldType f of
      FNested _ -> True
      _ -> False

generateSimpleFromRow :: DomainSchema -> RecordDef -> Text
generateSimpleFromRow schema RecordDef{..} = T.unlines $
  [ "instance FromRow " <> recordName <> " where"
  , "  fromRow ="
  , "    " <> recordName
  ] ++ zipWith (fromRowField schema) [0::Int ..] recordFields

fromRowField :: DomainSchema -> Int -> FieldDef -> Text
fromRowField _ idx FieldDef{..} =
  let prefix = if idx == 0 then "      <$> " else "      <*> "
      parser = case fieldType of
        FEnum _ -> "(read <$> field)"
        FVector _ -> "(V.fromList . fromPGArray <$> field)"
        _ -> "field"
  in prefix <> parser

generateFromRowWithNested :: DomainSchema -> RecordDef -> Text
generateFromRowWithNested schema RecordDef{..} = T.unlines $
  [ "instance FromRow " <> recordName <> " where"
  , "  fromRow ="
  , "    " <> recordName
  ] ++ concatMap (fromRowFieldOrNested schema) (zip [0::Int ..] recordFields)

fromRowFieldOrNested :: DomainSchema -> (Int, FieldDef) -> [Text]
fromRowFieldOrNested schema (idx, f@FieldDef{..}) = case fieldType of
  FNested nestedName ->
    let prefix = if idx == 0 then "      <$> " else "      <*> "
    in case findRecord schema nestedName of
      Nothing -> [prefix <> "field"]
      Just nested ->
        [ prefix <> "( " <> nestedName ]
        ++ map ("          " <>) (nestedFieldParsers nested)
        ++ [ "          )" ]
  _ -> [fromRowField schema idx f]

nestedFieldParsers :: RecordDef -> [Text]
nestedFieldParsers RecordDef{..} =
  zipWith mkParser [0::Int ..] recordFields
  where
    mkParser 0 f = "<$> " <> fieldParser f
    mkParser _ f = "<*> " <> fieldParser f

    fieldParser FieldDef{..} = case fieldType of
      FEnum _ -> "(read <$> field)"
      FVector _ -> "(V.fromList . fromPGArray <$> field)"
      _ -> "field"

fieldTypeToHaskell :: DomainSchema -> FieldType -> Text
fieldTypeToHaskell schema = \case
  FText -> "Text"
  FInt -> "Int"
  FInteger -> "Integer"
  FDouble -> "Double"
  FBool -> "Bool"
  FUuid -> "UUID"
  FUtcTime -> "UTCTime"
  FMoney -> "Int"
  FVector inner -> "V.Vector " <> fieldTypeToHaskell schema inner
  FList inner -> "[" <> fieldTypeToHaskell schema inner <> "]"
  FMaybe inner -> "Maybe " <> wrapIfNeeded (fieldTypeToHaskell schema inner)
  FEnum name -> name
  FNested name -> name
  FCustom name -> name
  where
    wrapIfNeeded t
      | T.any (== ' ') t = "(" <> t <> ")"
      | otherwise = t

findRecord :: DomainSchema -> Text -> Maybe RecordDef
findRecord schema name =
  case filter (\r -> recordName r == name) (schemaRecords schema) of
    [r] -> Just r
    _ -> Nothing