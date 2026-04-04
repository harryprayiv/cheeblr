{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Effect.StockDb (
  StockDb (..),
  createPullRequest,
  getPullRequest,
  updatePullStatus,
  getPendingPulls,
  getPullsByTransaction,
  addPullMessage,
  getPullMessages,
  cancelPullsForTransaction,
  cancelPullsForItem,
  runStockDbIO,
  StockStore (..),
  emptyStockStore,
  runStockDbPure,
) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.UUID (UUID)
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local

import DB.Database (DBPool)
import qualified DB.Stock as DBS
import State.StockPullMachine (PullVertex (..))
import Types.Location (LocationId)
import Types.Stock

data StockDb :: Effect where
  CreatePullRequest :: PullRequest -> StockDb m (Either Text ())
  GetPullRequest :: UUID -> StockDb m (Maybe PullRequest)
  UpdatePullStatus :: UUID -> PullVertex -> Maybe Text -> StockDb m (Either Text ())
  GetPendingPulls :: LocationId -> StockDb m [PullRequest]
  GetPullsByTransaction :: UUID -> StockDb m [PullRequest]
  AddPullMessage :: UUID -> PullMessage -> StockDb m (Either Text ())
  GetPullMessages :: UUID -> StockDb m [PullMessage]
  CancelPullsForTransaction :: UUID -> Text -> StockDb m ()
  CancelPullsForItem :: UUID -> UUID -> Text -> StockDb m ()

type instance DispatchOf StockDb = Dynamic

createPullRequest :: (StockDb :> es) => PullRequest -> Eff es (Either Text ())
createPullRequest = send . CreatePullRequest

getPullRequest :: (StockDb :> es) => UUID -> Eff es (Maybe PullRequest)
getPullRequest = send . GetPullRequest

updatePullStatus :: (StockDb :> es) => UUID -> PullVertex -> Maybe Text -> Eff es (Either Text ())
updatePullStatus pid v mNote = send (UpdatePullStatus pid v mNote)

getPendingPulls :: (StockDb :> es) => LocationId -> Eff es [PullRequest]
getPendingPulls = send . GetPendingPulls

getPullsByTransaction :: (StockDb :> es) => UUID -> Eff es [PullRequest]
getPullsByTransaction = send . GetPullsByTransaction

addPullMessage :: (StockDb :> es) => UUID -> PullMessage -> Eff es (Either Text ())
addPullMessage pid msg = send (AddPullMessage pid msg)

getPullMessages :: (StockDb :> es) => UUID -> Eff es [PullMessage]
getPullMessages = send . GetPullMessages

cancelPullsForTransaction :: (StockDb :> es) => UUID -> Text -> Eff es ()
cancelPullsForTransaction txId reason = send (CancelPullsForTransaction txId reason)

cancelPullsForItem :: (StockDb :> es) => UUID -> UUID -> Text -> Eff es ()
cancelPullsForItem txId itemSku reason = send (CancelPullsForItem txId itemSku reason)

runStockDbIO :: (IOE :> es) => DBPool -> Eff (StockDb : es) a -> Eff es a
runStockDbIO pool = interpret $ \_ -> \case
  CreatePullRequest pr -> liftIO $ do
    DBS.insertPullRequest pool pr
    pure (Right ())
  GetPullRequest pid ->
    liftIO $ DBS.getPullRequest pool pid
  UpdatePullStatus pid v mNote -> liftIO $ do
    DBS.updatePullStatus pool pid v mNote
    pure (Right ())
  GetPendingPulls locId ->
    liftIO $ DBS.getPendingPulls pool locId
  GetPullsByTransaction txId ->
    liftIO $ DBS.getPullsByTransaction pool txId
  AddPullMessage pid msg -> liftIO $ do
    DBS.insertPullMessage pool pid msg
    pure (Right ())
  GetPullMessages pid ->
    liftIO $ DBS.getPullMessages pool pid
  CancelPullsForTransaction txId reason ->
    liftIO $ DBS.cancelPullsForTransaction pool txId reason
  CancelPullsForItem txId itemSku _reason ->
    liftIO $ DBS.cancelPullsForItem pool txId itemSku

data StockStore = StockStore
  { ssRequests :: Map UUID PullRequest
  , ssMessages :: Map UUID [PullMessage]
  }
  deriving (Show, Eq)

emptyStockStore :: StockStore
emptyStockStore = StockStore Map.empty Map.empty

runStockDbPure :: StockStore -> Eff (StockDb : es) a -> Eff es (a, StockStore)
runStockDbPure initial = reinterpret (runState initial) $ \_ -> \case
  CreatePullRequest pr -> do
    modify @StockStore $ \st ->
      st {ssRequests = Map.insert (prId pr) pr (ssRequests st)}
    pure (Right ())
  GetPullRequest pid ->
    gets @StockStore (Map.lookup pid . ssRequests)
  UpdatePullStatus pid newVertex _mNote -> do
    st <- get @StockStore
    case Map.lookup pid (ssRequests st) of
      Nothing -> pure (Left "Pull request not found")
      Just pr -> do
        put @StockStore
          st {ssRequests = Map.insert pid pr {prStatus = newVertex} (ssRequests st)}
        pure (Right ())
  GetPendingPulls locId ->
    gets @StockStore $
      filter
        ( \pr ->
            prLocationId pr == locId
              && prStatus pr `notElem` [PullFulfilled, PullCancelled]
        )
        . Map.elems
        . ssRequests
  GetPullsByTransaction txId ->
    gets @StockStore $
      filter (\pr -> prTransactionId pr == txId) . Map.elems . ssRequests
  AddPullMessage pid msg -> do
    modify @StockStore $ \st ->
      st {ssMessages = Map.insertWith (<>) pid [msg] (ssMessages st)}
    pure (Right ())
  GetPullMessages pid ->
    gets @StockStore (Map.findWithDefault [] pid . ssMessages)
  CancelPullsForTransaction txId _reason ->
    modify @StockStore $ \st ->
      st
        { ssRequests =
            Map.map
              ( \pr ->
                  if prTransactionId pr == txId
                    && prStatus pr `notElem` [PullFulfilled, PullCancelled]
                    then pr {prStatus = PullCancelled}
                    else pr
              )
              (ssRequests st)
        }
  CancelPullsForItem txId itemSku _reason ->
    modify @StockStore $ \st ->
      st
        { ssRequests =
            Map.map
              ( \pr ->
                  if prTransactionId pr == txId
                    && prItemSku pr == itemSku
                    && prStatus pr `notElem` [PullFulfilled, PullCancelled]
                    then pr {prStatus = PullCancelled}
                    else pr
              )
              (ssRequests st)
        }
