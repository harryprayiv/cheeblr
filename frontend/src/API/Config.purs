module Cheeblr.API.Config where

-- | Environment configuration for API endpoints.
-- | Swap `currentConfig` to point at staging/prod as needed.

type EnvironmentConfig =
  { apiBaseUrl :: String
  , appOrigin :: String
  }

localConfig :: EnvironmentConfig
localConfig =
  { apiBaseUrl: "http://localhost:8080"
  , appOrigin: "http://localhost:5174"
  }

currentConfig :: EnvironmentConfig
currentConfig = localConfig