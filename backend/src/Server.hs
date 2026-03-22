{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Server where

import API.Inventory
import API.OpenApi (CheeblrAPI, cheeblrOpenApi)
import Auth.Session (SessionContext (..), resolveSession, extractBearer)
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
import qualified Servant (throwError)

import DB.Database (DBPool)
import Effect.InventoryDb
import GraphQL.Resolvers (rootResolver)
import Logging
import Server.Auth (authServerImpl)
import Server.Transaction (posServerImpl)
import Types.Auth
  ( AuthenticatedUser (..)
  , UserCapabilities (..)
  , capabilitiesForRole
  , auRole
  , auUserId
  , auUserName
  , SessionResponse (..)
  )
import Types.Inventory
import Control.Applicative ((<|>))

------------------------------------------------------------------------
-- Auth resolution helper
--
-- The two paths share the same handler signatures — only this function
-- changes behaviour.  With USE_REAL_AUTH=false the Authorization header
-- value is passed directly to lookupUser (which ignores it and returns
-- the default dev user when Nothing or unrecognised).  With
-- USE_REAL_AUTH=true the full header is forwarded to resolveSession,
-- which expects "Bearer <token>" and throws 401 on any failure.
------------------------------------------------------------------------

resolveUser
  :: DBPool
  -> Bool         -- True = real auth, False = dev mode
  -> Maybe Text   -- Authorization header value
  -> Handler AuthenticatedUser
resolveUser pool True  mHeader = scUser <$> resolveSession pool mHeader
resolveUser _    False mHeader =
  -- Strip "Bearer " prefix if present so UUID-style dev tokens still
  -- resolve correctly, then fall through to lookupUser's defaults.
  pure $ lookupUser (extractBearer mHeader <|> mHeader)

------------------------------------------------------------------------
-- Effect runner
------------------------------------------------------------------------

runInvEff :: DBPool -> Eff '[InventoryDb, Error ServerError, IOE] a -> Handler a
runInvEff pool action = do
  result <- liftIO . runEff . runErrorNoCallStack @ServerError . runInventoryDbIO pool $ action
  either Servant.throwError pure result

------------------------------------------------------------------------
-- Top-level server
------------------------------------------------------------------------

combinedServer :: DBPool -> LogEnv -> Bool -> Server CheeblrAPI
combinedServer pool logEnv realAuth =
  inventoryServer pool logEnv realAuth
    :<|> posServerImpl pool logEnv
    :<|> authServerImpl pool logEnv
    :<|> pure cheeblrOpenApi

------------------------------------------------------------------------
-- Inventory server
------------------------------------------------------------------------

inventoryServer :: DBPool -> LogEnv -> Bool -> Server InventoryAPI
inventoryServer pool logEnv realAuth =
  getInventory
    :<|> addInventoryItem
    :<|> updateInventoryItem
    :<|> deleteInventoryItem
    :<|> getSession
    :<|> graphqlInventory
  where
    -- Shared auth resolution for every handler in this server.
    auth :: Maybe Text -> Handler AuthenticatedUser
    auth = resolveUser pool realAuth

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
      let caps = capabilitiesForRole (auRole user)
          lctx = makeLogCtx logEnv (Just (T.pack (show (auUserId user)))) (auRole user)
          skuT = T.pack (show (Types.Inventory.sku item))
      liftIO $ logHttpRequest logEnv "POST" "/inventory" (T.pack (show (auUserId user)))
      if not (capCanCreateItem caps)
        then do
          liftIO $ logAuthDenied logEnv (T.pack (show (auUserId user))) "capCanCreateItem"
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
    updateInventoryItem mHeader item = do
      user <- auth mHeader
      let caps = capabilitiesForRole (auRole user)
          lctx = makeLogCtx logEnv (Just (T.pack (show (auUserId user)))) (auRole user)
          skuT = T.pack (show (Types.Inventory.sku item))
      liftIO $ logHttpRequest logEnv "PUT" "/inventory" (T.pack (show (auUserId user)))
      if not (capCanEditItem caps)
        then do
          liftIO $ logAuthDenied logEnv (T.pack (show (auUserId user))) "capCanEditItem"
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
    deleteInventoryItem mHeader uuid = do
      user <- auth mHeader
      let caps = capabilitiesForRole (auRole user)
          lctx = makeLogCtx logEnv (Just (T.pack (show (auUserId user)))) (auRole user)
          skuT = T.pack (show uuid)
      liftIO $ logHttpRequest logEnv "DELETE" ("/inventory/" <> skuT) (T.pack (show (auUserId user)))
      if not (capCanDeleteItem caps)
        then do
          liftIO $ logAuthDenied logEnv (T.pack (show (auUserId user))) "capCanDeleteItem"
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
    getSession mHeader = do
      user <- auth mHeader
      let lctx = makeLogCtx logEnv (Just (T.pack (show (auUserId user)))) (auRole user)
      liftIO $ do
        logHttpRequest logEnv "GET" "/session" (T.pack (show (auUserId user)))
        logSessionAccess lctx
      pure SessionResponse
        { sessionUserId       = auUserId user
        , sessionUserName     = auUserName user
        , sessionRole         = auRole user
        , sessionCapabilities = capabilitiesForRole (auRole user)
        }

    graphqlInventory :: Maybe Text -> GQLRequest -> Handler GQLResponse
    graphqlInventory mHeader req = do
      user <- auth mHeader
      liftIO $ logHttpRequest logEnv "POST" "/graphql/inventory" (T.pack (show (auUserId user)))
      -- rootResolver still takes Maybe Text (the raw header) for its own
      -- dev-mode lookup; pass the stripped bearer or raw value.
      let mUserId = Just (T.pack (show (auUserId user)))
      liftIO $ interpreter (rootResolver pool mUserId) req