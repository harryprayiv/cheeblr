{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Time               (getCurrentTime)
import qualified Data.Text.Encoding as TE

import App                     (runWithEnv)
import Config.App              (AppConfig (..), loadConfig)
import Config.BuildInfo        (currentBuildInfo)
import DB.Database             (DBConfig (..), initializeDB)
import Infrastructure.Broadcast (newBroadcaster, Broadcaster)
import Logging                 (initLogging)
import Server.Env              (AppEnv (..))
import Server.Metrics          (newMetrics)
import Types.Events.Availability (AvailabilityUpdate)
import Types.Events.Domain     (DomainEvent)
import Types.Events.Log        (LogEvent)
import Types.Events.Stock      (StockEvent)

main :: IO ()
main = do
  config    <- loadConfig
  startTime <- getCurrentTime

  logBc    <- newBroadcaster (cfgLogBroadcastSize    config)
                :: IO (Broadcaster LogEvent)
  domainBc <- newBroadcaster (cfgDomainBroadcastSize config)
                :: IO (Broadcaster DomainEvent)
  stockBc  <- newBroadcaster (cfgStockBroadcastSize  config)
                :: IO (Broadcaster StockEvent)
  availBc  <- newBroadcaster (cfgAvailabilityBroadcastSize config)
                :: IO (Broadcaster AvailabilityUpdate)

  metrics  <- newMetrics
  logEnv   <- initLogging (cfgLogFile config)
  pool     <- initializeDB (toDBConfig config)

  let env = AppEnv
        { envStartTime               = startTime
        , envBuildInfo               = currentBuildInfo
        , envConfig                  = config
        , envDbPool                  = pool
        , envSessionStore            = pool
        , envLogEnv                  = logEnv
        , envLogNS                   = mempty
        , envLogContext              = mempty
        , envLogBroadcaster          = logBc
        , envDomainBroadcaster       = domainBc
        , envStockBroadcaster        = stockBc
        , envAvailabilityBroadcaster = availBc
        , envMetrics                 = metrics
        }

  -- Phase 5: uncomment when Infrastructure.AvailabilityRelay exists.
  -- _ <- forkIO (runAvailabilityRelay env)

  runWithEnv env

-- Translate the new AppConfig into the DBConfig that initializeDB expects.
toDBConfig :: AppConfig -> DBConfig
toDBConfig cfg = DBConfig
  { dbHost     = TE.encodeUtf8 (cfgPgHost     cfg)
  , dbPort     = fromIntegral  (cfgPgPort     cfg)
  , dbName     = TE.encodeUtf8 (cfgPgDatabase cfg)
  , dbUser     = TE.encodeUtf8 (cfgPgUser     cfg)
  , dbPassword = TE.encodeUtf8 (cfgPgPassword cfg)
  , poolSize   = cfgDbPoolSize cfg
  }