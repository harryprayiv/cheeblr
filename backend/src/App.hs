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
import qualified Data.ByteString.Char8 as B8

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
    corsPolicy = simpleCorsResourcePolicy
        { corsOrigins = Just ([B8.pack "http://localhost:5173", B8.pack "http://localhost:5174"], True)
        , corsRequestHeaders = [hContentType, hAccept, hAuthorization, hOrigin, hContentLength]
        , corsMethods = [methodGet, methodPost, methodPut, methodDelete, methodOptions]
        , corsMaxAge = Just 3600
        , corsVaryOrigin = True
        , corsExposedHeaders = Just [hContentType]
        }

    app = cors (const $ Just corsPolicy) $ serve api (combinedServer pool)

  Warp.run (serverPort config) app