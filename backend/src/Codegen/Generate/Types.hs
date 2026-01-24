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
      , T.intercalate "\n" $ map generateRecordAesonInstances
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
generateRecord schema rec = T.unlines $
  [ "data " <> recordName rec <> " = " <> recordName rec ]
  ++ formatRecordFields schema (recordFields rec)
  ++ [ "  deriving (" <> T.intercalate ", " (recordDeriving rec) <> ")" ]

formatRecordFields :: DomainSchema -> [FieldDef] -> [Text]
formatRecordFields _ [] = ["  {}"]
formatRecordFields schema fields =
  zipWith (formatField schema) [0::Int ..] fields ++ ["  }"]
  where
    formatField s 0 f = "  { " <> fieldName f <> " :: " <> fieldTypeToHaskell s (fieldType f)
    formatField s _ f = "  , " <> fieldName f <> " :: " <> fieldTypeToHaskell s (fieldType f)

generateNewtype :: RecordDef -> Text
generateNewtype rec = case recordKind rec of
  NewtypeOver inner -> T.unlines
    [ "newtype " <> recordName rec <> " = " <> recordName rec
    , "  { items :: " <> inner
    , "  }"
    , "  deriving (" <> T.intercalate ", " (recordDeriving rec) <> ")"
    ]
  _ -> ""

generateInventoryResponse :: Text
generateInventoryResponse = T.unlines
  [ "data InventoryResponse"
  , "  = InventoryData Inventory"
  , "  | Message Text"
  , "  deriving (Show, Generic)"
  ]

generateRecordAesonInstances :: RecordDef -> Text
generateRecordAesonInstances rec = T.unlines
  [ "instance ToJSON " <> recordName rec
  , "instance FromJSON " <> recordName rec
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
generatePgInstances schema rec = case recordKind rec of
  NewtypeOver _ -> []
  RecordType
    | recordName rec == "InventoryResponse" -> []
    | otherwise ->
        [ generateToRowInstance schema rec
        , generateFromRowInstance schema rec
        ]

generateToRowInstance :: DomainSchema -> RecordDef -> Text
generateToRowInstance _ rec = T.unlines
  [ "instance ToRow " <> recordName rec <> " where"
  , "  toRow " <> recordName rec <> "{..} ="
  , "    [ " <> T.intercalate "\n    , " (map toRowField simpleFields) <> "\n    ]"
  ]
  where
    simpleFields = filter (not . isNestedFieldType . fieldType) (recordFields rec)

toRowField :: FieldDef -> Text
toRowField fld = case fieldType fld of
  FEnum _ -> "toField (show " <> fieldName fld <> ")"
  FVector _ -> "toField (PGArray $ V.toList " <> fieldName fld <> ")"
  _ -> "toField " <> fieldName fld

isNestedFieldType :: FieldType -> Bool
isNestedFieldType (FNested _) = True
isNestedFieldType _ = False

generateFromRowInstance :: DomainSchema -> RecordDef -> Text
generateFromRowInstance schema rec
  | hasNestedRecord rec = generateFromRowWithNested schema rec
  | otherwise = generateSimpleFromRow schema rec

hasNestedRecord :: RecordDef -> Bool
hasNestedRecord rec = any (isNestedFieldType . fieldType) (recordFields rec)

generateSimpleFromRow :: DomainSchema -> RecordDef -> Text
generateSimpleFromRow schema rec = T.unlines $
  [ "instance FromRow " <> recordName rec <> " where"
  , "  fromRow ="
  , "    " <> recordName rec
  ] ++ zipWith (fromRowField schema) [0::Int ..] (recordFields rec)

fromRowField :: DomainSchema -> Int -> FieldDef -> Text
fromRowField _ idx fld =
  let prefix = if idx == 0 then "      <$> " else "      <*> "
      parser = case fieldType fld of
        FEnum _ -> "(read <$> field)"
        FVector _ -> "(V.fromList . fromPGArray <$> field)"
        _ -> "field"
  in prefix <> parser

generateFromRowWithNested :: DomainSchema -> RecordDef -> Text
generateFromRowWithNested schema rec = T.unlines $
  [ "instance FromRow " <> recordName rec <> " where"
  , "  fromRow ="
  , "    " <> recordName rec
  ] ++ concatMap (fromRowFieldOrNested schema) (zip [0::Int ..] (recordFields rec))

fromRowFieldOrNested :: DomainSchema -> (Int, FieldDef) -> [Text]
fromRowFieldOrNested schema (idx, fld) = case fieldType fld of
  FNested nestedName ->
    let prefix = if idx == 0 then "      <$> " else "      <*> "
    in case findRecord schema nestedName of
      Nothing -> [prefix <> "field"]
      Just nested ->
        [ prefix <> "( " <> nestedName ]
        ++ map ("          " <>) (nestedFieldParsers nested)
        ++ [ "          )" ]
  _ -> [fromRowField schema idx fld]

nestedFieldParsers :: RecordDef -> [Text]
nestedFieldParsers rec =
  zipWith mkParser [0::Int ..] (recordFields rec)
  where
    mkParser 0 f = "<$> " <> fieldParser f
    mkParser _ f = "<*> " <> fieldParser f

    fieldParser fld = case fieldType fld of
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