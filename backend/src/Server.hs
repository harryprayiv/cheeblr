{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Server where

import API.Admin (AdminAPI)
import API.Feed (FeedAPI)
import API.Inventory
import API.Manager (ManagerAPI)
import API.OpenApi (CheeblrAPI, cheeblrOpenApi)
import API.Stock (StockAPI)
import Auth.Session (SessionContext (..), resolveSession)
import Control.Monad.IO.Class (liftIO)
import Data.Morpheus (interpreter)
import Data.Morpheus.Types (GQLRequest, GQLResponse)
import Data.Text (Text, pack)
import qualified Data.Text as T
import Data.UUID (UUID)
import Effectful (Eff, IOE, runEff)
import Effectful.Error.Static (Error, runErrorNoCallStack)
import Servant hiding (throwError)
import qualified Servant (throwError)

import DB.Database (DBPool)
import Effect.InventoryDb
import GraphQL.Resolvers (rootResolver)
import Logging
import Server.Admin (adminServerImpl)
import Server.Auth (authServerImpl)
import Server.Env (AppEnv (..))
import Server.Feed (feedServerImpl)
import Server.Manager (managerServerImpl)
import Server.Stock (stockServerImpl)
import Server.Transaction (posServerImpl)
import Types.Auth (
  AuthenticatedUser (..),
  SessionResponse (..),
  UserCapabilities (..),
  auRole,
  auUserId,
  auUserName,
  capabilitiesForRole,
 )
import Types.Inventory

-- FeedAPI is first so its public routes are checked before the authenticated
-- CheeblrAPI. The /xrpc/..., /lexicons/..., and /feed/... prefixes do not
-- overlap with any existing route.
type FullAPI = FeedAPI :<|> CheeblrAPI :<|> AdminAPI :<|> ManagerAPI :<|> StockAPI

fullAPI :: Proxy FullAPI
fullAPI = Proxy

fullServer :: AppEnv -> Server FullAPI
fullServer env =
  feedServerImpl env
    :<|> combinedServer env
    :<|> adminServerImpl env
    :<|> managerServerImpl env
    :<|> stockServerImpl env

runInvEff :: DBPool -> Eff '[InventoryDb, Error ServerError, IOE] a -> Handler a
runInvEff pool action = do
  result <- liftIO . runEff . runErrorNoCallStack @ServerError . runInventoryDbIO pool $ action
  either Servant.throwError pure result

combinedServer :: AppEnv -> Server CheeblrAPI
combinedServer env =
  inventoryServer env
    :<|> posServerImpl env
    :<|> authServerImpl (envDbPool env) (envLogEnv env)
    :<|> pure cheeblrOpenApi

inventoryServer :: AppEnv -> Server InventoryAPI
inventoryServer env =
  getInventory
    :<|> addInventoryItem
    :<|> updateInventoryItem
    :<|> deleteInventoryItem
    :<|> getSession
    :<|> graphqlInventory
  where
    pool = envDbPool env
    logEnv = envLogEnv env

    auth :: Maybe Text -> Handler AuthenticatedUser
    auth mHeader = scUser <$> resolveSession pool mHeader

    getInventory :: Maybe Text -> Handler Inventory
    getInventory mHeader = do
      user <- auth mHeader
      let lctx = makeLogCtx logEnv (Just (T.pack (show (auUserId user)))) (auRole user)
      liftIO $ do
        logHttpRequest logEnv "GET" "/inventory" (T.pack (show (auUserId user)))
        logInventoryRead lctx
      runInvEff pool getAllMenuItems

    addInventoryItem :: Maybe Text -> MenuItem -> Handler MutationResponse
    addInventoryItem mHeader item = do
      user <- auth mHeader
      let
        caps = capabilitiesForRole (auRole user)
        lctx = makeLogCtx logEnv (Just (T.pack (show (auUserId user)))) (auRole user)
        skuT = T.pack (show (Types.Inventory.sku item))
      liftIO $ logHttpRequest logEnv "POST" "/inventory" (T.pack (show (auUserId user)))
      if not (capCanCreateItem caps)
        then do
          liftIO $ logAuthDenied logEnv (T.pack (show (auUserId user))) "capCanCreateItem"
          Servant.throwError err403 {errBody = "You don't have permission to create items"}
        else runInvEff pool $ do
          result <- Effect.InventoryDb.insertMenuItem item
          liftIO $ case result of
            Right () -> logInventoryCreate lctx skuT LogSuccess
            Left e ->
              logInventoryCreate
                lctx
                skuT
                (LogFailure (T.pack $ "insertMenuItem: " <> show e))
          pure $ case result of
            Right () -> MutationResponse True "Item added successfully"
            Left e -> MutationResponse False (pack $ "Error inserting item: " <> show e)

    updateInventoryItem :: Maybe Text -> MenuItem -> Handler MutationResponse
    updateInventoryItem mHeader item = do
      user <- auth mHeader
      let
        caps = capabilitiesForRole (auRole user)
        lctx = makeLogCtx logEnv (Just (T.pack (show (auUserId user)))) (auRole user)
        skuT = T.pack (show (Types.Inventory.sku item))
      liftIO $ logHttpRequest logEnv "PUT" "/inventory" (T.pack (show (auUserId user)))
      if not (capCanEditItem caps)
        then do
          liftIO $ logAuthDenied logEnv (T.pack (show (auUserId user))) "capCanEditItem"
          Servant.throwError err403 {errBody = "You don't have permission to edit items"}
        else runInvEff pool $ do
          result <- Effect.InventoryDb.updateMenuItem item
          liftIO $ case result of
            Right () -> logInventoryUpdate lctx skuT LogSuccess
            Left e ->
              logInventoryUpdate
                lctx
                skuT
                (LogFailure (T.pack $ "updateMenuItem: " <> show e))
          pure $ case result of
            Right () -> MutationResponse True "Item updated successfully"
            Left e -> MutationResponse False (pack $ "Error updating item: " <> show e)

    deleteInventoryItem :: Maybe Text -> UUID -> Handler MutationResponse
    deleteInventoryItem mHeader uuid = do
      user <- auth mHeader
      let
        caps = capabilitiesForRole (auRole user)
        lctx = makeLogCtx logEnv (Just (T.pack (show (auUserId user)))) (auRole user)
        skuT = T.pack (show uuid)
      liftIO $ logHttpRequest logEnv "DELETE" ("/inventory/" <> skuT) (T.pack (show (auUserId user)))
      if not (capCanDeleteItem caps)
        then do
          liftIO $ logAuthDenied logEnv (T.pack (show (auUserId user))) "capCanDeleteItem"
          Servant.throwError err403 {errBody = "You don't have permission to delete items"}
        else do
          response <- runInvEff pool (Effect.InventoryDb.deleteMenuItem uuid)
          if success response
            then do
              liftIO $ logInventoryDelete lctx skuT LogSuccess
              pure response
            else do
              liftIO $ logInventoryDelete lctx skuT (LogFailure (message response))
              Servant.throwError err404 {errBody = "Item not found"}

    getSession :: Maybe Text -> Handler SessionResponse
    getSession mHeader = do
      user <- auth mHeader
      let lctx = makeLogCtx logEnv (Just (T.pack (show (auUserId user)))) (auRole user)
      liftIO $ do
        logHttpRequest logEnv "GET" "/session" (T.pack (show (auUserId user)))
        logSessionAccess lctx
      pure
        SessionResponse
          { sessionUserId = auUserId user
          , sessionUserName = auUserName user
          , sessionRole = auRole user
          , sessionCapabilities = capabilitiesForRole (auRole user)
          }

    graphqlInventory :: Maybe Text -> GQLRequest -> Handler GQLResponse
    graphqlInventory mHeader req = do
      user <- auth mHeader
      liftIO $ logHttpRequest logEnv "POST" "/graphql/inventory" (T.pack (show (auUserId user)))
      liftIO $ interpreter (rootResolver pool user) req