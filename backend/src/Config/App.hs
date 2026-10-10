{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Config.App (
  AppConfig (..),
  Environment (..),
  loadConfig,
) where

import Config.Env
import Control.Exception (throwIO)
import Data.Aeson (ToJSON)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (NominalDiffTime)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import GHC.Generics (Generic)

import Domain.StockPolicy (
  RestockPolicy,
  StockPolicy (..),
  parseRestockPolicy,
 )
import Types.Location (LocationId (..))

data Environment
  = Development
  | Staging
  | Production
  deriving (Show, Read, Eq, Ord, Generic)

instance ToJSON Environment

data AppConfig = AppConfig
  { cfgPort           :: Int
  , cfgBindAddress    :: Text

  , cfgPgHost         :: Text
  , cfgPgPort         :: Int
  , cfgPgDatabase     :: Text
  , cfgPgUser         :: Text
  , cfgPgPassword     :: Text
  , cfgDatabaseUrl    :: Text
  , cfgDbPoolSize     :: Int
  , cfgDbPoolTimeout  :: NominalDiffTime

  , cfgSessionTtlSeconds :: Int

  , cfgTokenRotationSecs :: NominalDiffTime

  , cfgSessionCleanupIntervalHours :: Int

  , cfgRateLimitWindow :: NominalDiffTime
  , cfgRateLimitMax    :: Int

  , cfgTlsCertPath :: FilePath
  , cfgTlsKeyPath  :: FilePath
  , cfgUseTls      :: Bool



  , cfgAllowedOrigin :: Maybe Text

  , cfgApiPublicUrl :: Text

  , cfgImgSrcDomain :: Maybe Text

  , cfgLowStockThreshold    :: Int
  , cfgStaleTransactionSecs :: Int

  , cfgLogBroadcastSize          :: Int
  , cfgDomainBroadcastSize       :: Int
  , cfgStockBroadcastSize        :: Int
  , cfgAvailabilityBroadcastSize :: Int

  , cfgEnvironment :: Environment


  , cfgLogFile     :: FilePath

  , cfgPublicLocationId   :: LocationId
  , cfgPublicLocationName :: Text

  -- Whether voiding and refunding a completed sale put stock back. Read
  -- from RESTOCK_ON_VOID and RESTOCK_ON_REFUND. Neither has a default.
  , cfgStockPolicy :: StockPolicy
  }

loadConfig :: IO AppConfig
loadConfig = do
  port     <- envInt  "PORT"         8080
  bind     <- envText "BIND_ADDRESS" "0.0.0.0"
  pgHost   <- envText "PGHOST"       "localhost"
  pgPort   <- envInt  "PGPORT"       5432
  pgDb     <- envText "PGDATABASE"   "cheeblr"
  pgUser   <- envText "PGUSER"       "cheeblr"
  pgPass   <- envText "PGPASSWORD"   ""
  let dbUrl =
        "postgresql://"
          <> pgUser <> ":" <> pgPass
          <> "@" <> pgHost <> ":"
          <> T.pack (show pgPort) <> "/" <> pgDb
  poolSize    <- envInt  "DB_POOL_SIZE"         10
  poolTimeout <- envSecs "DB_POOL_TIMEOUT_SECS" 30
  sessionTtl  <- envInt  "SESSION_TTL_SECS"     3600

  tokenRotationSecs           <- envSecs "TOKEN_ROTATION_SECS"            900
  sessionCleanupIntervalHours <- envInt  "SESSION_CLEANUP_INTERVAL_HOURS" 1

  rlWindow   <- envSecs "RATE_LIMIT_WINDOW_SECS" 60
  rlMax      <- envInt  "RATE_LIMIT_MAX"          10
  certPath   <- envPath "TLS_CERT_FILE" "cert.pem"
  keyPath    <- envPath "TLS_KEY_FILE"  "key.pem"
  useTls     <- envBool "USE_TLS" False
  allowedOrig <- envMaybe "ALLOWED_ORIGIN"

  apiPublicUrl  <- envText  "API_PUBLIC_URL" "https://localhost:8080"
  mImgSrcDomain <- envMaybe "IMG_SRC_DOMAIN"

  lowStock  <- envInt "LOW_STOCK_THRESHOLD"    5
  staleTx   <- envInt "STALE_TRANSACTION_SECS" 1800

  logBcSize    <- envInt "LOG_BROADCAST_SIZE"          500
  domainBcSize <- envInt "DOMAIN_BROADCAST_SIZE"       200
  stockBcSize  <- envInt "STOCK_BROADCAST_SIZE"        200
  availBcSize  <- envInt "AVAILABILITY_BROADCAST_SIZE" 200

  appEnv  <- envEnum "APP_ENVIRONMENT" Development
  logFile <- envPath "LOG_FILE"        "cheeblr.log"

  pubLocId   <- LocationId <$> envUUID "PUBLIC_LOCATION_ID" nilUUID
  pubLocName <- envText "PUBLIC_LOCATION_NAME" "Main Location"

  restockVoid   <- envRestockPolicy "RESTOCK_ON_VOID"
  restockRefund <- envRestockPolicy "RESTOCK_ON_REFUND"

  pure AppConfig
    { cfgPort        = port
    , cfgBindAddress = bind
    , cfgPgHost      = pgHost
    , cfgPgPort      = pgPort
    , cfgPgDatabase  = pgDb
    , cfgPgUser      = pgUser
    , cfgPgPassword  = pgPass
    , cfgDatabaseUrl = dbUrl
    , cfgDbPoolSize  = poolSize
    , cfgDbPoolTimeout = poolTimeout
    , cfgSessionTtlSeconds = sessionTtl
    , cfgTokenRotationSecs = tokenRotationSecs
    , cfgSessionCleanupIntervalHours = sessionCleanupIntervalHours
    , cfgRateLimitWindow = rlWindow
    , cfgRateLimitMax    = rlMax
    , cfgTlsCertPath = certPath
    , cfgTlsKeyPath  = keyPath
    , cfgUseTls      = useTls
    , cfgAllowedOrigin = allowedOrig
    , cfgApiPublicUrl  = apiPublicUrl
    , cfgImgSrcDomain  = mImgSrcDomain
    , cfgLowStockThreshold    = lowStock
    , cfgStaleTransactionSecs = staleTx
    , cfgLogBroadcastSize          = logBcSize
    , cfgDomainBroadcastSize       = domainBcSize
    , cfgStockBroadcastSize        = stockBcSize
    , cfgAvailabilityBroadcastSize = availBcSize
    , cfgEnvironment = appEnv
    , cfgLogFile     = logFile
    , cfgPublicLocationId   = pubLocId
    , cfgPublicLocationName = pubLocName
    , cfgStockPolicy =
        StockPolicy
          { restockOnVoid   = restockVoid
          , restockOnRefund = restockRefund
          }
    }

-- | Reads a restock setting. The variable has to be set, and its value has
-- to be @restock@ or @no-restock@. A missing or unreadable value stops the
-- program at startup with a message that names the variable. There is no
-- default, so whoever deploys the backend has to make the choice.
envRestockPolicy :: String -> IO RestockPolicy
envRestockPolicy name = do
  raw <- envRequired name
  case parseRestockPolicy raw of
    Right policy -> pure policy
    Left problem ->
      throwIO . userError $
        "Invalid value for " <> name <> ": " <> T.unpack problem

nilUUID :: UUID
nilUUID = case UUID.fromString "00000000-0000-0000-0000-000000000000" of
  Just u  -> u
  Nothing -> error "nilUUID: impossible"