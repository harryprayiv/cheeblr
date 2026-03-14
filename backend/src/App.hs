{-# LANGUAGE OverloadedStrings #-}

module App where

import Control.Exception (fromException)
import Data.Maybe (fromMaybe)
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Char8 as B8
import qualified Data.CaseInsensitive as CI
import Network.HTTP.Types.Header (hContentType, hAccept, hAuthorization, hOrigin, hContentLength)
import Network.HTTP.Types.Method (methodGet, methodPost, methodPut, methodDelete, methodOptions)
import Network.HTTP.Types.Status (status200)
import Network.TLS (TLSException (..))
import Network.Wai (responseBuilder, requestMethod)
import Network.Wai.Handler.WarpTLS (runTLS, tlsSettings)
import qualified Network.Wai.Handler.Warp as Warp
import Network.Wai.Middleware.Cors (simpleCorsResourcePolicy, CorsResourcePolicy (..), cors)
import Servant
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.Posix.User (getEffectiveUserName)
import API.OpenApi (cheeblrAPI)
import DB.Database (DBConfig (..), initializeDB, createTables)
import DB.Transaction (createTransactionTables)
import Server (combinedServer)

data AppConfig = AppConfig
  { dbConfig    :: DBConfig
  , serverPort  :: Int
  , tlsCertFile :: Maybe FilePath
  , tlsKeyFile  :: Maybe FilePath
  }

run :: IO ()
run = do
  currentUser <- getEffectiveUserName

  envHost     <- fromMaybe "localhost"  <$> lookupEnv "PGHOST"
  envDbPort   <- maybe (5432 :: Int) read <$> lookupEnv "PGPORT"
  envPort     <- maybe 8080 read        <$> lookupEnv "PORT"
  envDb       <- fromMaybe "cheeblr"    <$> lookupEnv "PGDATABASE"
  envUser     <- fromMaybe currentUser  <$> lookupEnv "PGUSER"
  envPassword <- fromMaybe "BOOTSTRAP_FALLBACK_ONLY_USE_SOPS" <$> lookupEnv "PGPASSWORD"

  useTLS   <- lookupEnv "USE_TLS"
  certFile <- lookupEnv "TLS_CERT_FILE"
  keyFile  <- lookupEnv "TLS_KEY_FILE"

  let config = AppConfig
        { dbConfig = DBConfig
            { dbHost     = B8.pack envHost
            , dbPort     = fromIntegral envDbPort
            , dbName     = B8.pack envDb
            , dbUser     = B8.pack envUser
            , dbPassword = B8.pack envPassword
            , poolSize   = 10
            }
        , serverPort  = envPort
        , tlsCertFile = certFile
        , tlsKeyFile  = keyFile
        }

  pool <- initializeDB (dbConfig config)
  createTables pool
  createTransactionTables pool

  let
    hXRequestedWith = CI.mk (B8.pack "x-requested-with")
    hXUserId        = CI.mk (B8.pack "x-user-id")

    corsPolicy = simpleCorsResourcePolicy
      { corsOrigins        = Nothing
      , corsRequestHeaders =
          [hContentType, hAccept, hAuthorization, hOrigin, hContentLength, hXRequestedWith, hXUserId]
      , corsMethods        = [methodGet, methodPost, methodPut, methodDelete, methodOptions]
      , corsMaxAge         = Just 86400
      , corsVaryOrigin     = False
      , corsExposedHeaders = Just [hContentType]
      , corsRequireOrigin  = False
      , corsIgnoreFailures = True
      }

    app = cors (const $ Just corsPolicy) $
            serve cheeblrAPI (combinedServer pool)

    appWithOptions = handleOptionsMiddleware app

    warpSettings =
      Warp.setPort (serverPort config)
      $ Warp.setHost "*"
      $ Warp.setOnException onEx Warp.defaultSettings
      where
        onEx _ e = case fromException e :: Maybe TLSException of
          Just _  -> pure ()
          Nothing -> Warp.defaultOnException Nothing e

  case (useTLS, tlsCertFile config, tlsKeyFile config) of
    (Just "true", Just cert, Just key) -> do
      certExists <- doesFileExist cert
      keyExists  <- doesFileExist key
      if certExists && keyExists
        then do
          let tls = tlsSettings cert key
          putStrLn $ "Starting HTTPS server on port " ++ show (serverPort config)
          putStrLn $ "  Cert: " ++ cert
          putStrLn $ "  Key:  " ++ key
          putStrLn "=================================="
          putStrLn $ "https://YOUR_MACHINE_IP:" ++ show (serverPort config)
          putStrLn "=================================="
          runTLS tls warpSettings appWithOptions
        else do
          putStrLn "WARNING: USE_TLS=true but cert/key files not found, falling back to HTTP"
          putStrLn $ "  Cert exists: " ++ show certExists ++ " (" ++ cert ++ ")"
          putStrLn $ "  Key exists:  " ++ show keyExists  ++ " (" ++ key  ++ ")"
          Warp.runSettings warpSettings appWithOptions
    _ -> do
      putStrLn $ "Starting HTTP server on port " ++ show (serverPort config)
      putStrLn "=================================="
      putStrLn $ "http://YOUR_MACHINE_IP:" ++ show (serverPort config)
      putStrLn "=================================="
      Warp.runSettings warpSettings appWithOptions

handleOptionsMiddleware :: Application -> Application
handleOptionsMiddleware app req responder =
  if requestMethod req == methodOptions
    then responder $ responseBuilder status200 corsHeaders (B.byteString B8.empty)
    else app req responder
  where
    corsHeaders =
      [ (hContentType,                                          B8.pack "text/plain")
      , (CI.mk $ B8.pack "Access-Control-Allow-Origin",        B8.pack "*")
      , (CI.mk $ B8.pack "Access-Control-Allow-Methods",       B8.pack "GET, POST, PUT, DELETE, OPTIONS")
      , (CI.mk $ B8.pack "Access-Control-Allow-Headers",       B8.pack
            "Content-Type, Authorization, Accept, Origin, Content-Length, x-requested-with, x-user-id")
      , (CI.mk $ B8.pack "Access-Control-Max-Age",             B8.pack "86400")
      ]