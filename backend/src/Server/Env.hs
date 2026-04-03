{-# LANGUAGE StrictData #-}

module Server.Env (
  AppEnv (..),
) where

import Config.App (AppConfig)
import Config.BuildInfo (BuildInfo)
import Control.Concurrent.STM (TVar)
import Data.Time (UTCTime)
import Hasql.Pool (Pool)
import Infrastructure.AvailabilityState (AvailabilityState)
import Infrastructure.Broadcast (Broadcaster)
import Katip (LogContexts, LogEnv, Namespace)
import Server.Metrics (Metrics)
import Types.Events.Availability (AvailabilityUpdate)
import Types.Events.Domain (DomainEvent)
import Types.Events.Log (LogEvent)
import Types.Events.Stock (StockEvent)

data AppEnv = AppEnv
  { envStartTime :: UTCTime
  , envBuildInfo :: BuildInfo
  , envConfig :: AppConfig
  , envDbPool :: Pool
  , -- Sessions live in the same PostgreSQL pool.
    -- Kept as a distinct field so a future phase can swap in a dedicated
    -- store without touching every call site.
    envSessionStore :: Pool
  , envLogEnv :: LogEnv
  , envLogNS :: Namespace
  , envLogContext :: LogContexts
  , envLogBroadcaster :: Broadcaster LogEvent
  , envDomainBroadcaster :: Broadcaster DomainEvent
  , envStockBroadcaster :: Broadcaster StockEvent
  , envAvailabilityBroadcaster :: Broadcaster AvailabilityUpdate
  , envAvailabilityState :: TVar AvailabilityState
  , envMetrics :: Metrics
  }
