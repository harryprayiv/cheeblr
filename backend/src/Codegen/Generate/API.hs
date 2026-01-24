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
  { modulePath = moduleNameToPath (schemaApiModuleName schema)
  , moduleContent = T.unlines $ filter (not . T.null)
      [ generatePragmas
      , ""
      , generateModuleDecl schema
      , ""
      , generateImports schema
      , ""
      , "-- ============================================"
      , "-- API Type Definitions"
      , "-- ============================================"
      , ""
      , generateApiTypes schema
      , ""
      , "-- ============================================"
      , "-- Proxy Definitions"
      , "-- ============================================"
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
  "module " <> schemaApiModuleName schema <> " where"

generateImports :: DomainSchema -> Text
generateImports schema = T.unlines
  [ "import Data.UUID (UUID)"
  , "import Servant"
  , "import " <> schemaModuleName schema
  ]

generateApiTypes :: DomainSchema -> Text
generateApiTypes schema = T.intercalate "\n\n" $ mapMaybe (generateApiType schema) (schemaRecords schema)

generateApiType :: DomainSchema -> RecordDef -> Maybe Text
generateApiType schema rec@RecordDef{..} = case recordKind of
  NewtypeOver _ -> Just $ generateCollectionApi schema rec
  RecordType
    | recordName == "InventoryResponse" -> Nothing
    | isNestedRecord schema rec -> Nothing
    | otherwise -> Just $ generateCrudApi schema rec

isNestedRecord :: DomainSchema -> RecordDef -> Bool
isNestedRecord schema RecordDef{..} =
  any (referencesThis . recordFields) (schemaRecords schema)
  where
    referencesThis fields = any (references recordName) fields
    references name f = case fieldType f of
      FNested n -> n == name
      _ -> False

generateCrudApi :: DomainSchema -> RecordDef -> Text
generateCrudApi schema RecordDef{..} = T.unlines
  [ "-- | CRUD API for " <> recordName
  , "type " <> recordName <> "API ="
  , "  \"" <> endpoint <> "\" :> Get '[JSON] " <> responseType
  , "    :<|> \"" <> endpoint <> "\" :> ReqBody '[JSON] " <> recordName <> " :> Post '[JSON] " <> responseType
  , "    :<|> \"" <> endpoint <> "\" :> ReqBody '[JSON] " <> recordName <> " :> Put '[JSON] " <> responseType
  , "    :<|> \"" <> endpoint <> "\" :> Capture \"" <> pkField <> "\" UUID :> Delete '[JSON] " <> responseType
  ]
  where
    endpoint = T.toLower recordName
    responseType = findResponseType schema recordName
    pkField = findPrimaryKeyField recordFields

generateCollectionApi :: DomainSchema -> RecordDef -> Text
generateCollectionApi schema RecordDef{..} = case recordKind of
  NewtypeOver innerType -> 
    let itemName = extractItemName innerType
        endpoint = T.toLower recordName
        responseType = findResponseType schema itemName
    in T.unlines
      [ "-- | Collection API for " <> recordName
      , "type " <> recordName <> "API ="
      , "  \"" <> endpoint <> "\" :> Get '[JSON] " <> responseType
      , "    :<|> \"" <> endpoint <> "\" :> ReqBody '[JSON] " <> itemName <> " :> Post '[JSON] " <> responseType
      , "    :<|> \"" <> endpoint <> "\" :> ReqBody '[JSON] " <> itemName <> " :> Put '[JSON] " <> responseType
      , "    :<|> \"" <> endpoint <> "\" :> Capture \"sku\" UUID :> Delete '[JSON] " <> responseType
      ]
  _ -> ""

extractItemName :: Text -> Text
extractItemName innerType = 
  -- "V.Vector MenuItem" -> "MenuItem"
  case T.words innerType of
    [_, name] -> name
    _ -> innerType

findResponseType :: DomainSchema -> Text -> Text
findResponseType schema name =
  -- Look for a response wrapper type
  let responseTypes = filter isResponseType (schemaRecords schema)
  in case responseTypes of
    (r:_) -> recordName r
    [] -> name
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
generateProxies schema = T.intercalate "\n\n" $ mapMaybe generateProxy (schemaRecords schema)
  where
    generateProxy RecordDef{..} = case recordKind of
      NewtypeOver _ -> Just $ T.unlines
        [ T.toLower recordName <> "API :: Proxy " <> recordName <> "API"
        , T.toLower recordName <> "API = Proxy"
        ]
      RecordType
        | recordName == "InventoryResponse" -> Nothing
        | isNestedRecord schema (RecordDef recordName recordKind recordFields recordDescription recordDeriving) -> Nothing
        | otherwise -> Just $ T.unlines
          [ T.toLower recordName <> "API :: Proxy " <> recordName <> "API"
          , T.toLower recordName <> "API = Proxy"
          ]