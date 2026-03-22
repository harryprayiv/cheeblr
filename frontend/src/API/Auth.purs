module API.Auth where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe)
import Effect.Aff (Aff, attempt)
import Fetch (Method(..), fetch)
import Fetch.Yoga.Json (fromJSON)
import Config.Network (currentConfig)
import Types.Auth (UserCapabilities, UserRole)
import Types.Session (SessionResponse)
import Types.UUID (UUID)
import Yoga.JSON (writeJSON)

------------------------------------------------------------------------
-- Request / response types (mirrors Haskell API.Auth)
------------------------------------------------------------------------

type LoginRequest =
  { loginUsername   :: String
  , loginPassword   :: String
  , loginRegisterId :: Maybe UUID
  }

type LoginResponse =
  { loginToken     :: String
  , loginExpiresAt :: String
  , loginUser      :: SessionResponse
  }

------------------------------------------------------------------------
-- API calls
-- These bypass authGet/authPost because they do not carry a session yet.
------------------------------------------------------------------------

login
  :: String        -- username
  -> String        -- password
  -> Maybe UUID    -- optional register binding
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
      }
    fromJSON response.json :: Aff LoginResponse
  pure $ case result of
    Left err -> Left (show err)
    Right r  -> Right r

logout :: String -> Aff (Either String Unit)
logout token = do
  result <- attempt do
    _ <- fetch (currentConfig.apiBaseUrl <> "/auth/logout")
      { method: POST
      , headers:
          { "Content-Type": "application/json"
          , "Accept":       "application/json"
          , "Authorization": "Bearer " <> token
          }
      }
    pure unit
  pure $ case result of
    Left err -> Left (show err)
    Right _  -> Right unit

-- Validate a stored token and return the current session info.
-- Used on startup to restore sessions across page refreshes.
validateSession :: String -> Aff (Either String SessionResponse)
validateSession token = do
  result <- attempt do
    response <- fetch (currentConfig.apiBaseUrl <> "/auth/me")
      { method: GET
      , headers:
          { "Accept":        "application/json"
          , "Authorization": "Bearer " <> token
          }
      }
    fromJSON response.json :: Aff SessionResponse
  pure $ case result of
    Left err -> Left (show err)
    Right r  -> Right r