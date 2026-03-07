{-# LANGUAGE OverloadedStrings #-}
module App where

import API.Inventory (api)
import DB.Database (initializeDB, createTables, DBConfig(..))
import DB.Transaction (createTransactionTables)
import qualified Network.Wai.Handler.Warp as Warp
import Network.Wai.Handler.WarpTLS (runTLS, tlsSettings)
import Servant
import Server (combinedServer)
import System.Posix.User (getLoginName)
import Network.HTTP.Types.Header (hContentType, hAccept, hAuthorization, hOrigin, hContentLength)
import Network.HTTP.Types.Method (methodGet, methodPost, methodPut, methodDelete, methodOptions)
import Network.Wai.Middleware.Cors (simpleCorsResourcePolicy, CorsResourcePolicy(..), cors)
import Network.Wai (responseBuilder, requestMethod)
import qualified Data.ByteString.Char8 as B8
import qualified Data.CaseInsensitive as CI
import Network.HTTP.Types.Status (status200)
import qualified Data.ByteString.Builder as B
import System.Environment (lookupEnv)
import Data.Maybe (fromMaybe)
import System.Directory (doesFileExist)
import Control.Exception (fromException)
import Network.TLS (TLSException(..))



data AppConfig = AppConfig
  { dbConfig :: DBConfig
  , serverPort :: Int
  , tlsCertFile :: Maybe FilePath
  , tlsKeyFile :: Maybe FilePath
  }

run :: IO ()
run = do
  currentUser <- getLoginName
  
  envHost     <- fromMaybe "localhost" <$> lookupEnv "PGHOST"
  envDbPort   <- maybe 5432 read <$> lookupEnv "PGPORT"
  envPort     <- maybe 8080 read <$> lookupEnv "PORT"
  envDb       <- fromMaybe "cheeblr"   <$> lookupEnv "PGDATABASE"
  envUser     <- fromMaybe currentUser  <$> lookupEnv "PGUSER"
  envPassword <- fromMaybe "postgres"   <$> lookupEnv "PGPASSWORD"
  
  -- TLS config from environment
  useTLS      <- lookupEnv "USE_TLS"
  certFile    <- lookupEnv "TLS_CERT_FILE"
  keyFile     <- lookupEnv "TLS_KEY_FILE"

  let config =
        AppConfig
          { dbConfig =
              DBConfig
                { dbHost = envHost
                , dbPort = envDbPort
                , dbName = envDb
                , dbUser = envUser
                , dbPassword = envPassword
                , poolSize = 10
                }
          , serverPort = envPort
          , tlsCertFile = certFile
          , tlsKeyFile = keyFile
          }

  pool <- initializeDB (dbConfig config)
  createTables pool
  createTransactionTables pool

  let
    hXRequestedWith = CI.mk (B8.pack "x-requested-with")
    hXUserId = CI.mk (B8.pack "x-user-id")
    
    corsPolicy = simpleCorsResourcePolicy
        { corsOrigins = Nothing
        , corsRequestHeaders = [hContentType, hAccept, hAuthorization, hOrigin, hContentLength, hXRequestedWith, hXUserId]
        , corsMethods = [methodGet, methodPost, methodPut, methodDelete, methodOptions]
        , corsMaxAge = Just 86400
        , corsVaryOrigin = False
        , corsExposedHeaders = Just [hContentType]
        , corsRequireOrigin = False
        , corsIgnoreFailures = True
        }

    app = cors (const $ Just corsPolicy) $ serve api (combinedServer pool)
    appWithOptions = handleOptionsMiddleware app    
    -- warpSettings = Warp.setPort (serverPort config)
    --              $ Warp.setHost "*"  -- bind all interfaces
    --              $ Warp.defaultSettings
    warpSettings = Warp.setPort (serverPort config)
                    $ Warp.setHost "*"
                    $ Warp.setOnException onEx Warp.defaultSettings
          where
            onEx _ e = case fromException e :: Maybe TLSException of
              Just _ -> pure ()
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
          putStrLn $ "  Key exists:  " ++ show keyExists ++ " (" ++ key ++ ")"
          Warp.runSettings warpSettings appWithOptions
    _ -> do
      let scheme = "http"
      putStrLn $ "Starting " ++ scheme ++ " server on port " ++ show (serverPort config)
      putStrLn "=================================="
      putStrLn $ scheme ++ "://YOUR_MACHINE_IP:" ++ show (serverPort config)
      putStrLn "=================================="
      Warp.runSettings warpSettings appWithOptions

handleOptionsMiddleware :: Application -> Application
handleOptionsMiddleware app req responder =
  if requestMethod req == methodOptions
  then responder $ responseBuilder status200 corsHeaders (B.byteString B8.empty)
  else app req responder
  where
    corsHeaders =
      [ (hContentType, B8.pack "text/plain")
      , (CI.mk $ B8.pack "Access-Control-Allow-Origin", B8.pack "*")
      , (CI.mk $ B8.pack "Access-Control-Allow-Methods", B8.pack "GET, POST, PUT, DELETE, OPTIONS")
      , (CI.mk $ B8.pack "Access-Control-Allow-Headers", B8.pack "Content-Type, Authorization, Accept, Origin, Content-Length, x-requested-with, x-user-id")
      , (CI.mk $ B8.pack "Access-Control-Max-Age", B8.pack "86400")
      ]


