{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Codegen.Generate.Server
  ( generateServerModule
  ) where

import Codegen.Schema
import Codegen.Generate.Common (GeneratedModule(..), moduleNameToPath)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe)

generateServerModule :: DomainSchema -> GeneratedModule
generateServerModule schema = GeneratedModule
  { modulePath = moduleNameToPath (schemaServerModuleName schema)
  , moduleContent = T.unlines $ filter (not . T.null)
      [ generatePragmas
      , ""
      , generateModuleDecl schema
      , ""
      , generateImports schema
      , ""
      , "-- ============================================"
      , "-- Server Implementation"
      , "-- ============================================"
      , ""
      , generateServerImpl schema
      ]
  }

-- Helper to get server module name
schemaServerModuleName :: DomainSchema -> Text
schemaServerModuleName schema = 
  T.replace "API" "Server" (schemaApiModuleName schema) <> ".Generated"

generatePragmas :: Text
generatePragmas = T.unlines
  [ "{-# LANGUAGE ScopedTypeVariables #-}"
  , "{-# LANGUAGE TypeApplications #-}"
  , "{-# LANGUAGE OverloadedStrings #-}"
  ]

generateModuleDecl :: DomainSchema -> Text
generateModuleDecl schema = 
  "module " <> schemaServerModuleName schema <> " where"

generateImports :: DomainSchema -> Text
generateImports schema = T.unlines
  [ "import Control.Exception (SomeException, try)"
  , "import Control.Monad.IO.Class (liftIO)"
  , "import Data.Aeson (encode)"
  , "import qualified Data.ByteString.Lazy.Char8 as LBS"
  , "import Data.Pool (Pool)"
  , "import Data.Text (pack)"
  , "import Data.UUID (UUID)"
  , "import Database.PostgreSQL.Simple (Connection)"
  , "import Servant"
  , ""
  , "import " <> schemaModuleName schema
  , "import " <> schemaApiModuleName schema
  , "import " <> schemaDbModuleName schema
  ]

generateServerImpl :: DomainSchema -> Text
generateServerImpl schema = 
  case findMainRecord schema of
    Nothing -> "-- No main record found to generate server for"
    Just rec -> generateMainServer schema rec

findMainRecord :: DomainSchema -> Maybe RecordDef
findMainRecord schema = 
  case filter isCollectionType (schemaRecords schema) of
    (r:_) -> Just r
    [] -> Nothing
  where
    isCollectionType r = case recordKind r of
      NewtypeOver _ -> True
      _ -> False

generateMainServer :: DomainSchema -> RecordDef -> Text
generateMainServer schema rec@RecordDef{..} = 
  let itemName = case recordKind of
        NewtypeOver inner -> extractItemName inner
        _ -> recordName
      serverName = T.toLower recordName <> "Server"
      apiName = recordName <> "API"
      responseType = findResponseType schema itemName
  in T.unlines
    [ "-- | Server implementation for " <> recordName <> "API"
    , serverName <> " :: Pool Connection -> Server " <> apiName
    , serverName <> " pool ="
    , "  get" <> recordName
    , "    :<|> add" <> itemName
    , "    :<|> update" <> itemName
    , "    :<|> delete" <> itemName <> " pool"
    , "  where"
    , ""
    , "    -- GET all items"
    , "    get" <> recordName <> " :: Handler " <> responseType
    , "    get" <> recordName <> " = do"
    , "      " <> T.toLower recordName <> " <- liftIO $ getAll" <> itemName <> "s pool"
    , "      liftIO $ putStrLn \"Sending " <> T.toLower recordName <> " response:\""
    , "      liftIO $ LBS.putStrLn $ encode $ " <> getDataCtor responseType <> " " <> T.toLower recordName
    , "      return $ " <> getDataCtor responseType <> " " <> T.toLower recordName
    , ""
    , "    -- POST new item"
    , "    add" <> itemName <> " :: " <> itemName <> " -> Handler " <> responseType
    , "    add" <> itemName <> " item = do"
    , "      liftIO $ putStrLn \"Received request to add " <> T.toLower itemName <> "\""
    , "      liftIO $ print item"
    , "      result <- liftIO $ try @SomeException $ do"
    , "        insert" <> itemName <> " pool item"
    , "        let response = Message (pack \"Item added successfully\")"
    , "        liftIO $ putStrLn $ \"Sending response: \" ++ show (encode response)"
    , "        return response"
    , "      case result of"
    , "        Right msg -> return msg"
    , "        Left (e :: SomeException) -> do"
    , "          let errMsg = pack $ \"Error inserting item: \" <> show e"
    , "          liftIO $ putStrLn $ \"Error: \" ++ show e"
    , "          let response = Message errMsg"
    , "          liftIO $ putStrLn $ \"Sending error response: \" ++ show (encode response)"
    , "          return response"
    , ""
    , "    -- PUT update item"
    , "    update" <> itemName <> " :: " <> itemName <> " -> Handler " <> responseType
    , "    update" <> itemName <> " item = do"
    , "      liftIO $ putStrLn \"Received request to update " <> T.toLower itemName <> "\""
    , "      liftIO $ print item"
    , "      result <- liftIO $ try @SomeException $ do"
    , "        updateExisting" <> itemName <> " pool item"
    , "        let response = Message (pack \"Item updated successfully\")"
    , "        liftIO $ putStrLn $ \"Sending response: \" ++ show (encode response)"
    , "        return response"
    , "      case result of"
    , "        Right msg -> return msg"
    , "        Left (e :: SomeException) -> do"
    , "          let errMsg = pack $ \"Error updating item: \" <> show e"
    , "          let response = Message errMsg"
    , "          liftIO $ putStrLn $ \"Sending error response: \" ++ show (encode response)"
    , "          return response"
    ]

extractItemName :: Text -> Text
extractItemName innerType = 
  case T.words innerType of
    [_, name] -> name
    _ -> innerType

findResponseType :: DomainSchema -> Text -> Text
findResponseType schema _ =
  let responseTypes = filter isResponseType (schemaRecords schema)
  in case responseTypes of
    (r:_) -> recordName r
    [] -> "InventoryResponse"
  where
    isResponseType r = "Response" `T.isSuffixOf` recordName r

getDataCtor :: Text -> Text
getDataCtor "InventoryResponse" = "InventoryData"
getDataCtor name = name