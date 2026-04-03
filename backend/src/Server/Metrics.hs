module Server.Metrics (
  Metrics (..),
  newMetrics,
  incRequestCount,
  incErrorCount,
  incDbQueryCount,
  incDbErrorCount,
  adjustActiveConnections,
) where

import Control.Concurrent.STM
import Data.Int (Int64)

data Metrics = Metrics
  { mRequestCount :: TVar Int64
  , mErrorCount :: TVar Int64
  , mActiveConnections :: TVar Int
  , mDbQueryCount :: TVar Int64
  , mDbErrorCount :: TVar Int64
  }

newMetrics :: IO Metrics
newMetrics =
  Metrics
    <$> newTVarIO 0
    <*> newTVarIO 0
    <*> newTVarIO 0
    <*> newTVarIO 0
    <*> newTVarIO 0

incRequestCount :: Metrics -> STM ()
incRequestCount m = modifyTVar' (mRequestCount m) (+ 1)

incErrorCount :: Metrics -> STM ()
incErrorCount m = modifyTVar' (mErrorCount m) (+ 1)

incDbQueryCount :: Metrics -> STM ()
incDbQueryCount m = modifyTVar' (mDbQueryCount m) (+ 1)

incDbErrorCount :: Metrics -> STM ()
incDbErrorCount m = modifyTVar' (mDbErrorCount m) (+ 1)

adjustActiveConnections :: Metrics -> Int -> STM ()
adjustActiveConnections m delta =
  modifyTVar' (mActiveConnections m) (+ delta)
