{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module App (run, runWithEnv, buildCsp, extractCookieToken, cookieAuthMiddleware) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.STM (newTVarIO)
import Control.Exception (SomeException, catch, fromException)
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Char8 as B8
import qualified Data.CaseInsensitive as CI
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time
import Katip
    ( defaultScribeSettings,
      permitItem,
      registerScribe,
      Severity(InfoS) )
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
  Request (requestHeaders),
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
import Web.Cookie (parseCookies)

import Config.App (AppConfig (..), loadConfig)
import Config.BuildInfo (currentBuildInfo)
import DB.Auth (
  cleanupExpiredSessions,
  createAuthTables,
  getSessionRotatedAt,
  rotateSessionToken,
 )
import DB.Database (DBConfig (..), DBPool, createTables, initializeDB)
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
import Server.Cookie (sessionCookie)
import Server.Env (AppEnv (..))
import Server.Metrics (newMetrics)
import Server.Middleware.Tracing (tracingMiddleware)
import Types.Events.Availability (AvailabilityUpdate)
import Types.Events.Domain (DomainEvent)
import Types.Events.Log (LogEvent)
import Types.Events (StockEvent)
import Types.Location (locationIdToUUID)
import Types.Public.AvailableItem (PublicLocationId (..))

run :: IO ()
run = do
  config <- loadConfig
  runWithEnv =<< buildEnv config

buildEnv :: AppConfig -> IO AppEnv
buildEnv config = do
  startTime  <- Data.Time.getCurrentTime
  logBc      <- newBroadcaster (cfgLogBroadcastSize config)         :: IO (Broadcaster LogEvent)
  domainBc   <- newBroadcaster (cfgDomainBroadcastSize config)      :: IO (Broadcaster DomainEvent)
  stockBc    <- newBroadcaster (cfgStockBroadcastSize config)       :: IO (Broadcaster StockEvent)
  availBc    <- newBroadcaster (cfgAvailabilityBroadcastSize config) :: IO (Broadcaster AvailabilityUpdate)
  metrics    <- newMetrics
  logEnv     <- initLogging (cfgLogFile config)
  pool       <- initializeDB (toDBConfig config)
  availState <- newTVarIO $
    AvailabilityState
      { asItems       = Map.empty
      , asReserved    = Map.empty
      , asPublicLocId = PublicLocationId (locationIdToUUID (cfgPublicLocationId config))
      , asLocName     = cfgPublicLocationName config
      }
  pure AppEnv
    { envStartTime               = startTime
    , envBuildInfo               = currentBuildInfo
    , envConfig                  = config
    , envDbPool                  = pool
    , envLogEnv                  = logEnv
    , envLogNS                   = mempty
    , envLogContext              = mempty
    , envLogBroadcaster          = logBc
    , envDomainBroadcaster       = domainBc
    , envStockBroadcaster        = stockBc
    , envAvailabilityBroadcaster = availBc
    , envAvailabilityState       = availState
    , envMetrics                 = metrics
    }

runWithEnv :: AppEnv -> IO ()
runWithEnv env = do
  let
    pool = envDbPool env
    cfg  = envConfig env

  createTables pool
  createTransactionTables pool
  createAuthTables pool
  createEventsTables pool
  createStockTables pool

  broadcastScribe <- mkBroadcastScribe (envLogBroadcaster env) (Katip.permitItem Katip.InfoS)
  logEnv <-
    Katip.registerScribe "broadcast" broadcastScribe Katip.defaultScribeSettings (envLogEnv env)

  let
    port       = cfgPort cfg
    tlsEnabled = cfgUseTls cfg
    mAllowed   = cfgAllowedOrigin cfg

  logAppStartup logEnv port tlsEnabled
  logAppInfo logEnv $
    "CORS mode: " <> case mAllowed of
      Just origin -> "locked to " <> origin
      Nothing     -> "open (no ALLOWED_ORIGIN set)"
  logAppInfo logEnv $
    "Token rotation interval: "
      <> T.pack (show (cfgTokenRotationSecs cfg)) <> "s"

  _ <- forkIO $
    runAvailabilityRelay env
      `catch` (\(e :: SomeException) ->
        hPutStrLn stderr $ "AvailabilityRelay stopped: " <> show e)

  _ <- forkIO $
    sessionCleanupWorker pool (cfgSessionCleanupIntervalHours cfg)

  let
    hXRequestedWith = CI.mk (B8.pack "x-requested-with")
    hXUserId        = CI.mk (B8.pack "x-user-id")
    corsOrigins'    = case mAllowed of
      Just origin -> Just ([TE.encodeUtf8 origin], True)
      Nothing     -> Nothing
    corsPolicy =
      simpleCorsResourcePolicy
        { corsOrigins        = corsOrigins'
        , corsRequestHeaders =
            [ hContentType, hAccept, hAuthorization, hOrigin
            , hContentLength, hXRequestedWith, hXUserId
            ]
        , corsMethods        = [methodGet, methodPost, methodPut, methodDelete, methodOptions]
        , corsMaxAge         = Just 86400
        , corsVaryOrigin     = False
        , corsExposedHeaders = Just [hContentType]
        , corsRequireOrigin  = False
        , corsIgnoreFailures = True
        }
    coreApp =
      cors (const $ Just corsPolicy) $
        serve fullAPI (fullServer env)
    app =
      tracingMiddleware
        . securityHeadersMiddleware (cfgApiPublicUrl cfg) (cfgImgSrcDomain cfg)
        . handleOptionsMiddleware mAllowed   -- now enforces cfgAllowedOrigin
        . reflectOriginMiddleware
        . cookieAuthMiddleware pool (cfgTokenRotationSecs cfg)
        $ coreApp
    warpSettings =
      Warp.setPort port $
        Warp.setHost "*" $
          Warp.setOnException onEx Warp.defaultSettings
      where
        onEx _ e = case fromException e :: Maybe TLSException of
          Just _  -> pure ()
          Nothing -> Warp.defaultOnException Nothing e

  if tlsEnabled
    then do
      let cert = cfgTlsCertPath cfg
          key  = cfgTlsKeyPath  cfg
      certExists <- doesFileExist cert
      keyExists  <- doesFileExist key
      if certExists && keyExists
        then do
          logAppInfo logEnv $ "TLS enabled cert=" <> T.pack cert
          runTLS (tlsSettings cert key) warpSettings app
        else do
          logAppWarn logEnv
            "USE_TLS=true but cert/key files not found — falling back to HTTP"
          Warp.runSettings warpSettings app
    else
      Warp.runSettings warpSettings app

  logAppShutdown logEnv
  closeLogging logEnv

cookieAuthMiddleware :: DBPool -> Data.Time.NominalDiffTime -> Middleware
cookieAuthMiddleware pool rotationThreshold app req rspnd =
  case extractCookieToken req of
    Nothing ->
      app req rspnd
    Just tokenText -> do
      mRotation <- checkAndRotate pool rotationThreshold tokenText
      let
        (effectiveToken, mNewCookieHdr) = case mRotation of
          Nothing          -> (tokenText, Nothing)
          Just (newTok, _) -> (newTok, Just (sessionCookie newTok))
        newHdrs =
          (hAuthorization, "Bearer " <> TE.encodeUtf8 effectiveToken)
            : requestHeaders req
      app req {requestHeaders = newHdrs} $ \response ->
        rspnd $ case mNewCookieHdr of
          Nothing  -> response
          Just hdr ->
            mapResponseHeaders
              ((CI.mk (B8.pack "Set-Cookie"), TE.encodeUtf8 hdr) :)
              response

extractCookieToken :: Request -> Maybe T.Text
extractCookieToken req = do
  cookieHdr <- lookup "Cookie" (requestHeaders req)
  tokenBS   <- lookup "cheeblr_session" (parseCookies cookieHdr)
  pure (TE.decodeUtf8 tokenBS)

checkAndRotate
  :: DBPool
  -> Data.Time.NominalDiffTime
  -> T.Text
  -> IO (Maybe (T.Text, Data.Time.UTCTime))
checkAndRotate pool threshold tokenText = do
  now   <- Data.Time.getCurrentTime
  mInfo <- getSessionRotatedAt pool tokenText
  case mInfo of
    Nothing -> pure Nothing
    Just (sid, rotatedAt)
      | Data.Time.diffUTCTime now rotatedAt > threshold ->
          Just <$> rotateSessionToken pool sid
      | otherwise -> pure Nothing

sessionCleanupWorker :: DBPool -> Int -> IO ()
sessionCleanupWorker pool intervalHours = loop
  where
    loop = do
      threadDelay (intervalHours * 3600 * 1000000)
      cleanupExpiredSessions pool
        `catch` (\(e :: SomeException) ->
          hPutStrLn stderr $ "Session cleanup error: " <> show e)
      loop

buildCsp :: T.Text -> Maybe T.Text -> T.Text
buildCsp apiPublicUrl mImgDomain =
  T.intercalate "; "
    [ "default-src 'self'"
    , "script-src 'self'"
    , "style-src 'self'"
    , "img-src 'self' data: " <> fromMaybe "https:" mImgDomain
    , "connect-src 'self' " <> apiPublicUrl <> " " <> toWsUrl apiPublicUrl
    , "frame-ancestors 'none'"
    , "base-uri 'self'"
    , "form-action 'self'"
    ]
  where
    toWsUrl url
      | "https://" `T.isPrefixOf` url = "wss://" <> T.drop 8 url
      | "http://"  `T.isPrefixOf` url = "ws://"  <> T.drop 7 url
      | otherwise                      = url

securityHeadersMiddleware :: T.Text -> Maybe T.Text -> Middleware
securityHeadersMiddleware apiPublicUrl mImgDomain app req sendResponse =
  app req $ \response ->
    sendResponse $
      mapResponseHeaders
        ( <>
          [ ( CI.mk $ B8.pack "Strict-Transport-Security"
            , B8.pack "max-age=31536000; includeSubDomains"
            )
          , ( CI.mk $ B8.pack "X-Content-Type-Options"
            , B8.pack "nosniff"
            )
          , ( CI.mk $ B8.pack "X-Frame-Options"
            , B8.pack "DENY"
            )
          , ( CI.mk $ B8.pack "Referrer-Policy"
            , B8.pack "strict-origin-when-cross-origin"
            )
          , ( CI.mk $ B8.pack "Content-Security-Policy"
            , TE.encodeUtf8 (buildCsp apiPublicUrl mImgDomain)
            )
          ]
        )
        response

-- | Previously reflected any origin the client sent unconditionally,
-- overriding the CORS policy set by the wai-cors middleware above it.
-- Now accepts the configured allowed origin and enforces it:
--   Just origin → always respond with that origin (browser rejects mismatches)
--   Nothing     → open mode: reflect whatever the client sent (dev default)
handleOptionsMiddleware :: Maybe T.Text -> Middleware
handleOptionsMiddleware mAllowed app req responder =
  if requestMethod req == methodOptions
    then do
      let
        requestOrigin  = lookup hOrigin (requestHeaders req)
        responseOrigin = case mAllowed of
          Just allowed -> TE.encodeUtf8 allowed
          Nothing      -> fromMaybe (B8.pack "*") requestOrigin
      responder $
        responseBuilder status200
          [ (hContentType, B8.pack "text/plain")
          , (CI.mk (B8.pack "Access-Control-Allow-Origin"),      responseOrigin)
          , (CI.mk (B8.pack "Access-Control-Allow-Credentials"), B8.pack "true")
          , (CI.mk (B8.pack "Access-Control-Allow-Methods"),
              B8.pack "GET, POST, PUT, DELETE, OPTIONS")
          , (CI.mk (B8.pack "Access-Control-Allow-Headers"),
              B8.pack "Content-Type, Authorization, Accept, Origin, \
                      \Content-Length, x-requested-with, x-user-id")
          , (CI.mk (B8.pack "Access-Control-Max-Age"), B8.pack "86400")
          ]
          (B.byteString B8.empty)
    else app req responder

reflectOriginMiddleware :: Middleware
reflectOriginMiddleware app req rspnd =
  app req $ \response ->
    case lookup hOrigin (requestHeaders req) of
      Nothing     -> rspnd response
      Just origin ->
        rspnd $
          mapResponseHeaders
            ( \hdrs ->
                let filtered = filter
                      (\(n, _) -> n /= "Access-Control-Allow-Origin"
                                && n /= "Access-Control-Allow-Credentials")
                      hdrs
                in filtered
                     <> [ (CI.mk (B8.pack "Access-Control-Allow-Origin"), origin)
                        , (CI.mk (B8.pack "Access-Control-Allow-Credentials"), B8.pack "true")
                        ]
            )
            response

toDBConfig :: AppConfig -> DBConfig
toDBConfig cfg =
  DBConfig
    { dbHost     = TE.encodeUtf8 (cfgPgHost cfg)
    , dbPort     = fromIntegral (cfgPgPort cfg)
    , dbName     = TE.encodeUtf8 (cfgPgDatabase cfg)
    , dbUser     = TE.encodeUtf8 (cfgPgUser cfg)
    , dbPassword = TE.encodeUtf8 (cfgPgPassword cfg)
    , poolSize   = cfgDbPoolSize cfg
    }