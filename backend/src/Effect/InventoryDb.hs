{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Effect.InventoryDb
  ( InventoryDb (..)
  , getAllMenuItems
  , insertMenuItem
  , updateMenuItem
  , deleteMenuItem
  , runInventoryDbIO
  , runInventoryDbPure
  ) where

import Control.Exception (SomeException, try)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.UUID (UUID)
import qualified Data.Vector as V
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local

import qualified DB.Database as DB
import DB.Database (DBPool)
import Types.Inventory

data InventoryDb :: Effect where
  GetAllMenuItems :: InventoryDb m Inventory
  InsertMenuItem  :: MenuItem -> InventoryDb m (Either SomeException ())
  UpdateMenuItem  :: MenuItem -> InventoryDb m (Either SomeException ())
  DeleteMenuItem  :: UUID -> InventoryDb m MutationResponse

type instance DispatchOf InventoryDb = Dynamic

getAllMenuItems :: InventoryDb :> es => Eff es Inventory
getAllMenuItems = send GetAllMenuItems

insertMenuItem :: InventoryDb :> es => MenuItem -> Eff es (Either SomeException ())
insertMenuItem = send . InsertMenuItem

updateMenuItem :: InventoryDb :> es => MenuItem -> Eff es (Either SomeException ())
updateMenuItem = send . UpdateMenuItem

deleteMenuItem :: InventoryDb :> es => UUID -> Eff es MutationResponse
deleteMenuItem = send . DeleteMenuItem

runInventoryDbIO :: IOE :> es => DBPool -> Eff (InventoryDb : es) a -> Eff es a
runInventoryDbIO pool = interpret $ \_ -> \case
  GetAllMenuItems  -> liftIO $ DB.getAllMenuItems pool
  InsertMenuItem m -> liftIO $ try @SomeException $ DB.insertMenuItem pool m
  UpdateMenuItem m -> liftIO $ try @SomeException $ DB.updateExistingMenuItem pool m
  DeleteMenuItem u -> liftIO $ DB.deleteMenuItem pool u

runInventoryDbPure
  :: Map UUID MenuItem
  -> Eff (InventoryDb : es) a
  -> Eff es (a, Map UUID MenuItem)
runInventoryDbPure initial = reinterpret (runState initial) $ \_ -> \case
  GetAllMenuItems  ->
    gets @(Map UUID MenuItem) (Inventory . V.fromList . Map.elems)
  InsertMenuItem m ->
    modify @(Map UUID MenuItem) (Map.insert (Types.Inventory.sku m) m) >> pure (Right ())
  UpdateMenuItem m ->
    modify @(Map UUID MenuItem) (Map.insert (Types.Inventory.sku m) m) >> pure (Right ())
  DeleteMenuItem u -> do
    store <- get @(Map UUID MenuItem)
    case Map.lookup u store of
      Nothing -> pure $ MutationResponse False "Item not found"
      Just _  -> modify @(Map UUID MenuItem) (Map.delete u)
                   >> pure (MutationResponse True "Item deleted successfully")