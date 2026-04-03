{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module App (run, runWithEnv) where

import Control.Concurrent (forkIO)
import Control.Concurrent.STM (newTVarIO)
import Control.Exception (SomeException, catch, fromException)
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Char8 as B8
import qualified Data.CaseInsensitive as CI
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (getCurrentTime)
import Katip
import Network.HTTP.Types.Header (
  hAccept,
  hAuthorization,
  hContentLength,
  hContentType,
  hOrigin,
 )
import Network.HTTP.Types.Method (
  methodDelete,
  methodGet,
  methodOptions,
  methodPost,
  methodPut,
 )
import Network.HTTP.Types.Status (status200)
import Network.TLS (TLSException (..))
import Network.Wai (
  Middleware,
  mapResponseHeaders,
  requestMethod,
  responseBuilder,
 )
import qualified Network.Wai.Handler.Warp as Warp
import Network.Wai.Handler.WarpTLS (runTLS, tlsSettings)
import Network.Wai.Middleware.Cors (
  CorsResourcePolicy (..),
  cors,
  simpleCorsResourcePolicy,
 )
import Servant
import System.Directory (doesFileExist)
import System.IO (hPutStrLn, stderr)

-- import API.OpenApi                        (cheeblrAPI)
import Config.App (AppConfig (..), loadConfig)
import Config.BuildInfo (currentBuildInfo)
import DB.Auth (createAuthTables)
import DB.Database (DBConfig (..), createTables, initializeDB)
import DB.Events (createEventsTables)
import DB.Stock (createStockTables)
import DB.Transaction (createTransactionTables)
import Infrastructure.AvailabilityRelay (runAvailabilityRelay)
import Infrastructure.AvailabilityState (AvailabilityState (..))
import Infrastructure.Broadcast (Broadcaster, newBroadcaster)
import Logging (
  closeLogging,
  initLogging,
  logAppInfo,
  logAppShutdown,
  logAppStartup,
  logAppWarn,
 )
import Logging.BroadcastScribe (mkBroadcastScribe)
import Server (fullAPI, fullServer)
import Server.Env (AppEnv (..))
import Server.Metrics (newMetrics)
import Server.Middleware.Tracing (tracingMiddleware)
import Types.Events.Availability (AvailabilityUpdate)
import Types.Events.Domain (DomainEvent)
import Types.Events.Log (LogEvent)
import Types.Events.Stock (StockEvent)
import Types.Location (locationIdToUUID)
import Types.Public.AvailableItem (PublicLocationId (..))

run :: IO ()
run = do
  config <- loadConfig
  startTime <- getCurrentTime
  logBc <- newBroadcaster (cfgLogBroadcastSize config) :: IO (Broadcaster LogEvent)
  domainBc <- newBroadcaster (cfgDomainBroadcastSize config) :: IO (Broadcaster DomainEvent)
  stockBc <- newBroadcaster (cfgStockBroadcastSize config) :: IO (Broadcaster StockEvent)
  availBc <-
    newBroadcaster (cfgAvailabilityBroadcastSize config) ::
      IO (Broadcaster AvailabilityUpdate)
  metrics <- newMetrics
  logEnv <- initLogging (cfgLogFile config)
  pool <- initializeDB (toDBConfig config)
  availState <-
    newTVarIO $
      AvailabilityState
        { asItems = Map.empty
        , asReserved = Map.empty
        , asPublicLocId = PublicLocationId (locationIdToUUID (cfgPublicLocationId config))
        , asLocName = cfgPublicLocationName config
        }
  let env =
        AppEnv
          { envStartTime = startTime
          , envBuildInfo = currentBuildInfo
          , envConfig = config
          , envDbPool = pool
          , envSessionStore = pool
          , envLogEnv = logEnv
          , envLogNS = mempty
          , envLogContext = mempty
          , envLogBroadcaster = logBc
          , envDomainBroadcaster = domainBc
          , envStockBroadcaster = stockBc
          , envAvailabilityBroadcaster = availBc
          , envAvailabilityState = availState
          , envMetrics = metrics
          }
  runWithEnv env

runWithEnv :: AppEnv -> IO ()
runWithEnv env = do
  let
    pool = envDbPool env
    cfg = envConfig env

  createTables pool
  createTransactionTables pool
  createAuthTables pool
  createEventsTables pool
  createStockTables pool

  -- Register the broadcast scribe so log events flow to envLogBroadcaster.
  -- logEnv is used for all logging from this point forward.
  broadcastScribe <- mkBroadcastScribe (envLogBroadcaster env) (permitItem InfoS)
  logEnv <-
    registerScribe
      "broadcast"
      broadcastScribe
      defaultScribeSettings
      (envLogEnv env)

  let
    port = cfgPort cfg
    tlsEnabled = cfgUseTls cfg
    mAllowed = cfgAllowedOrigin cfg

  logAppStartup logEnv port tlsEnabled
  logAppInfo logEnv $
    "CORS mode: " <> case mAllowed of
      Just origin -> "locked to " <> origin
      Nothing -> "open (no ALLOWED_ORIGIN set)"

  _ <-
    forkIO $
      runAvailabilityRelay env
        `catch` ( \(e :: SomeException) ->
                    hPutStrLn stderr $ "AvailabilityRelay stopped: " <> show e
                )

  let
    hXRequestedWith = CI.mk (B8.pack "x-requested-with")
    hXUserId = CI.mk (B8.pack "x-user-id")
    corsOrigins' = case mAllowed of
      Just origin -> Just ([TE.encodeUtf8 origin], True)
      Nothing -> Nothing
    corsPolicy =
      simpleCorsResourcePolicy
        { corsOrigins = corsOrigins'
        , corsRequestHeaders =
            [ hContentType
            , hAccept
            , hAuthorization
            , hOrigin
            , hContentLength
            , hXRequestedWith
            , hXUserId
            ]
        , corsMethods =
            [methodGet, methodPost, methodPut, methodDelete, methodOptions]
        , corsMaxAge = Just 86400
        , corsVaryOrigin = False
        , corsExposedHeaders = Just [hContentType]
        , corsRequireOrigin = False
        , corsIgnoreFailures = True
        }
    coreApp =
      cors (const $ Just corsPolicy) $
        serve fullAPI (fullServer env)
    app =
      tracingMiddleware
        . securityHeadersMiddleware
        . handleOptionsMiddleware
        $ coreApp
    warpSettings =
      Warp.setPort port $
        Warp.setHost "*" $
          Warp.setOnException onEx Warp.defaultSettings
      where
        onEx _ e = case fromException e :: Maybe TLSException of
          Just _ -> pure ()
          Nothing -> Warp.defaultOnException Nothing e

  if tlsEnabled
    then do
      let
        cert = cfgTlsCertPath cfg
        key = cfgTlsKeyPath cfg
      certExists <- doesFileExist cert
      keyExists <- doesFileExist key
      if certExists && keyExists
        then do
          logAppInfo logEnv $ "TLS enabled cert=" <> T.pack cert
          runTLS (tlsSettings cert key) warpSettings app
        else do
          logAppWarn
            logEnv
            "USE_TLS=true but cert/key files not found — falling back to HTTP"
          Warp.runSettings warpSettings app
    else
      Warp.runSettings warpSettings app

  logAppShutdown logEnv
  closeLogging logEnv

securityHeadersMiddleware :: Middleware
securityHeadersMiddleware app req sendResponse =
  app req $ \response ->
    sendResponse $
      mapResponseHeaders
        ( <>
            [
              ( CI.mk $ B8.pack "Strict-Transport-Security"
              , B8.pack "max-age=31536000; includeSubDomains"
              )
            ,
              ( CI.mk $ B8.pack "X-Content-Type-Options"
              , B8.pack "nosniff"
              )
            ,
              ( CI.mk $ B8.pack "X-Frame-Options"
              , B8.pack "DENY"
              )
            ,
              ( CI.mk $ B8.pack "Referrer-Policy"
              , B8.pack "strict-origin-when-cross-origin"
              )
            ,
              ( CI.mk $ B8.pack "Content-Security-Policy"
              , B8.pack
                  "default-src 'self'; script-src 'self'; \
                  \style-src 'self' 'unsafe-inline'; \
                  \img-src 'self' data: https:"
              )
            ]
        )
        response

handleOptionsMiddleware :: Middleware
handleOptionsMiddleware app req responder =
  if requestMethod req == methodOptions
    then
      responder $
        responseBuilder status200 corsHeaders (B.byteString B8.empty)
    else app req responder
  where
    corsHeaders =
      [
        ( hContentType
        , B8.pack "text/plain"
        )
      ,
        ( CI.mk $ B8.pack "Access-Control-Allow-Origin"
        , B8.pack "*"
        )
      ,
        ( CI.mk $ B8.pack "Access-Control-Allow-Methods"
        , B8.pack "GET, POST, PUT, DELETE, OPTIONS"
        )
      ,
        ( CI.mk $ B8.pack "Access-Control-Allow-Headers"
        , B8.pack
            "Content-Type, Authorization, Accept, Origin, \
            \Content-Length, x-requested-with, x-user-id"
        )
      ,
        ( CI.mk $ B8.pack "Access-Control-Max-Age"
        , B8.pack "86400"
        )
      ]

toDBConfig :: AppConfig -> DBConfig
toDBConfig cfg =
  DBConfig
    { dbHost = TE.encodeUtf8 (cfgPgHost cfg)
    , dbPort = fromIntegral (cfgPgPort cfg)
    , dbName = TE.encodeUtf8 (cfgPgDatabase cfg)
    , dbUser = TE.encodeUtf8 (cfgPgUser cfg)
    , dbPassword = TE.encodeUtf8 (cfgPgPassword cfg)
    , poolSize = cfgDbPoolSize cfg
    }
