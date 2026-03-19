{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Server where

import API.Inventory
import API.OpenApi (CheeblrAPI, cheeblrOpenApi)
import Auth.Simple (lookupUser)
import Control.Monad.IO.Class (liftIO)
import Data.Morpheus (interpreter)
import Data.Morpheus.Types (GQLRequest, GQLResponse)
import Data.Text (Text, pack)
import Data.UUID (UUID)
import Effectful (Eff, IOE, runEff)
import Effectful.Error.Static (Error, runErrorNoCallStack)
import Servant hiding (throwError)
import qualified Servant ( throwError )

import DB.Database (DBPool)
import Effect.InventoryDb
import GraphQL.Resolvers (rootResolver)
import Server.Transaction (posServerImpl)
import Types.Auth
  ( UserCapabilities (..)
  , capabilitiesForRole
  , auRole
  , auUserId
  , auUserName
  , SessionResponse (..)
  )
import Types.Inventory

runInvEff :: DBPool -> Eff '[InventoryDb, Error ServerError, IOE] a -> Handler a
runInvEff pool action = do
  result <- liftIO . runEff . runErrorNoCallStack @ServerError . runInventoryDbIO pool $ action
  either Servant.throwError pure result

combinedServer :: DBPool -> Server CheeblrAPI
combinedServer pool =
  inventoryServer pool
    :<|> posServerImpl pool
    :<|> pure cheeblrOpenApi

inventoryServer :: DBPool -> Server InventoryAPI
inventoryServer pool =
  getInventory
    :<|> addInventoryItem
    :<|> updateInventoryItem
    :<|> deleteInventoryItem
    :<|> getSession
    :<|> graphqlInventory
  where
    getInventory :: Maybe Text -> Handler Inventory
    getInventory mUserId = do
      let user = lookupUser mUserId
      liftIO $ putStrLn $ "GET /inventory - User: " ++ show (auRole user)
      runInvEff pool getAllMenuItems

    addInventoryItem :: Maybe Text -> MenuItem -> Handler MutationResponse
    addInventoryItem mUserId item = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
      liftIO $ putStrLn $ "POST /inventory - User: " ++ show (auRole user)
      if not (capCanCreateItem caps)
        then Servant.throwError err403 { errBody = "You don't have permission to create items" }
        else runInvEff pool $ do
          result <- Effect.InventoryDb.insertMenuItem item
          pure $ case result of
            Right ()  -> MutationResponse True "Item added successfully"
            Left e    -> MutationResponse False (pack $ "Error inserting item: " <> show e)

    updateInventoryItem :: Maybe Text -> MenuItem -> Handler MutationResponse
    updateInventoryItem mUserId item = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
      liftIO $ putStrLn $ "PUT /inventory - User: " ++ show (auRole user)
      if not (capCanEditItem caps)
        then Servant.throwError err403 { errBody = "You don't have permission to edit items" }
        else runInvEff pool $ do
          result <- Effect.InventoryDb.updateMenuItem item
          pure $ case result of
            Right ()  -> MutationResponse True "Item updated successfully"
            Left e    -> MutationResponse False (pack $ "Error updating item: " <> show e)

    deleteInventoryItem :: Maybe Text -> UUID -> Handler MutationResponse
    deleteInventoryItem mUserId uuid = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
      liftIO $ putStrLn $
        "DELETE /inventory/" ++ show uuid ++ " - User: " ++ show (auRole user)
      if not (capCanDeleteItem caps)
        then Servant.throwError err403 { errBody = "You don't have permission to delete items" }
        else do
          response <- runInvEff pool (Effect.InventoryDb.deleteMenuItem uuid)
          if success response
            then pure response
            else Servant.throwError err404 { errBody = "Item not found" }

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