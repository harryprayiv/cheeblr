-- FILE: ./backend/src/Server.hs
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}

module Server where

import API.Inventory
import Control.Exception (SomeException, try)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (encode)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Database.PostgreSQL.Simple
import Data.Pool (Pool)
import Data.Text (Text, pack)
import qualified Data.Text as T
import Servant
import DB.Database (getAllMenuItems, insertMenuItem, updateExistingMenuItem, deleteMenuItem)
import Types.Inventory
import Types.Auth (capabilitiesForRole, auRole, UserCapabilities(..))
import Auth.Simple (lookupUser)
import Data.UUID (UUID)

import API.Transaction ()
import qualified Data.Pool as Pool
import Server.Transaction (posServerImpl)

inventoryServer :: Pool.Pool Connection -> Server InventoryAPI
inventoryServer pool =
  getInventory
    :<|> addMenuItem
    :<|> updateMenuItem
    :<|> deleteInventoryItem
  where
    -- | GET /inventory - anyone can view, capabilities tell frontend what else they can do
    getInventory :: Maybe Text -> Handler InventoryResponse
    getInventory mUserId = do
      let user = lookupUser mUserId
      let caps = capabilitiesForRole (auRole user)
      
      liftIO $ putStrLn $ "GET /inventory - User: " ++ show (auRole user)
      
      inventory <- liftIO $ getAllMenuItems pool
      liftIO $ putStrLn "Sending inventory response with capabilities"
      liftIO $ LBS.putStrLn $ encode $ InventoryData inventory caps
      return $ InventoryData inventory caps

    -- | POST /inventory - requires create permission
    addMenuItem :: Maybe Text -> MenuItem -> Handler InventoryResponse
    addMenuItem mUserId item = do
      let user = lookupUser mUserId
      let caps = capabilitiesForRole (auRole user)
      
      liftIO $ putStrLn $ "POST /inventory - User: " ++ show (auRole user)
      
      -- Check permission
      if not (capCanCreateItem caps)
        then do
          liftIO $ putStrLn "Permission denied: cannot create items"
          throwError err403 { errBody = "You don't have permission to create items" }
        else do
          liftIO $ putStrLn "Received request to add menu item"
          liftIO $ print item
          result <- liftIO $ try $ do
            insertMenuItem pool item
            return $ Message (pack "Item added successfully")
          case result of
            Right msg -> return msg
            Left (e :: SomeException) -> do
              let errMsg = pack $ "Error inserting item: " <> show e
              liftIO $ putStrLn $ "Error: " ++ show e
              return $ Message errMsg

    -- | PUT /inventory - requires edit permission
    updateMenuItem :: Maybe Text -> MenuItem -> Handler InventoryResponse
    updateMenuItem mUserId item = do
      let user = lookupUser mUserId
      let caps = capabilitiesForRole (auRole user)
      
      liftIO $ putStrLn $ "PUT /inventory - User: " ++ show (auRole user)
      
      -- Check permission
      if not (capCanEditItem caps)
        then do
          liftIO $ putStrLn "Permission denied: cannot edit items"
          throwError err403 { errBody = "You don't have permission to edit items" }
        else do
          liftIO $ putStrLn "Received request to update menu item"
          liftIO $ print item
          result <- liftIO $ try $ do
            updateExistingMenuItem pool item
            return $ Message (pack "Item updated successfully")
          case result of
            Right msg -> return msg
            Left (e :: SomeException) -> do
              let errMsg = pack $ "Error updating item: " <> show e
              return $ Message errMsg

    -- | DELETE /inventory/:sku - requires delete permission
    deleteInventoryItem :: Maybe Text -> UUID -> Handler InventoryResponse
    deleteInventoryItem mUserId uuid = do
      let user = lookupUser mUserId
      let caps = capabilitiesForRole (auRole user)
      
      liftIO $ putStrLn $ "DELETE /inventory/" ++ show uuid ++ " - User: " ++ show (auRole user)
      
      -- Check permission
      if not (capCanDeleteItem caps)
        then do
          liftIO $ putStrLn "Permission denied: cannot delete items"
          throwError err403 { errBody = "You don't have permission to delete items" }
        else deleteMenuItem pool uuid

combinedServer :: Pool Connection -> Server API
combinedServer pool =
  inventoryServer pool
    :<|> posServerImpl pool