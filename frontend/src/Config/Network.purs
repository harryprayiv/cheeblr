module Config.Network where

-- Environment configuration settings
type EnvironmentConfig =
  { apiBaseUrl :: String
  , appOrigin :: String
  }

-- Local development configuration (localhost)
localConfig :: EnvironmentConfig
localConfig = 
  { apiBaseUrl: "https://localhost:8080"
  , appOrigin: "https://localhost:5173" 
  }

-- Network configuration for LAN testing
networkConfig :: EnvironmentConfig
networkConfig = 
  { apiBaseUrl: "https://192.168.8.248:8080"
  , appOrigin: "https://192.168.8.248:5173" 
  }

-- Toggle between configurations
-- Set this to networkConfig for LAN testing
currentConfig :: EnvironmentConfig
currentConfig = localConfig