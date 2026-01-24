{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Codegen.Generate.Database
  ( generateDbModule
  ) where

import Codegen.Schema
import Codegen.Generate.Common (GeneratedModule(..), moduleNameToPath, toTableName)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (fromMaybe, mapMaybe)
import Data.List (find)

generateDbModule :: DomainSchema -> GeneratedModule
generateDbModule schema = GeneratedModule
  { modulePath = moduleNameToPath (generatedDbModule schema)
  , moduleContent = T.unlines $ filter (not . T.null)
      [ generatePragmas
      , ""
      , generateModuleDecl schema
      , ""
      , generateImports schema
      , ""
      , "-- =============================================="
      , "-- DATABASE CONFIGURATION"
      , "-- =============================================="
      , ""
      , generateDbConfig
      , ""
      , "-- =============================================="
      , "-- CONNECTION HELPERS"
      , "-- =============================================="
      , ""
      , generateConnectionHelpers
      , ""
      , "-- =============================================="
      , "-- TABLE CREATION"
      , "-- =============================================="
      , ""
      , generateCreateTables schema
      , ""
      , "-- =============================================="
      , "-- INSERT OPERATIONS"
      , "-- =============================================="
      , ""
      , T.intercalate "\n\n" $ mapMaybe (generateInsertFunction schema) (schemaRecords schema)
      , ""
      , "-- =============================================="
      , "-- SELECT OPERATIONS"
      , "-- =============================================="
      , ""
      , T.intercalate "\n\n" $ mapMaybe (generateSelectFunction schema) (schemaRecords schema)
      , ""
      , "-- =============================================="
      , "-- UPDATE OPERATIONS"
      , "-- =============================================="
      , ""
      , T.intercalate "\n\n" $ mapMaybe (generateUpdateFunction schema) (schemaRecords schema)
      , ""
      , "-- =============================================="
      , "-- DELETE OPERATIONS"
      , "-- =============================================="
      , ""
      , T.intercalate "\n\n" $ mapMaybe (generateDeleteFunction schema) (schemaRecords schema)
      ]
  }

generatePragmas :: Text
generatePragmas = T.unlines
  [ "{-# LANGUAGE OverloadedStrings #-}"
  , "{-# LANGUAGE QuasiQuotes #-}"
  , "{-# LANGUAGE RecordWildCards #-}"
  , "{-# LANGUAGE TypeApplications #-}"
  ]

generateModuleDecl :: DomainSchema -> Text
generateModuleDecl schema =
  let modName = generatedDbModule schema
  in "module " <> modName <> " where"

generateImports :: DomainSchema -> Text
generateImports schema = T.unlines
  [ "import Control.Concurrent (threadDelay)"
  , "import Control.Exception (catch, throwIO, SomeException, try)"
  , "import Control.Monad.IO.Class (liftIO)"
  , "import Control.Monad.Error.Class (throwError)"
  , "import qualified Data.Pool as Pool"
  , "import Data.Text (Text, pack)"
  , "import qualified Data.Vector as V"
  , "import Data.UUID (UUID)"
  , "import Database.PostgreSQL.Simple"
  , "import Database.PostgreSQL.Simple.SqlQQ (sql)"
  , "import Database.PostgreSQL.Simple.Types (PGArray(..))"
  , "import Servant (Handler)"
  , "import Servant.Server (err404)"
  , "import System.IO (hPutStrLn, stderr)"
  , "import " <> generatedTypesModule schema
  ]

generateDbConfig :: Text
generateDbConfig = T.unlines
  [ "data DBConfig = DBConfig"
  , "  { dbHost :: String"
  , "  , dbPort :: Int"
  , "  , dbName :: String"
  , "  , dbUser :: String"
  , "  , dbPassword :: String"
  , "  , poolSize :: Int"
  , "  }"
  ]

generateConnectionHelpers :: Text
generateConnectionHelpers = T.unlines
  [ "initializeDB :: DBConfig -> IO (Pool.Pool Connection)"
  , "initializeDB config = do"
  , "  let poolConfig ="
  , "        Pool.defaultPoolConfig"
  , "          (connectWithRetry config)"
  , "          close"
  , "          0.5"
  , "          10"
  , "  pool <- Pool.newPool poolConfig"
  , "  Pool.withResource pool $ \\conn -> do"
  , "    _ <- query_ conn \"SELECT 1\" :: IO [Only Int]"
  , "    pure ()"
  , "  pure pool"
  , ""
  , "connectWithRetry :: DBConfig -> IO Connection"
  , "connectWithRetry DBConfig{..} = go 5"
  , "  where"
  , "    go :: Int -> IO Connection"
  , "    go retriesLeft = do"
  , "      let connInfo ="
  , "            defaultConnectInfo"
  , "              { connectHost = dbHost"
  , "              , connectPort = fromIntegral dbPort"
  , "              , connectDatabase = dbName"
  , "              , connectUser = dbUser"
  , "              , connectPassword = dbPassword"
  , "              }"
  , "      catch"
  , "        (connect connInfo)"
  , "        (`handleConnError` retriesLeft)"
  , ""
  , "    handleConnError :: SqlError -> Int -> IO Connection"
  , "    handleConnError e retriesLeft"
  , "      | retriesLeft == 0 = do"
  , "          hPutStrLn stderr $ \"Failed to connect to database after 5 attempts: \" ++ show e"
  , "          throwIO e"
  , "      | otherwise = do"
  , "          hPutStrLn stderr \"Database connection attempt failed, retrying in 5 seconds...\""
  , "          threadDelay 5000000"
  , "          go (retriesLeft - 1)"
  , ""
  , "withConnection :: Pool.Pool Connection -> (Connection -> IO a) -> IO a"
  , "withConnection = Pool.withResource"
  ]

generateCreateTables :: DomainSchema -> Text
generateCreateTables schema = T.unlines $
  [ "createTables :: Pool.Pool Connection -> IO ()"
  , "createTables pool = withConnection pool $ \\conn -> do"
  ] ++ concatMap (generateCreateTableSql schema) (getMainRecords schema)
  ++ [ "  pure ()" ]

getMainRecords :: DomainSchema -> [RecordDef]
getMainRecords schema = filter isMainRecord (schemaRecords schema)
  where
    isMainRecord r = case recordKind r of
      RecordType -> r.recordName /= "InventoryResponse"
      _ -> False

generateCreateTableSql :: DomainSchema -> RecordDef -> [Text]
generateCreateTableSql schema rec = case recordKind rec of
  NewtypeOver _ -> []
  RecordType ->
    [ "  _ <-"
    , "    execute_"
    , "      conn"
    , "      [sql|"
    , "        CREATE TABLE IF NOT EXISTS " <> tableName <> " ("
    ] ++ map ("          " <>) (generateColumns schema rec)
    ++ [ "        )"
       , "      |]"
       , ""
       ]
  where
    tableName = toTableName (recordName rec)

generateColumns :: DomainSchema -> RecordDef -> [Text]
generateColumns _ rec =
  zipWith formatCol [0..] simpleFields
  where
    simpleFields = filter (not . isNestedFieldType . fieldType) (recordFields rec)
    numFields = length simpleFields

    formatCol :: Int -> FieldDef -> Text
    formatCol idx fld =
      colName <> " " <> sqlType <> constraints <> comma
      where
        colName = fromMaybe (fieldName fld) (fieldDbColumn fld)
        sqlType = fieldTypeToSql (fieldType fld)
        constraints = generateConstraints fld
        comma = if idx == numFields - 1 then "" else ","

    generateConstraints fld
      | fieldName fld == "sku" = " PRIMARY KEY"
      | Required `elem` fieldValidations fld = " NOT NULL"
      | otherwise = ""

isNestedFieldType :: FieldType -> Bool
isNestedFieldType (FNested _) = True
isNestedFieldType _ = False

fieldTypeToSql :: FieldType -> Text
fieldTypeToSql = \case
  FText -> "TEXT"
  FInt -> "INTEGER"
  FInteger -> "BIGINT"
  FDouble -> "DOUBLE PRECISION"
  FBool -> "BOOLEAN"
  FUuid -> "UUID"
  FUtcTime -> "TIMESTAMP WITH TIME ZONE"
  FMoney -> "INTEGER"
  FVector _ -> "TEXT[]"
  FList _ -> "TEXT[]"
  FMaybe inner -> fieldTypeToSql inner
  FEnum _ -> "TEXT"
  FNested _ -> "TEXT"
  FCustom _ -> "TEXT"

generateInsertFunction :: DomainSchema -> RecordDef -> Maybe Text
generateInsertFunction schema rec = case recordKind rec of
  NewtypeOver _ -> Nothing
  RecordType
    | recordName rec == "InventoryResponse" -> Nothing
    | hasNestedField rec -> Just $ generateInsertWithNested schema rec
    | otherwise -> Just $ generateSimpleInsert rec

hasNestedField :: RecordDef -> Bool
hasNestedField rec = any (isNestedFieldType . fieldType) (recordFields rec)

generateSimpleInsert :: RecordDef -> Text
generateSimpleInsert rec = T.unlines
  [ "insert" <> recName <> " :: Pool.Pool Connection -> " <> recName <> " -> IO ()"
  , "insert" <> recName <> " pool " <> recName <> "{..} = withConnection pool $ \\conn -> do"
  , "  _ <-"
  , "    execute"
  , "      conn"
  , "      [sql|"
  , "        INSERT INTO " <> tableName
  , "            (" <> T.intercalate ", " colNames <> ")"
  , "        VALUES (" <> T.intercalate ", " placeholders <> ")"
  , "      |]"
  , "      ( " <> T.intercalate "\n      , " fieldRefs
  , "      )"
  , "  pure ()"
  ]
  where
    recName = recordName rec
    tableName = toTableName recName
    simpleFields = filter (not . isNestedFieldType . fieldType) (recordFields rec)
    colNames = map fieldName simpleFields
    placeholders = replicate (length simpleFields) "?"
    fieldRefs = map formatFieldRef simpleFields

generateInsertWithNested :: DomainSchema -> RecordDef -> Text
generateInsertWithNested schema rec = T.unlines $
  [ "insert" <> recName <> " :: Pool.Pool Connection -> " <> recName <> " -> IO ()"
  , "insert" <> recName <> " pool " <> recName <> "{..} = withConnection pool $ \\conn -> do"
  , "  _ <-"
  , "    execute"
  , "      conn"
  , "      [sql|"
  , "        INSERT INTO " <> tableName
  , "            (" <> T.intercalate ", " mainColNames <> ")"
  , "        VALUES (" <> T.intercalate ", " mainPlaceholders <> ")"
  , "      |]"
  , "      ( " <> T.intercalate "\n      , " mainFieldRefs
  , "      )"
  , ""
  ] ++ concatMap (generateNestedInsert schema) nestedFields ++
  [ "  pure ()"
  ]
  where
    recName = recordName rec
    tableName = toTableName recName
    mainFields = filter (not . isNestedFieldType . fieldType) (recordFields rec)
    nestedFields = filter (isNestedFieldType . fieldType) (recordFields rec)
    mainColNames = map fieldName mainFields
    mainPlaceholders = replicate (length mainFields) "?"
    mainFieldRefs = map formatFieldRef mainFields

generateNestedInsert :: DomainSchema -> FieldDef -> [Text]
generateNestedInsert schema fld = case fieldType fld of
  FNested nestedName -> case findRecord schema nestedName of
    Nothing -> []
    Just nestedRec ->
      let nestedTableName = toTableName nestedName
          nestedFields = recordFields nestedRec
          colNames = "sku" : map fieldName nestedFields
          placeholders = replicate (length colNames) "?"
      in
      [ "  let " <> nestedName <> "{..} = " <> fieldName fld
      , "  _ <-"
      , "    execute"
      , "      conn"
      , "      [sql|"
      , "        INSERT INTO " <> nestedTableName
      , "            (" <> T.intercalate ", " colNames <> ")"
      , "        VALUES (" <> T.intercalate ", " placeholders <> ")"
      , "      |]"
      , "      ( sku"
      , "      , " <> T.intercalate "\n      , " (map formatFieldRef nestedFields)
      , "      )"
      , ""
      ]
  _ -> []

formatFieldRef :: FieldDef -> Text
formatFieldRef fld = case fieldType fld of
  FEnum _ -> "show " <> fieldName fld
  FVector _ -> "PGArray $ V.toList " <> fieldName fld
  _ -> fieldName fld

generateSelectFunction :: DomainSchema -> RecordDef -> Maybe Text
generateSelectFunction schema rec = case recordKind rec of
  NewtypeOver innerType
    | "MenuItem" `T.isInfixOf` innerType -> Just $ generateInventorySelect schema rec
    | otherwise -> Nothing
  RecordType
    | rec.recordName == "InventoryResponse" -> Nothing
    | isNestedRecord schema rec -> Nothing
    | otherwise -> Just $ generateSimpleSelect rec

isNestedRecord :: DomainSchema -> RecordDef -> Bool
isNestedRecord schema rec =
  any referencesThis (schemaRecords schema)
  where
    referencesThis r = any (references (recordName rec)) (recordFields r)
    references name fld = case fieldType fld of
      FNested n -> n == name
      _ -> False

generateSimpleSelect :: RecordDef -> Text
generateSimpleSelect rec = T.unlines
  [ "getAll" <> recName <> "s :: Pool.Pool Connection -> IO [" <> recName <> "]"
  , "getAll" <> recName <> "s pool = withConnection pool $ \\conn -> do"
  , "  query_ conn"
  , "    [sql|"
  , "      SELECT"
  , "        " <> T.intercalate ",\n        " selectCols
  , "      FROM " <> tableName
  , "      ORDER BY " <> orderCol
  , "    |]"
  ]
  where
    recName = recordName rec
    tableName = toTableName recName
    simpleFields = filter (not . isNestedFieldType . fieldType) (recordFields rec)
    selectCols = map (("m." <>) . fieldName) simpleFields
    orderCol = maybe "1" fieldName $ find (\f -> fieldName f == "sort") (recordFields rec)

generateInventorySelect :: DomainSchema -> RecordDef -> Text
generateInventorySelect _ _ = T.unlines
  [ "getAllMenuItems :: Pool.Pool Connection -> IO Inventory"
  , "getAllMenuItems pool = withConnection pool $ \\conn -> do"
  , "  items <- query_ conn"
  , "    [sql|"
  , "      SELECT"
  , "        m.sort, m.sku, m.brand, m.name, m.price, m.measure_unit, m.per_package,"
  , "        m.quantity, m.category, m.subcategory, m.description, m.tags, m.effects,"
  , "        s.thc, s.cbg, s.strain, s.creator, s.species,"
  , "        s.dominant_terpene, s.terpenes, s.lineage,"
  , "        s.leafly_url, s.img"
  , "      FROM menu_items m"
  , "      JOIN strain_lineage s ON m.sku = s.sku"
  , "      ORDER BY m.sort"
  , "    |]"
  , "  return $ Inventory $ V.fromList items"
  ]

generateUpdateFunction :: DomainSchema -> RecordDef -> Maybe Text
generateUpdateFunction schema rec = case recordKind rec of
  NewtypeOver _ -> Nothing
  RecordType
    | recordName rec == "InventoryResponse" -> Nothing
    | isNestedRecord schema rec -> Nothing
    | hasNestedField rec -> Just $ generateUpdateWithNested schema rec
    | otherwise -> Just $ generateSimpleUpdate rec

generateSimpleUpdate :: RecordDef -> Text
generateSimpleUpdate rec = T.unlines
  [ "update" <> recName <> " :: Pool.Pool Connection -> " <> recName <> " -> IO ()"
  , "update" <> recName <> " pool " <> recName <> "{..} = withConnection pool $ \\conn -> do"
  , "  _ <-"
  , "    execute"
  , "      conn"
  , "      [sql|"
  , "        UPDATE " <> tableName
  , "        SET " <> T.intercalate ", " setClauses
  , "        WHERE sku = ?"
  , "      |]"
  , "      ( " <> T.intercalate "\n      , " (updateFieldRefs ++ ["sku"])
  , "      )"
  , "  pure ()"
  ]
  where
    recName = recordName rec
    tableName = toTableName recName
    updateFields = filter (\f -> fieldName f /= "sku" && not (isNestedFieldType (fieldType f))) (recordFields rec)
    setClauses = map (\f -> fieldName f <> " = ?") updateFields
    updateFieldRefs = map formatFieldRef updateFields

generateUpdateWithNested :: DomainSchema -> RecordDef -> Text
generateUpdateWithNested schema rec = T.unlines $
  [ "updateExisting" <> recName <> " :: Pool.Pool Connection -> " <> recName <> " -> IO ()"
  , "updateExisting" <> recName <> " pool " <> recName <> "{..} = withConnection pool $ \\conn -> do"
  , "  _ <-"
  , "    execute"
  , "      conn"
  , "      [sql|"
  , "        UPDATE " <> tableName
  , "        SET " <> T.intercalate ", " mainSetClauses
  , "        WHERE sku = ?"
  , "      |]"
  , "      ( " <> T.intercalate "\n      , " (mainUpdateRefs ++ ["sku"])
  , "      )"
  , ""
  ] ++ concatMap (generateNestedUpdate schema) nestedFields ++
  [ "  pure ()"
  ]
  where
    recName = recordName rec
    tableName = toTableName recName
    mainFields = filter (\f -> fieldName f /= "sku" && not (isNestedFieldType (fieldType f))) (recordFields rec)
    nestedFields = filter (isNestedFieldType . fieldType) (recordFields rec)
    mainSetClauses = map (\f -> fieldName f <> " = ?") mainFields
    mainUpdateRefs = map formatFieldRef mainFields

generateNestedUpdate :: DomainSchema -> FieldDef -> [Text]
generateNestedUpdate schema fld = case fieldType fld of
  FNested nestedName -> case findRecord schema nestedName of
    Nothing -> []
    Just nestedRec ->
      let nestedTableName = toTableName nestedName
          nestedFields = recordFields nestedRec
          setClauses = map (\f -> fieldName f <> " = ?") nestedFields
          fieldRefs = map formatFieldRef nestedFields
      in
      [ "  let " <> nestedName <> "{..} = " <> fieldName fld
      , "  _ <-"
      , "    execute"
      , "      conn"
      , "      [sql|"
      , "        UPDATE " <> nestedTableName
      , "        SET " <> T.intercalate ", " setClauses
      , "        WHERE sku = ?"
      , "      |]"
      , "      ( " <> T.intercalate "\n      , " fieldRefs
      , "      , sku"
      , "      )"
      , ""
      ]
  _ -> []

generateDeleteFunction :: DomainSchema -> RecordDef -> Maybe Text
generateDeleteFunction schema rec = case recordKind rec of
  NewtypeOver _ -> Nothing
  RecordType
    | recordName rec == "InventoryResponse" -> Nothing
    | isNestedRecord schema rec -> Nothing
    | hasNestedField rec -> Just $ generateDeleteWithNested schema rec
    | otherwise -> Just $ generateSimpleDelete rec

generateSimpleDelete :: RecordDef -> Text
generateSimpleDelete rec = T.unlines
  [ "delete" <> recName <> " :: Pool.Pool Connection -> UUID -> Handler InventoryResponse"
  , "delete" <> recName <> " pool uuid = do"
  , "  liftIO $ putStrLn $ \"Received request to delete " <> T.toLower recName <> " with UUID: \" ++ show uuid"
  , "  result <- liftIO $ try @SomeException $ do"
  , "    withConnection pool $ \\conn ->"
  , "      execute"
  , "        conn"
  , "        \"DELETE FROM " <> tableName <> " WHERE sku = ?\""
  , "        (Only uuid)"
  , "  case result of"
  , "    Left e -> do"
  , "      let errMsg = pack $ \"Error deleting item: \" <> show e"
  , "      liftIO $ putStrLn $ \"Error in delete operation: \" ++ show e"
  , "      return $ Message errMsg"
  , "    Right affected ->"
  , "      if affected > 0"
  , "        then return $ Message \"Item deleted successfully\""
  , "        else throwError err404"
  ]
  where
    recName = recordName rec
    tableName = toTableName recName

generateDeleteWithNested :: DomainSchema -> RecordDef -> Text
generateDeleteWithNested _schema rec = T.unlines $
  [ "delete" <> recName <> " :: Pool.Pool Connection -> UUID -> Handler InventoryResponse"
  , "delete" <> recName <> " pool uuid = do"
  , "  liftIO $ putStrLn $ \"Received request to delete " <> T.toLower recName <> " with UUID: \" ++ show uuid"
  , ""
  , "  result <- liftIO $ try @SomeException $ do"
  ] ++ map generateNestedDelete nestedFields ++
  [ ""
  , "    withConnection pool $ \\conn ->"
  , "      execute"
  , "        conn"
  , "        \"DELETE FROM " <> tableName <> " WHERE sku = ?\""
  , "        (Only uuid)"
  , ""
  , "  case result of"
  , "    Left e -> do"
  , "      let errMsg = pack $ \"Error deleting item: \" <> show e"
  , "      liftIO $ putStrLn $ \"Error in delete operation: \" ++ show e"
  , "      return $ Message errMsg"
  , "    Right affected ->"
  , "      if affected > 0"
  , "        then return $ Message \"Item deleted successfully\""
  , "        else throwError err404"
  ]
  where
    recName = recordName rec
    tableName = toTableName recName
    nestedFields = filter (isNestedFieldType . fieldType) (recordFields rec)

    generateNestedDelete fld = case fieldType fld of
      FNested nestedName ->
        "    _ <- withConnection pool $ \\conn ->\n" <>
        "      execute\n" <>
        "        conn\n" <>
        "        \"DELETE FROM " <> toTableName nestedName <> " WHERE sku = ?\"\n" <>
        "        (Only uuid)"
      _ -> ""

findRecord :: DomainSchema -> Text -> Maybe RecordDef
findRecord schema name =
  find (\r -> recordName r == name) (schemaRecords schema)