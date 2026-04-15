{-# LANGUAGE OverloadedStrings #-}

module Infrastructure.AvailabilityRelay (
  runAvailabilityRelay,
  populateFromDb,
  updateAvailability,
) where

import Control.Concurrent.STM
import Control.Monad (forever)
import qualified Data.Map.Strict as Map
import Data.Time (UTCTime, getCurrentTime)
import qualified Data.Vector as V

import qualified DB.Database as DB
import qualified DB.Reservation as DBRes
import Infrastructure.AvailabilityState
import Infrastructure.Broadcast (publish, subChan, subscribe)
import Server.Env (AppEnv (..))
import Types.Events
import Types.Events.Availability (AvailabilityUpdate (..))
import Types.Events.Domain (DomainEvent (..))
import Types.Inventory (Inventory (..))
import qualified Types.Inventory as TI
import qualified Types.Transaction as TT

runAvailabilityRelay :: AppEnv -> IO ()
runAvailabilityRelay env = do
  populateFromDb env
  sub <- subscribe (envDomainBroadcaster env)
  forever $ do
    evt <- atomically $ readTChan (subChan sub)
    now <- getCurrentTime
    mUpd <- atomically $ updateAvailability (envAvailabilityState env) evt now
    case mUpd of
      Nothing -> pure ()
      Just upd -> publish (envAvailabilityBroadcaster env) upd

populateFromDb :: AppEnv -> IO ()
populateFromDb env = do
  Inventory itemVec <- DB.getAllMenuItems (envDbPool env)
  let invItems = V.toList itemVec
  reservations <- DBRes.getAllActiveReservations (envDbPool env)
  atomically $ modifyTVar' (envAvailabilityState env) $ \st ->
    st
      { asItems = Map.fromList [(TI.sku i, i) | i <- invItems]
      , asReserved =
          Map.fromListWith
            (+)
            [ (TT.reservationItemSku r, TT.reservationQuantity r)
            | r <- reservations
            ]
      }

updateAvailability ::
  TVar AvailabilityState ->
  DomainEvent ->
  UTCTime ->
  STM (Maybe AvailabilityUpdate)
updateAvailability stVar evt now = case evt of
  InventoryEvt (ItemCreated {ieItem = item}) -> do
    modifyTVar' stVar $ \st ->
      st {asItems = Map.insert (TI.sku item) item (asItems st)}
    publishFor (TI.sku item)
  InventoryEvt (ItemUpdated {ieNewItem = item}) -> do
    modifyTVar' stVar $ \st ->
      st {asItems = Map.insert (TI.sku item) item (asItems st)}
    publishFor (TI.sku item)
  InventoryEvt (ItemDeleted {ieSku = skuId}) -> do
    modifyTVar' stVar $ \st ->
      st
        { asItems = Map.delete skuId (asItems st)
        , asReserved = Map.delete skuId (asReserved st)
        }
    pure Nothing
  TransactionEvt (TransactionItemAdded {teItem = item}) -> do
    let
      skuId = TT.transactionItemMenuItemSku item
      qty = TT.transactionItemQuantity item
    modifyTVar' stVar $ \st ->
      st {asReserved = Map.insertWith (+) skuId qty (asReserved st)}
    publishFor skuId
  TransactionEvt (TransactionItemRemoved {teItemSku = skuId, teQty = qty}) -> do
    modifyTVar' stVar $ \st ->
      st
        { asReserved =
            Map.update
              (\r -> let r' = r - qty in if r' <= 0 then Nothing else Just r')
              skuId
              (asReserved st)
        }
    publishFor skuId
  _ -> pure Nothing
  where
    publishFor skuId = do
      st <- readTVar stVar
      pure $
        fmap
          (\ai -> AvailabilityUpdate ai now)
          (toAvailableItem st skuId now)
