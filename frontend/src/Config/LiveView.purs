module Config.LiveView where

import Prelude
import Data.Tuple (Tuple)
import Data.Tuple.Nested ((/\))
import Config.Network (currentConfig)

defaultConfig :: FetchConfig
defaultConfig =
  { apiEndpoint: currentConfig.apiBaseUrl <> "/inventory"
  , jsonPath: "./inventory.json"
  , corsHeaders: true
  }

defaultViewConfig :: LiveViewConfig
defaultViewConfig =
  { sortFields:
      [ SortByQuantity /\ Descending
      , SortByCategory /\ Ascending
      , SortBySpecies /\ Descending
      ]
  , hideOutOfStock: false
  , mode: HttpMode
  , refreshRate: 5000
  , screens: 1
  , fetchConfig: defaultConfig
      { apiEndpoint = currentConfig.apiBaseUrl <> "/inventory"
      , corsHeaders = true
      }
  }

data QueryMode = JsonMode | HttpMode

derive instance eqQueryMode :: Eq QueryMode
derive instance ordQueryMode :: Ord QueryMode

instance Show QueryMode where
  show JsonMode = "JsonMode"
  show HttpMode = "HttpMode"

-- | Configuration type for fetcher
type FetchConfig =
  { apiEndpoint :: String
  , jsonPath :: String
  , corsHeaders :: Boolean
  }

-- | Unified configuration for LiveView
type LiveViewConfig =
  { sortFields :: Array (Tuple SortField SortOrder)
  , hideOutOfStock :: Boolean
  , mode :: QueryMode
  , refreshRate :: Int
  , screens :: Int
  , fetchConfig :: FetchConfig
  }

-- | Sorting types
data SortField
  = SortByOrder
  | SortByName
  | SortByCategory
  | SortBySubCategory
  | SortBySpecies
  | SortBySKU
  | SortByPrice
  | SortByQuantity

data SortOrder = Ascending | Descending

type SortConfig =
  { sortFields :: Array (Tuple SortField SortOrder)
  }