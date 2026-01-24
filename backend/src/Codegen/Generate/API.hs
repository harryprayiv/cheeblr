{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Codegen.Generate.API
  ( generateApiModule
  ) where

import Codegen.Schema
import Codegen.Generate.Common (GeneratedModule(..), moduleNameToPath)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe)

generateApiModule :: DomainSchema -> GeneratedModule
generateApiModule schema = GeneratedModule
  { modulePath = moduleNameToPath (generatedApiModule schema)
  , moduleContent = T.unlines $ filter (not . T.null)
      [ generatePragmas
      , ""
      , generateModuleDecl schema
      , ""
      , generateImports schema
      , ""
      , "-- =============================================="
      , "-- API TYPE DEFINITIONS"
      , "-- =============================================="
      , ""
      , generateApiTypes schema
      , ""
      , "-- =============================================="
      , "-- API PROXIES"
      , "-- =============================================="
      , ""
      , generateProxies schema
      ]
  }

generatePragmas :: Text
generatePragmas = T.unlines
  [ "{-# LANGUAGE DataKinds #-}"
  , "{-# LANGUAGE TypeOperators #-}"
  ]

generateModuleDecl :: DomainSchema -> Text
generateModuleDecl schema =
  let modName = generatedApiModule schema
      exports = generateExports schema
  in "module " <> modName <> "\n  ( " <> exports <> "\n  ) where"

generateExports :: DomainSchema -> Text
generateExports schema = 
  let apiTypes = mapMaybe (getApiTypeName schema) (schemaRecords schema)
      proxyNames = map (\t -> T.toLower t <> "API") apiTypes
  in T.intercalate "\n  , " (apiTypes ++ proxyNames)

getApiTypeName :: DomainSchema -> RecordDef -> Maybe Text
getApiTypeName schema rec = case recordKind rec of
  NewtypeOver _ -> Just $ recordName rec <> "API"
  RecordType
    | recordName rec == "InventoryResponse" -> Nothing
    | isNestedRecord schema rec -> Nothing
    | otherwise -> Just $ recordName rec <> "API"

generateImports :: DomainSchema -> Text
generateImports schema = T.unlines
  [ "import Data.UUID (UUID)"
  , "import Servant"
  , "import " <> generatedTypesModule schema
  ]

generateApiTypes :: DomainSchema -> Text
generateApiTypes schema = T.intercalate "\n\n" $ mapMaybe (generateApiType schema) (schemaRecords schema)

generateApiType :: DomainSchema -> RecordDef -> Maybe Text
generateApiType schema rec = case recordKind rec of
  NewtypeOver _ -> Just $ generateCollectionApi schema rec
  RecordType
    | recordName rec == "InventoryResponse" -> Nothing
    | isNestedRecord schema rec -> Nothing
    | otherwise -> Just $ generateCrudApi schema rec

isNestedRecord :: DomainSchema -> RecordDef -> Bool
isNestedRecord schema rec =
  any referencesThis (schemaRecords schema)
  where
    referencesThis r = any (references (recordName rec)) (recordFields r)
    references name fld = case fieldType fld of
      FNested n -> n == name
      _ -> False

generateCrudApi :: DomainSchema -> RecordDef -> Text
generateCrudApi schema rec = T.unlines
  [ "-- | CRUD API for " <> recName
  , "type " <> recName <> "API ="
  , "  \"" <> endpoint <> "\" :> Get '[JSON] " <> responseType
  , "    :<|> \"" <> endpoint <> "\" :> ReqBody '[JSON] " <> recName <> " :> Post '[JSON] " <> responseType
  , "    :<|> \"" <> endpoint <> "\" :> ReqBody '[JSON] " <> recName <> " :> Put '[JSON] " <> responseType
  , "    :<|> \"" <> endpoint <> "\" :> Capture \"" <> pkField <> "\" UUID :> Delete '[JSON] " <> responseType
  ]
  where
    recName = recordName rec
    endpoint = T.toLower recName
    responseType = findResponseType schema recName
    pkField = findPrimaryKeyField (recordFields rec)

generateCollectionApi :: DomainSchema -> RecordDef -> Text
generateCollectionApi schema rec = case recordKind rec of
  NewtypeOver innerType ->
    let itemName = extractItemName innerType
        recName = recordName rec
        endpoint = T.toLower recName
        responseType = findResponseType schema itemName
    in T.unlines
      [ "-- | Collection API for " <> recName
      , "type " <> recName <> "API ="
      , "  \"" <> endpoint <> "\" :> Get '[JSON] " <> responseType
      , "    :<|> \"" <> endpoint <> "\" :> ReqBody '[JSON] " <> itemName <> " :> Post '[JSON] " <> responseType
      , "    :<|> \"" <> endpoint <> "\" :> ReqBody '[JSON] " <> itemName <> " :> Put '[JSON] " <> responseType
      , "    :<|> \"" <> endpoint <> "\" :> Capture \"sku\" UUID :> Delete '[JSON] " <> responseType
      ]
  _ -> ""

extractItemName :: Text -> Text
extractItemName innerType =
  -- Extract "MenuItem" from "V.Vector MenuItem"
  case T.words innerType of
    [_, name] -> name
    _ -> innerType

findResponseType :: DomainSchema -> Text -> Text
findResponseType schema _ =
  -- Find the response type in the schema (e.g., InventoryResponse)
  let responseTypes = filter isResponseType (schemaRecords schema)
  in case responseTypes of
    (r:_) -> recordName r
    [] -> "InventoryResponse"
  where
    isResponseType r = "Response" `T.isSuffixOf` recordName r

findPrimaryKeyField :: [FieldDef] -> Text
findPrimaryKeyField fields =
  case filter isPk fields of
    (f:_) -> fieldName f
    [] -> "id"
  where
    isPk f = fieldName f == "sku" || fieldName f == "id"

generateProxies :: DomainSchema -> Text
generateProxies schema = T.intercalate "\n\n" $ mapMaybe (generateProxy schema) (schemaRecords schema)

generateProxy :: DomainSchema -> RecordDef -> Maybe Text
generateProxy schema rec = case recordKind rec of
  NewtypeOver _ -> Just $ T.unlines
    [ T.toLower (recordName rec) <> "API :: Proxy " <> recordName rec <> "API"
    , T.toLower (recordName rec) <> "API = Proxy"
    ]
  RecordType
    | recordName rec == "InventoryResponse" -> Nothing
    | isNestedRecord schema rec -> Nothing
    | otherwise -> Just $ T.unlines
      [ T.toLower (recordName rec) <> "API :: Proxy " <> recordName rec <> "API"
      , T.toLower (recordName rec) <> "API = Proxy"
      ]