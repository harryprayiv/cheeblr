module API.Inventory where

import Prelude

import API.Request (ApiError(..))
import API.Request as Request
import Config.LiveView (FetchConfig, QueryMode(..))
import Data.Either (Either(..))
import Effect.Aff (Aff, attempt)
import Effect.Class (liftEffect)
import Effect.Exception (message)
import Effect.Now (now)
import Fetch (fetch)
import Fetch.Yoga.Json (fromJSON)
import GraphQL.API.Inventory (readInventoryGql)
import Types.Inventory (Inventory, MenuItem, MutationResponse)

writeInventory :: MenuItem -> Aff (Either ApiError MutationResponse)
writeInventory menuItem = Request.post "/inventory" menuItem

readInventory :: Aff (Either ApiError Inventory)
readInventory = Request.get "/inventory"

updateInventory :: MenuItem -> Aff (Either ApiError MutationResponse)
updateInventory menuItem = Request.put "/inventory" menuItem

deleteInventory :: String -> Aff (Either ApiError MutationResponse)
deleteInventory itemId = Request.delete ("/inventory/" <> itemId)

-- Reads a static file served beside the app, not the API. No credentials.
fetchInventoryFromJson :: FetchConfig -> Aff (Either ApiError Inventory)
fetchInventoryFromJson config = do
  result <- attempt do
    timestamp <- liftEffect $ show <$> now
    response <- fetch (config.jsonPath <> "?t=" <> timestamp) {}
    fromJSON response.json :: Aff Inventory
  pure case result of
    Left err -> Left (Unreachable (message err))
    Right inventory -> Right inventory

fetchInventoryFromHttp :: FetchConfig -> Aff (Either ApiError Inventory)
fetchInventoryFromHttp config = Request.getAbsolute config.apiEndpoint

fetchInventory :: FetchConfig -> QueryMode -> Aff (Either ApiError Inventory)
fetchInventory config = case _ of
  JsonMode -> fetchInventoryFromJson config
  HttpMode -> fetchInventoryFromHttp config
  GqlMode -> readInventoryGql
