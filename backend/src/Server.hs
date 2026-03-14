{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Server where

import API.Inventory
import API.OpenApi (CheeblrAPI, cheeblrOpenApi)
import Auth.Simple (lookupUser)
import Control.Exception (SomeException, try)
import Control.Monad.IO.Class (liftIO)
import Data.Morpheus (interpreter)
import Data.Morpheus.Types (GQLRequest, GQLResponse)
import Data.Pool (Pool)
import qualified Data.Pool as Pool
import Data.Text (Text, pack)
import Data.UUID (UUID)
import Database.PostgreSQL.Simple
import DB.Database (getAllMenuItems, insertMenuItem, updateExistingMenuItem, deleteMenuItem)
import GraphQL.Resolvers (rootResolver)
import Servant
import Server.Transaction (posServerImpl)
import Types.Auth
  ( capabilitiesForRole, auRole, auUserId, auUserName
  , UserCapabilities (..), SessionResponse (..)
  )
import Types.Inventory

combinedServer :: Pool Connection -> Server CheeblrAPI
combinedServer pool
  =    inventoryServer pool
  :<|> posServerImpl pool
  :<|> pure cheeblrOpenApi

inventoryServer :: Pool.Pool Connection -> Server InventoryAPI
inventoryServer pool =
  getInventory
    :<|> addMenuItem
    :<|> updateMenuItem
    :<|> deleteInventoryItem
    :<|> getSession
    :<|> graphqlInventory
  where

    getInventory :: Maybe Text -> Handler Inventory
    getInventory mUserId = do
      let user = lookupUser mUserId
      liftIO $ putStrLn $ "GET /inventory - User: " ++ show (auRole user)
      liftIO $ getAllMenuItems pool

    addMenuItem :: Maybe Text -> MenuItem -> Handler MutationResponse
    addMenuItem mUserId item = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
      liftIO $ putStrLn $ "POST /inventory - User: " ++ show (auRole user)
      if not (capCanCreateItem caps)
        then throwError err403 { errBody = "You don't have permission to create items" }
        else do
          result <- liftIO $ try $ insertMenuItem pool item
          pure $ case result of
            Right _                   -> MutationResponse True "Item added successfully"
            Left (e :: SomeException) -> MutationResponse False (pack $ "Error inserting item: " <> show e)

    updateMenuItem :: Maybe Text -> MenuItem -> Handler MutationResponse
    updateMenuItem mUserId item = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
      liftIO $ putStrLn $ "PUT /inventory - User: " ++ show (auRole user)
      if not (capCanEditItem caps)
        then throwError err403 { errBody = "You don't have permission to edit items" }
        else do
          result <- liftIO $ try $ updateExistingMenuItem pool item
          pure $ case result of
            Right _                   -> MutationResponse True "Item updated successfully"
            Left (e :: SomeException) -> MutationResponse False (pack $ "Error updating item: " <> show e)

    deleteInventoryItem :: Maybe Text -> UUID -> Handler MutationResponse
    deleteInventoryItem mUserId uuid = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
      liftIO $ putStrLn $
        "DELETE /inventory/" ++ show uuid ++ " - User: " ++ show (auRole user)
      if not (capCanDeleteItem caps)
        then throwError err403 { errBody = "You don't have permission to delete items" }
        else deleteMenuItem pool uuid

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

    graphqlInventory :: Maybe Text -> GQLRequest -> Handler GQLResponse
    graphqlInventory mUserId req = do
      liftIO $ putStrLn $
        "POST /graphql/inventory - User: " ++ show (auRole (lookupUser mUserId))
      liftIO $ interpreter (rootResolver pool mUserId) req