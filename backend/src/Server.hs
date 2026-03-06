{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}

module Server where

import API.Inventory
import Control.Exception (SomeException, try)
import Control.Monad.IO.Class (liftIO)
import Database.PostgreSQL.Simple
import Data.Pool (Pool)
import Data.Text (Text, pack)
import Servant
import DB.Database (getAllMenuItems, insertMenuItem, updateExistingMenuItem, deleteMenuItem)
import Types.Inventory
import Types.Auth
    ( capabilitiesForRole, auRole, auUserId, auUserName
    , UserCapabilities(..), SessionResponse(..)
    )
import Auth.Simple (lookupUser)
import Data.UUID (UUID)

import qualified Data.Pool as Pool
import Server.Transaction (posServerImpl)

inventoryServer :: Pool.Pool Connection -> Server InventoryAPI
inventoryServer pool =
  getInventory
    :<|> addMenuItem
    :<|> updateMenuItem
    :<|> deleteInventoryItem
    :<|> getSession
  where
    -- GET /inventory — plain JSON array, no capabilities bundled in
    getInventory :: Maybe Text -> Handler Inventory
    getInventory mUserId = do
      let user = lookupUser mUserId
      liftIO $ putStrLn $ "GET /inventory - User: " ++ show (auRole user)
      liftIO $ getAllMenuItems pool

    -- POST /inventory
    addMenuItem :: Maybe Text -> MenuItem -> Handler MutationResponse
    addMenuItem mUserId item = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
      liftIO $ putStrLn $ "POST /inventory - User: " ++ show (auRole user)
      if not (capCanCreateItem caps)
        then throwError err403 { errBody = "You don't have permission to create items" }
        else do
          liftIO $ putStrLn "Received request to add menu item"
          result <- liftIO $ try $ insertMenuItem pool item
          pure $ case result of
            Right _             -> MutationResponse True "Item added successfully"
            Left (e :: SomeException) ->
              MutationResponse False (pack $ "Error inserting item: " <> show e)

    -- PUT /inventory
    updateMenuItem :: Maybe Text -> MenuItem -> Handler MutationResponse
    updateMenuItem mUserId item = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
      liftIO $ putStrLn $ "PUT /inventory - User: " ++ show (auRole user)
      if not (capCanEditItem caps)
        then throwError err403 { errBody = "You don't have permission to edit items" }
        else do
          liftIO $ putStrLn "Received request to update menu item"
          result <- liftIO $ try $ updateExistingMenuItem pool item
          pure $ case result of
            Right _             -> MutationResponse True "Item updated successfully"
            Left (e :: SomeException) ->
              MutationResponse False (pack $ "Error updating item: " <> show e)

    -- DELETE /inventory/:sku
    deleteInventoryItem :: Maybe Text -> UUID -> Handler MutationResponse
    deleteInventoryItem mUserId uuid = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
      liftIO $ putStrLn $
        "DELETE /inventory/" ++ show uuid ++ " - User: " ++ show (auRole user)
      if not (capCanDeleteItem caps)
        then throwError err403 { errBody = "You don't have permission to delete items" }
        else deleteMenuItem pool uuid

    -- GET /session — capabilities for the identified user
    getSession :: Maybe Text -> Handler SessionResponse
    getSession mUserId = do
      let user = lookupUser mUserId
      liftIO $ putStrLn $ "GET /session - User: " ++ show (auRole user)
      pure SessionResponse
        { sessionUserId       = auUserId user
        , sessionUserName     = auUserName user
        , sessionRole         = auRole user
        , sessionCapabilities = capabilitiesForRole (auRole user)
        }

combinedServer :: Pool Connection -> Server API
combinedServer pool =
  inventoryServer pool
    :<|> posServerImpl pool