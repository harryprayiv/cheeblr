module API.Inventory where

import Prelude

import API.Request as Request
import Data.Either (Either(..))
import Effect.Aff (Aff, attempt)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Now (now)
import Effect.Ref (Ref)
import Fetch (fetch)
import Fetch.Yoga.Json (fromJSON)
import Services.AuthService (AuthContext)
import Types.Inventory (Inventory, InventoryResponse(..), MenuItem)
import Config.LiveView (QueryMode(..), FetchConfig)

writeInventory :: Ref AuthContext -> MenuItem -> Aff (Either String InventoryResponse)
writeInventory authRef menuItem =
  Request.authPost authRef "/inventory" menuItem

readInventory :: Ref AuthContext -> Aff (Either String InventoryResponse)
readInventory authRef =
  Request.authGet authRef "/inventory"

updateInventory :: Ref AuthContext -> MenuItem -> Aff (Either String InventoryResponse)
updateInventory authRef menuItem =
  Request.authPut authRef "/inventory" menuItem

deleteInventory :: Ref AuthContext -> String -> Aff (Either String InventoryResponse)
deleteInventory authRef itemId =
  Request.authDelete authRef ("/inventory/" <> itemId)

-- | Fetch inventory from a local JSON file. No auth needed.
-- | This is the only function here that doesn't use the generic helpers
-- | because it hits a file path, not an API endpoint.
fetchInventoryFromJson :: FetchConfig -> Aff (Either String InventoryResponse)
fetchInventoryFromJson config = do
  result <- attempt do
    timestamp <- liftEffect $ show <$> now
    let url = config.jsonPath <> "?t=" <> timestamp
    liftEffect $ Console.log ("Fetching from JSON: " <> url)
    response <- fetch url {}
    inventory <- fromJSON response.json :: Aff Inventory
    pure inventory
  pure case result of
    Left err -> Left $ "JSON fetch error: " <> show err
    Right inventory -> Right $ InventoryData inventory

-- | Fetch inventory from the configured HTTP endpoint.
-- | Uses authGetFullUrl because the endpoint comes from FetchConfig
-- | and may differ from the default apiBaseUrl.
fetchInventoryFromHttp :: Ref AuthContext -> FetchConfig -> Aff (Either String InventoryResponse)
fetchInventoryFromHttp authRef config =
  Request.authGetFullUrl authRef config.apiEndpoint

-- | Dispatch between JSON file and HTTP based on QueryMode.
fetchInventory
  :: Ref AuthContext -> FetchConfig -> QueryMode -> Aff (Either String InventoryResponse)
fetchInventory authRef config = case _ of
  JsonMode -> fetchInventoryFromJson config
  HttpMode -> fetchInventoryFromHttp authRef config