module Cheeblr.API.Inventory where

import Prelude

import Cheeblr.API.Auth (AuthContext)
import Cheeblr.API.AuthRequest as AR
import Cheeblr.Core.Product (Product, ProductResponse)
import Data.Either (Either(..))
import Effect.Aff (Aff, attempt)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Now (now)
import Effect.Ref (Ref)
import Fetch (fetch)
import Fetch.Yoga.Json (fromJSON)

----------------------------------------------------------------------
-- Fetch mode config
----------------------------------------------------------------------

data QueryMode = JsonMode | HttpMode

derive instance Eq QueryMode
derive instance Ord QueryMode

instance Show QueryMode where
  show JsonMode = "JsonMode"
  show HttpMode = "HttpMode"

type FetchConfig =
  { apiEndpoint :: String
  , jsonPath :: String
  , corsHeaders :: Boolean
  }

----------------------------------------------------------------------
-- CRUD operations
----------------------------------------------------------------------

create :: Ref AuthContext -> Product -> Aff (Either String ProductResponse)
create ref product =
  AR.authPost ref "/inventory" product

read :: Ref AuthContext -> Aff (Either String ProductResponse)
read ref =
  AR.authGet ref "/inventory"

update :: Ref AuthContext -> Product -> Aff (Either String ProductResponse)
update ref product =
  AR.authPut ref "/inventory" product

remove :: Ref AuthContext -> String -> Aff (Either String ProductResponse)
remove ref itemId =
  AR.authDelete ref ("/inventory/" <> itemId)

----------------------------------------------------------------------
-- Fetch (mode-aware: JSON file or HTTP API)
----------------------------------------------------------------------

fetchFromJson :: FetchConfig -> Aff (Either String ProductResponse)
fetchFromJson config = do
  result <- attempt do
    timestamp <- liftEffect $ show <$> now
    let url = config.jsonPath <> "?t=" <> timestamp
    liftEffect $ Console.log ("Fetching from JSON: " <> url)
    response <- fetch url {}
    fromJSON response.json
  pure case result of
    Left err -> Left $ "JSON fetch error: " <> show err
    Right inventory -> Right inventory

fetchFromHttp :: Ref AuthContext -> FetchConfig -> Aff (Either String ProductResponse)
fetchFromHttp ref config =
  AR.authGetFullUrl ref config.apiEndpoint

-- | Fetch inventory using the configured mode.
fetchInventory
  :: Ref AuthContext -> FetchConfig -> QueryMode -> Aff (Either String ProductResponse)
fetchInventory ref config = case _ of
  JsonMode -> fetchFromJson config
  HttpMode -> fetchFromHttp ref config