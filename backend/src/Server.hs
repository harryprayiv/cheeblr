{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications  #-}

module Server where

import API.Inventory
import API.OpenApi (CheeblrAPI, cheeblrOpenApi)
import Auth.Simple (lookupUser)
import Control.Monad.IO.Class (liftIO)
import Data.Morpheus (interpreter)
import Data.Morpheus.Types (GQLRequest, GQLResponse)
import Data.Text (Text, pack)
import qualified Data.Text as T
import Data.UUID (UUID)
import Effectful (Eff, IOE, runEff)
import Effectful.Error.Static (Error, runErrorNoCallStack)
import Katip (LogEnv)
import Servant hiding (throwError)
import qualified Servant ( throwError )

import DB.Database (DBPool)
import Effect.InventoryDb
import GraphQL.Resolvers (rootResolver)
import Logging
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

combinedServer :: DBPool -> LogEnv -> Server CheeblrAPI
combinedServer pool logEnv =
  inventoryServer pool logEnv
    :<|> posServerImpl pool logEnv
    :<|> pure cheeblrOpenApi

inventoryServer :: DBPool -> LogEnv -> Server InventoryAPI
inventoryServer pool logEnv =
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
          lctx = makeLogCtx logEnv mUserId (auRole user)
      liftIO $ do
        logHttpRequest logEnv "GET" "/inventory" (fromMaybeT mUserId)
        logInventoryRead lctx
      runInvEff pool getAllMenuItems

    addInventoryItem :: Maybe Text -> MenuItem -> Handler MutationResponse
    addInventoryItem mUserId item = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
          lctx = makeLogCtx logEnv mUserId (auRole user)
          skuT = T.pack (show (Types.Inventory.sku item))
      liftIO $ logHttpRequest logEnv "POST" "/inventory" (fromMaybeT mUserId)
      if not (capCanCreateItem caps)
        then do
          liftIO $ logAuthDenied logEnv (fromMaybeT mUserId) "capCanCreateItem"
          Servant.throwError err403 { errBody = "You don't have permission to create items" }
        else runInvEff pool $ do
          result <- Effect.InventoryDb.insertMenuItem item
          liftIO $ case result of
            Right () -> logInventoryCreate lctx skuT LogSuccess
            Left  e  -> logInventoryCreate lctx skuT
                          (LogFailure (T.pack $ "insertMenuItem: " <> show e))
          pure $ case result of
            Right () -> MutationResponse True  "Item added successfully"
            Left  e  -> MutationResponse False (pack $ "Error inserting item: " <> show e)

    updateInventoryItem :: Maybe Text -> MenuItem -> Handler MutationResponse
    updateInventoryItem mUserId item = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
          lctx = makeLogCtx logEnv mUserId (auRole user)
          skuT = T.pack (show (Types.Inventory.sku item))
      liftIO $ logHttpRequest logEnv "PUT" "/inventory" (fromMaybeT mUserId)
      if not (capCanEditItem caps)
        then do
          liftIO $ logAuthDenied logEnv (fromMaybeT mUserId) "capCanEditItem"
          Servant.throwError err403 { errBody = "You don't have permission to edit items" }
        else runInvEff pool $ do
          result <- Effect.InventoryDb.updateMenuItem item
          liftIO $ case result of
            Right () -> logInventoryUpdate lctx skuT LogSuccess
            Left  e  -> logInventoryUpdate lctx skuT
                          (LogFailure (T.pack $ "updateMenuItem: " <> show e))
          pure $ case result of
            Right () -> MutationResponse True  "Item updated successfully"
            Left  e  -> MutationResponse False (pack $ "Error updating item: " <> show e)

    deleteInventoryItem :: Maybe Text -> UUID -> Handler MutationResponse
    deleteInventoryItem mUserId uuid = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
          lctx = makeLogCtx logEnv mUserId (auRole user)
          skuT = T.pack (show uuid)
      liftIO $ logHttpRequest logEnv "DELETE" ("/inventory/" <> skuT) (fromMaybeT mUserId)
      if not (capCanDeleteItem caps)
        then do
          liftIO $ logAuthDenied logEnv (fromMaybeT mUserId) "capCanDeleteItem"
          Servant.throwError err403 { errBody = "You don't have permission to delete items" }
        else do
          response <- runInvEff pool (Effect.InventoryDb.deleteMenuItem uuid)
          if success response
            then do
              liftIO $ logInventoryDelete lctx skuT LogSuccess
              pure response
            else do
              liftIO $ logInventoryDelete lctx skuT (LogFailure (message response))
              Servant.throwError err404 { errBody = "Item not found" }

    getSession :: Maybe Text -> Handler SessionResponse
    getSession mUserId = do
      let user = lookupUser mUserId
          lctx = makeLogCtx logEnv mUserId (auRole user)
      liftIO $ do
        logHttpRequest logEnv "GET" "/session" (fromMaybeT mUserId)
        logSessionAccess lctx
      pure SessionResponse
        { sessionUserId       = auUserId user
        , sessionUserName     = auUserName user
        , sessionRole         = auRole user
        , sessionCapabilities = capabilitiesForRole (auRole user)
        }

    graphqlInventory :: Maybe Text -> GQLRequest -> Handler GQLResponse
    graphqlInventory mUserId req = do
      liftIO $ logHttpRequest logEnv "POST" "/graphql/inventory" (fromMaybeT mUserId)
      liftIO $ interpreter (rootResolver pool mUserId) req

-- | Safely extract a user ID string from the optional header.
fromMaybeT :: Maybe Text -> Text
fromMaybeT = maybe "anonymous" id