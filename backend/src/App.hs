module App where

import API.Inventory (api)
import DB.Database (initializeDB, createTables, DBConfig(..))
import DB.Transaction (createTransactionTables)
import qualified Network.Wai.Handler.Warp as Warp
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

data AppConfig = AppConfig
  { dbConfig :: DBConfig
  , serverPort :: Int
  }

run :: IO ()
run = do
  currentUser <- getLoginName
  let config =
        AppConfig
          { dbConfig =
              DBConfig
                { dbHost = "localhost"
                , dbPort = 5432
                , dbName = "cheeblr"
                , dbUser = currentUser
                , dbPassword = "postgres"
                , poolSize = 10
                }
          , serverPort = 8080
          }

  pool <- initializeDB (dbConfig config)

  createTables pool
  createTransactionTables pool

  putStrLn $ "Starting server on all interfaces, port " ++ show (serverPort config)
  putStrLn "=================================="
  putStrLn $ "Server running on port " ++ show (serverPort config)
  putStrLn "You can access this application from other devices on your network using:"
  putStrLn $ "http://YOUR_MACHINE_IP:" ++ show (serverPort config)
  putStrLn "=================================="

  let
    -- Define custom header name with correct type
    hXRequestedWith :: CI.CI B8.ByteString
    hXRequestedWith = CI.mk (B8.pack "x-requested-with")
    
    -- Very permissive CORS policy for development
    corsPolicy = simpleCorsResourcePolicy
        { corsOrigins = Nothing -- Allow all origins
        , corsRequestHeaders = [hContentType, hAccept, hAuthorization, hOrigin, hContentLength, hXRequestedWith]
        , corsMethods = [methodGet, methodPost, methodPut, methodDelete, methodOptions]
        , corsMaxAge = Just 86400 -- 24 hours
        , corsVaryOrigin = False
        , corsExposedHeaders = Just [hContentType]
        , corsRequireOrigin = False
        , corsIgnoreFailures = True -- ignore CORS failures in development
        }

    app = cors (const $ Just corsPolicy) $ serve api (combinedServer pool)
    
    -- Add middleware for OPTIONS requests
    appWithOptions = handleOptionsMiddleware app

  Warp.run (serverPort config) appWithOptions

-- Middleware to handle OPTIONS requests for CORS preflight
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
      , (CI.mk $ B8.pack "Access-Control-Allow-Headers", B8.pack "Content-Type, Authorization, Accept, Origin, Content-Length, x-requested-with")
      , (CI.mk $ B8.pack "Access-Control-Max-Age", B8.pack "86400")
      ]