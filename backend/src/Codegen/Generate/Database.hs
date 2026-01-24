{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}

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
  { modulePath = moduleNameToPath (schemaDbModuleName schema <> ".Generated")
  , moduleContent = T.unlines $ filter (not . T.null)
      [ generatePragmas
      , ""
      , generateModuleDecl schema
      , ""
      , generateImports schema
      , ""
      , "-- ============================================"
      , "-- Database Configuration"
      , "-- ============================================"
      , ""
      , generateDbConfig
      , ""
      , "-- ============================================"
      , "-- Connection Helpers"
      , "-- ============================================"
      , ""
      , generateConnectionHelpers
      , ""
      , "-- ============================================"
      , "-- Table Creation"
      , "-- ============================================"
      , ""
      , generateCreateTables schema
      , ""
      , "-- ============================================"
      , "-- Insert Operations"
      , "-- ============================================"
      , ""
      , T.intercalate "\n\n" $ mapMaybe (generateInsertFunction schema) (schemaRecords schema)
      , ""
      , "-- ============================================"
      , "-- Select Operations"
      , "-- ============================================"
      , ""
      , T.intercalate "\n\n" $ mapMaybe (generateSelectFunction schema) (schemaRecords schema)
      , ""
      , "-- ============================================"
      , "-- Update Operations"
      , "-- ============================================"
      , ""
      , T.intercalate "\n\n" $ mapMaybe (generateUpdateFunction schema) (schemaRecords schema)
      , ""
      , "-- ============================================"
      , "-- Delete Operations"
      , "-- ============================================"
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
  "module " <> schemaDbModuleName schema <> ".Generated where"

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
  , "import " <> schemaModuleName schema
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
      RecordType -> recordName r `notElem` ["InventoryResponse"]
      _ -> False

generateCreateTableSql :: DomainSchema -> RecordDef -> [Text]
generateCreateTableSql schema rec@RecordDef{..} = case recordKind of
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
    tableName = toTableName recordName

generateColumns :: DomainSchema -> RecordDef -> [Text]
generateColumns _ RecordDef{..} =
  zipWith formatCol [0..] $ filter (not . isNestedField) recordFields
  where
    isNestedField f = case fieldType f of
      FNested _ -> True
      _ -> False

    numFields = length $ filter (not . isNestedField) recordFields

    formatCol :: Int -> FieldDef -> Text
    formatCol idx f@FieldDef{..} =
      colName <> " " <> sqlType <> constraints <> comma
      where
        colName = fromMaybe fieldName fieldDbColumn
        sqlType = fieldTypeToSql (fieldType f)
        constraints = generateConstraints f
        comma = if idx == numFields - 1 then "" else ","

    generateConstraints FieldDef{..}
      | fieldName == "sku" = " PRIMARY KEY"
      | Required `elem` fieldValidations = " NOT NULL"
      | otherwise = ""

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
generateInsertFunction schema rec@RecordDef{..} = case recordKind of
  NewtypeOver _ -> Nothing
  RecordType
    | recordName `elem` ["InventoryResponse"] -> Nothing
    | hasNestedField rec -> Just $ generateInsertWithNested schema rec
    | otherwise -> Just $ generateSimpleInsert schema rec

hasNestedField :: RecordDef -> Bool
hasNestedField RecordDef{..} = any isNested recordFields
  where
    isNested f = case fieldType f of
      FNested _ -> True
      _ -> False

generateSimpleInsert :: DomainSchema -> RecordDef -> Text
generateSimpleInsert _ RecordDef{..} = T.unlines
  [ "insert" <> recordName <> " :: Pool.Pool Connection -> " <> recordName <> " -> IO ()"
  , "insert" <> recordName <> " pool " <> recordName <> "{..} = withConnection pool $ \\conn -> do"
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
    tableName = toTableName recordName
    simpleFields = filter (not . isNested) recordFields
    colNames = map fieldName simpleFields
    placeholders = replicate (length simpleFields) "?"
    fieldRefs = map formatFieldRef simpleFields
    isNested f = case fieldType f of
      FNested _ -> True
      _ -> False

generateInsertWithNested :: DomainSchema -> RecordDef -> Text
generateInsertWithNested schema rec@RecordDef{..} = T.unlines $
  [ "insert" <> recordName <> " :: Pool.Pool Connection -> " <> recordName <> " -> IO ()"
  , "insert" <> recordName <> " pool " <> recordName <> "{..} = withConnection pool $ \\conn -> do"
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
  ] ++ concatMap (generateNestedInsert schema rec) nestedFields ++
  [ "  pure ()"
  ]
  where
    tableName = toTableName recordName
    mainFields = filter (not . isNested) recordFields
    nestedFields = filter isNested recordFields
    mainColNames = map fieldName mainFields
    mainPlaceholders = replicate (length mainFields) "?"
    mainFieldRefs = map formatFieldRef mainFields
    isNested f = case fieldType f of
      FNested _ -> True
      _ -> False

generateNestedInsert :: DomainSchema -> RecordDef -> FieldDef -> [Text]
generateNestedInsert schema _ FieldDef{..} = case fieldType of
  FNested nestedName -> case findRecord schema nestedName of
    Nothing -> []
    Just nestedRec ->
      let nestedTableName = toTableName nestedName
          nestedFields = recordFields nestedRec
          colNames = "sku" : map fieldName nestedFields
          placeholders = replicate (length colNames) "?"
      in
      [ "  let " <> nestedName <> "{..} = " <> fieldName
      , "  _ <-"
      , "    execute"
      , "      conn"
      , "      [sql|"
      , "        INSERT INTO " <> nestedTableName
      , "            (" <> T.intercalate ", " colNames <> ")"
      , "        VALUES (" <> T.intercalate ", " placeholders <> ")"
      , "      |]"
      , "      ( sku"
      , "      , " <> T.intercalate "\n      , " (map (formatNestedFieldRef nestedName) nestedFields)
      , "      )"
      , ""
      ]
  _ -> []

formatFieldRef :: FieldDef -> Text
formatFieldRef FieldDef{..} = case fieldType of
  FEnum _ -> "show " <> fieldName
  FVector _ -> "PGArray $ V.toList " <> fieldName
  _ -> fieldName

formatNestedFieldRef :: Text -> FieldDef -> Text
formatNestedFieldRef _ FieldDef{..} = case fieldType of
  FEnum _ -> "show " <> fieldName
  FVector _ -> "PGArray $ V.toList " <> fieldName
  _ -> fieldName

generateSelectFunction :: DomainSchema -> RecordDef -> Maybe Text
generateSelectFunction schema rec@RecordDef{..} = case recordKind of
  NewtypeOver innerType
    | "MenuItem" `T.isInfixOf` innerType -> Just $ generateInventorySelect schema rec
    | otherwise -> Nothing
  RecordType
    | recordName `elem` ["InventoryResponse"] -> Nothing
    | isNestedRecord schema rec -> Nothing
    | otherwise -> Just $ generateSimpleSelect schema rec

isNestedRecord :: DomainSchema -> RecordDef -> Bool
isNestedRecord schema RecordDef{..} =
  any (referencesThis . recordFields) (schemaRecords schema)
  where
    referencesThis fields = any (references recordName) fields
    references name f = case fieldType f of
      FNested n -> n == name
      _ -> False

generateSimpleSelect :: DomainSchema -> RecordDef -> Text
generateSimpleSelect _ RecordDef{..} = T.unlines
  [ "getAll" <> recordName <> "s :: Pool.Pool Connection -> IO [" <> recordName <> "]"
  , "getAll" <> recordName <> "s pool = withConnection pool $ \\conn -> do"
  , "  query_ conn"
  , "    [sql|"
  , "      SELECT"
  , "        " <> T.intercalate ",\n        " selectCols
  , "      FROM " <> tableName
  , "      ORDER BY " <> orderCol
  , "    |]"
  ]
  where
    tableName = toTableName recordName
    simpleFields = filter (not . isNested) recordFields
    selectCols = map (("m." <>) . fieldName) simpleFields
    orderCol = maybe "1" fieldName $ find (\f -> fieldName f == "sort") recordFields
    isNested f = case fieldType f of
      FNested _ -> True
      _ -> False

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
generateUpdateFunction schema rec@RecordDef{..} = case recordKind of
  NewtypeOver _ -> Nothing
  RecordType
    | recordName `elem` ["InventoryResponse"] -> Nothing
    | isNestedRecord schema rec -> Nothing
    | hasNestedField rec -> Just $ generateUpdateWithNested schema rec
    | otherwise -> Just $ generateSimpleUpdate schema rec

generateSimpleUpdate :: DomainSchema -> RecordDef -> Text
generateSimpleUpdate _ RecordDef{..} = T.unlines
  [ "update" <> recordName <> " :: Pool.Pool Connection -> " <> recordName <> " -> IO ()"
  , "update" <> recordName <> " pool " <> recordName <> "{..} = withConnection pool $ \\conn -> do"
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
    tableName = toTableName recordName
    updateFields = filter (\f -> fieldName f /= "sku" && not (isNested f)) recordFields
    setClauses = map (\f -> fieldName f <> " = ?") updateFields
    updateFieldRefs = map formatFieldRef updateFields
    isNested f = case fieldType f of
      FNested _ -> True
      _ -> False

generateUpdateWithNested :: DomainSchema -> RecordDef -> Text
generateUpdateWithNested schema rec@RecordDef{..} = T.unlines $
  [ "updateExisting" <> recordName <> " :: Pool.Pool Connection -> " <> recordName <> " -> IO ()"
  , "updateExisting" <> recordName <> " pool " <> recordName <> "{..} = withConnection pool $ \\conn -> do"
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
    tableName = toTableName recordName
    mainFields = filter (\f -> fieldName f /= "sku" && not (isNested f)) recordFields
    nestedFields = filter isNested recordFields
    mainSetClauses = map (\f -> fieldName f <> " = ?") mainFields
    mainUpdateRefs = map formatFieldRef mainFields
    isNested f = case fieldType f of
      FNested _ -> True
      _ -> False

generateNestedUpdate :: DomainSchema -> FieldDef -> [Text]
generateNestedUpdate schema FieldDef{..} = case fieldType of
  FNested nestedName -> case findRecord schema nestedName of
    Nothing -> []
    Just nestedRec ->
      let nestedTableName = toTableName nestedName
          nestedFields = recordFields nestedRec
          setClauses = map (\f -> fieldName f <> " = ?") nestedFields
          fieldRefs = map (formatNestedFieldRef nestedName) nestedFields
      in
      [ "  let " <> nestedName <> "{..} = " <> fieldName
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
generateDeleteFunction schema rec@RecordDef{..} = case recordKind of
  NewtypeOver _ -> Nothing
  RecordType
    | recordName `elem` ["InventoryResponse"] -> Nothing
    | isNestedRecord schema rec -> Nothing
    | hasNestedField rec -> Just $ generateDeleteWithNested schema rec
    | otherwise -> Just $ generateSimpleDelete schema rec

generateSimpleDelete :: DomainSchema -> RecordDef -> Text
generateSimpleDelete _ RecordDef{..} = T.unlines
  [ "delete" <> recordName <> " :: Pool.Pool Connection -> UUID -> Handler InventoryResponse"
  , "delete" <> recordName <> " pool uuid = do"
  , "  liftIO $ putStrLn $ \"Received request to delete " <> T.toLower recordName <> " with UUID: \" ++ show uuid"
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
    tableName = toTableName recordName

generateDeleteWithNested :: DomainSchema -> RecordDef -> Text
generateDeleteWithNested schema rec@RecordDef{..} = T.unlines $
  [ "delete" <> recordName <> " :: Pool.Pool Connection -> UUID -> Handler InventoryResponse"
  , "delete" <> recordName <> " pool uuid = do"
  , "  liftIO $ putStrLn $ \"Received request to delete " <> T.toLower recordName <> " with UUID: \" ++ show uuid"
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
    tableName = toTableName recordName
    nestedFields = filter isNested recordFields
    isNested f = case fieldType f of
      FNested _ -> True
      _ -> False

    generateNestedDelete FieldDef{..} = case fieldType of
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