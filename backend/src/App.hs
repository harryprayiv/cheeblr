{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module App (run, runWithEnv) where

import Control.Exception (fromException, catch, SomeException)
import qualified Data.ByteString.Builder  as B
import qualified Data.ByteString.Char8    as B8
import qualified Data.CaseInsensitive     as CI
import qualified Data.Text                as T
import qualified Data.Text.Encoding       as TE
import Data.Maybe (fromMaybe)
import Network.HTTP.Types.Header (hContentType, hAccept, hAuthorization,
                                   hOrigin, hContentLength)
import Network.HTTP.Types.Method (methodGet, methodPost, methodPut,
                                   methodDelete, methodOptions)
import Network.HTTP.Types.Status (status200)
import Network.TLS               (TLSException (..))
import Network.Wai               (Middleware, mapResponseHeaders,
                                   responseBuilder, requestMethod)
import Network.Wai.Handler.WarpTLS (runTLS, tlsSettings)
import qualified Network.Wai.Handler.Warp as Warp
import Network.Wai.Middleware.Cors (simpleCorsResourcePolicy,
                                     CorsResourcePolicy (..), cors)
import Servant
import System.Directory          (doesFileExist)
import System.Environment        (lookupEnv)
import System.Posix.User         (getEffectiveUserName)

import API.OpenApi    (cheeblrAPI)
import DB.Auth        (createAuthTables)
import DB.Database    (DBConfig (..), initializeDB, createTables)
import DB.Transaction (createTransactionTables)
import Logging
import Server         (combinedServer)
import Server.Env     (AppEnv (..))
import Config.App     (AppConfig (..) )

------------------------------------------------------------------------
-- Internal config type used only by run.
-- Renamed from AppConfig -> RunConfig to avoid clashing with
-- the new Config.App.AppConfig that runWithEnv uses.
------------------------------------------------------------------------

data RunConfig = RunConfig
  { rcDbConfig    :: DBConfig
  , rcServerPort  :: Int
  , rcTlsCertFile :: Maybe FilePath
  , rcTlsKeyFile  :: Maybe FilePath
  }

------------------------------------------------------------------------
-- Security headers middleware (unchanged)
------------------------------------------------------------------------

securityHeadersMiddleware :: Middleware
securityHeadersMiddleware app req sendResponse =
  app req $ \response ->
    sendResponse $ mapResponseHeaders
      ( <>
          [ (CI.mk $ B8.pack "Strict-Transport-Security",
             B8.pack "max-age=31536000; includeSubDomains")
          , (CI.mk $ B8.pack "X-Content-Type-Options",
             B8.pack "nosniff")
          , (CI.mk $ B8.pack "X-Frame-Options",
             B8.pack "DENY")
          , (CI.mk $ B8.pack "Referrer-Policy",
             B8.pack "strict-origin-when-cross-origin")
          , (CI.mk $ B8.pack "Content-Security-Policy",
             B8.pack "default-src 'self'; script-src 'self'; \
                     \style-src 'self' 'unsafe-inline'; \
                     \img-src 'self' data: https:")
          ]
      )
      response

------------------------------------------------------------------------
-- handleOptionsMiddleware (unchanged)
------------------------------------------------------------------------

handleOptionsMiddleware :: Application -> Application
handleOptionsMiddleware app req responder =
  if requestMethod req == methodOptions
    then responder $
           responseBuilder status200 corsHeaders (B.byteString B8.empty)
    else app req responder
  where
    corsHeaders =
      [ (hContentType,
         B8.pack "text/plain")
      , (CI.mk $ B8.pack "Access-Control-Allow-Origin",
         B8.pack "*")
      , (CI.mk $ B8.pack "Access-Control-Allow-Methods",
         B8.pack "GET, POST, PUT, DELETE, OPTIONS")
      , (CI.mk $ B8.pack "Access-Control-Allow-Headers",
         B8.pack "Content-Type, Authorization, Accept, Origin, \
                 \Content-Length, x-requested-with, x-user-id")
      , (CI.mk $ B8.pack "Access-Control-Max-Age",
         B8.pack "86400")
      ]

------------------------------------------------------------------------
-- run — original entry point, completely unchanged in behaviour.
-- Uses RunConfig internally; does not touch AppEnv.
------------------------------------------------------------------------

run :: IO ()
run = do
  envHost     <- fromMaybe "localhost"  <$> lookupEnv "PGHOST"
  envDbPort   <- maybe (5432 :: Int) read <$> lookupEnv "PGPORT"
  envPort     <- maybe 8080 read        <$> lookupEnv "PORT"
  envDb       <- fromMaybe "cheeblr"    <$> lookupEnv "PGDATABASE"
  currentUser <- getEffectiveUserName
                  `catch` (\e -> let _ = e :: SomeException in pure "nobody")
  envUser     <- fromMaybe currentUser <$> lookupEnv "PGUSER"
  envPassword <- fromMaybe "BOOTSTRAP_FALLBACK_ONLY_USE_SOPS"
                   <$> lookupEnv "PGPASSWORD"

  useTLS         <- lookupEnv "USE_TLS"
  certFile       <- lookupEnv "TLS_CERT_FILE"
  keyFile        <- lookupEnv "TLS_KEY_FILE"
  logFile        <- fromMaybe "./cheeblr-compliance.log"
                      <$> lookupEnv "LOG_FILE"
  allowedOriginE <- lookupEnv "ALLOWED_ORIGIN"

  let tlsEnabled     = useTLS == Just "true"
      mAllowedOrigin = allowedOriginE >>= \s ->
        if null s then Nothing else Just s

  let config = RunConfig
        { rcDbConfig = DBConfig
            { dbHost     = B8.pack envHost
            , dbPort     = fromIntegral envDbPort
            , dbName     = B8.pack envDb
            , dbUser     = B8.pack envUser
            , dbPassword = B8.pack envPassword
            , poolSize   = 10
            }
        , rcServerPort  = envPort
        , rcTlsCertFile = certFile
        , rcTlsKeyFile  = keyFile
        }

  pool <- initializeDB (rcDbConfig config)
  createTables pool
  createTransactionTables pool
  createAuthTables pool

  logEnv <- initLogging logFile
  logAppStartup logEnv (rcServerPort config) tlsEnabled
  logAppInfo logEnv $
    "CORS mode: " <> case mAllowedOrigin of
      Just origin -> "locked to " <> T.pack origin
      Nothing     -> "open (no ALLOWED_ORIGIN set)"

  let
    hXRequestedWith = CI.mk (B8.pack "x-requested-with")
    hXUserId        = CI.mk (B8.pack "x-user-id")
    corsOrigins' = case mAllowedOrigin of
      Just origin -> Just ([B8.pack origin], True)
      Nothing     -> Nothing
    corsPolicy = simpleCorsResourcePolicy
      { corsOrigins        = corsOrigins'
      , corsRequestHeaders =
          [ hContentType, hAccept, hAuthorization, hOrigin
          , hContentLength, hXRequestedWith, hXUserId
          ]
      , corsMethods        =
          [methodGet, methodPost, methodPut, methodDelete, methodOptions]
      , corsMaxAge         = Just 86400
      , corsVaryOrigin     = False
      , corsExposedHeaders = Just [hContentType]
      , corsRequireOrigin  = False
      , corsIgnoreFailures = True
      }
    coreApp =
      cors (const $ Just corsPolicy) $
        serve cheeblrAPI (combinedServer pool logEnv)
    app =
      securityHeadersMiddleware
      . handleOptionsMiddleware
      $ coreApp
    warpSettings =
      Warp.setPort (rcServerPort config)
      $ Warp.setHost "*"
      $ Warp.setOnException onEx Warp.defaultSettings
      where
        onEx _ e = case fromException e :: Maybe TLSException of
          Just _  -> pure ()
          Nothing -> Warp.defaultOnException Nothing e

  case (tlsEnabled, rcTlsCertFile config, rcTlsKeyFile config) of
    (True, Just cert, Just key) -> do
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
    _ ->
      Warp.runSettings warpSettings app

  logAppShutdown logEnv
  closeLogging logEnv

------------------------------------------------------------------------
-- runWithEnv — Phase 0 entry point.
-- Receives a fully-constructed AppEnv; builds the WAI app and starts
-- Warp. All resource init (pool, log env, broadcasters) is the
-- caller's responsibility.
------------------------------------------------------------------------

runWithEnv :: AppEnv -> IO ()
runWithEnv env = do
  let pool    = envDbPool env
  let logEnv' = envLogEnv env
  let cfg     = envConfig env

  -- Idempotent DDL — safe on every restart.
  createTables pool
  createTransactionTables pool
  createAuthTables pool

  let port       = cfgPort cfg
  let tlsEnabled = cfgUseTls cfg
  let mAllowed   = cfgAllowedOrigin cfg

  logAppStartup logEnv' port tlsEnabled
  logAppInfo logEnv' $
    "CORS mode: " <> case mAllowed of
      Just origin -> "locked to " <> origin
      Nothing     -> "open (no ALLOWED_ORIGIN set)"

  let
    hXRequestedWith = CI.mk (B8.pack "x-requested-with")
    hXUserId        = CI.mk (B8.pack "x-user-id")
    corsOrigins' = case mAllowed of
      Just origin -> Just ([TE.encodeUtf8 origin], True)
      Nothing     -> Nothing
    corsPolicy = simpleCorsResourcePolicy
      { corsOrigins        = corsOrigins'
      , corsRequestHeaders =
          [ hContentType, hAccept, hAuthorization, hOrigin
          , hContentLength, hXRequestedWith, hXUserId
          ]
      , corsMethods        =
          [methodGet, methodPost, methodPut, methodDelete, methodOptions]
      , corsMaxAge         = Just 86400
      , corsVaryOrigin     = False
      , corsExposedHeaders = Just [hContentType]
      , corsRequireOrigin  = False
      , corsIgnoreFailures = True
      }
    coreApp =
      cors (const $ Just corsPolicy) $
        serve cheeblrAPI (combinedServer pool logEnv')
    app =
      securityHeadersMiddleware
      . handleOptionsMiddleware
      $ coreApp
    warpSettings =
      Warp.setPort port
      $ Warp.setHost "*"
      $ Warp.setOnException onEx Warp.defaultSettings
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
          logAppInfo logEnv' $ "TLS enabled cert=" <> T.pack cert
          runTLS (tlsSettings cert key) warpSettings app
        else do
          logAppWarn logEnv'
            "USE_TLS=true but cert/key files not found — falling back to HTTP"
          Warp.runSettings warpSettings app
    else
      Warp.runSettings warpSettings app

  logAppShutdown logEnv'
  closeLogging logEnv'