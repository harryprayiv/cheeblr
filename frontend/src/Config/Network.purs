module Config.Network where

-- Environment configuration settings
type EnvironmentConfig =
  { apiBaseUrl :: String
  , appOrigin :: String
  }

-- Local development configuration (localhost)
localConfig :: EnvironmentConfig
localConfig = 
  { apiBaseUrl: "http://localhost:8080"
  , appOrigin: "http://localhost:5173" 
  }

-- Network configuration for LAN testing
-- Replace 192.168.1.X with your actual machine's IP address
networkConfig :: EnvironmentConfig
networkConfig = 
  { apiBaseUrl: "https://192.168.8.248:8080"
  , appOrigin: "https://192.168.8.248:5174" 
  }

-- Toggle between configurations
-- Set this to networkConfig for LAN testing
currentConfig :: EnvironmentConfig
currentConfig = localConfig