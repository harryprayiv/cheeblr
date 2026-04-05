module API.Auth where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe)
import Effect.Aff (Aff, attempt, throwError)
import Effect.Exception (error)
import Fetch (Method(..), RequestCredentials(..), fetch)
import Fetch.Yoga.Json (fromJSON)
import Config.Network (currentConfig)
import Types.Session (SessionResponse)
import Types.UUID (UUID)
import Yoga.JSON (writeJSON)

type LoginRequest =
  { loginUsername   :: String
  , loginPassword   :: String
  , loginRegisterId :: Maybe UUID
  }

type LoginResponse =
  { loginExpiresAt :: String
  , loginUser      :: SessionResponse
  }

login
  :: String
  -> String
  -> Maybe UUID
  -> Aff (Either String LoginResponse)
login username password mRegisterId = do
  result <- attempt do
    response <- fetch (currentConfig.apiBaseUrl <> "/auth/login")
      { method: POST
      , body: writeJSON
          { loginUsername:   username
          , loginPassword:   password
          , loginRegisterId: mRegisterId
          }
      , headers:
          { "Content-Type": "application/json"
          , "Accept":       "application/json"
          }
      , credentials: Include
      }
    if response.status >= 200 && response.status < 300
      then fromJSON response.json :: Aff LoginResponse
      else do
        body <- response.text
        throwError $ error $ "HTTP " <> show response.status <> ": " <> body
  pure $ case result of
    Left err -> Left (show err)
    Right r  -> Right r

logout :: Aff (Either String Unit)
logout = do
  result <- attempt do
    _ <- fetch (currentConfig.apiBaseUrl <> "/auth/logout")
      { method: POST
      , headers:
          { "Content-Type": "application/json"
          , "Accept":       "application/json"
          }
      , credentials: Include
      }
    pure unit
  pure $ case result of
    Left err -> Left (show err)
    Right _  -> Right unit

validateSession :: Aff (Either String SessionResponse)
validateSession = do
  result <- attempt do
    response <- fetch (currentConfig.apiBaseUrl <> "/auth/me")
      { method: GET
      , headers:
          { "Accept": "application/json"
          }
      , credentials: Include
      }
    if response.status >= 200 && response.status < 300
      then fromJSON response.json :: Aff SessionResponse
      else do
        body <- response.text
        throwError $ error $ "HTTP " <> show response.status <> ": " <> body
  pure $ case result of
    Left err -> Left (show err)
    Right r  -> Right r