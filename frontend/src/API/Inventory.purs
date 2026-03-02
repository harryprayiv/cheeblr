module API.Inventory where

import Prelude

import API.Request as Request
import Config.LiveView (QueryMode(..), FetchConfig)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff, attempt)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Now (now)
import Fetch (fetch)
import Fetch.Yoga.Json (fromJSON)
import Services.AuthService (UserId)
import Types.Inventory (Inventory, InventoryResponse(..), MenuItem)

writeInventory :: UserId -> MenuItem -> Aff (Either String InventoryResponse)
writeInventory userId menuItem =
  Request.authPost userId "/inventory" menuItem

readInventory :: UserId -> Aff (Either String InventoryResponse)
readInventory userId =
  Request.authGet userId "/inventory"

updateInventory :: UserId -> MenuItem -> Aff (Either String InventoryResponse)
updateInventory userId menuItem =
  Request.authPut userId "/inventory" menuItem

deleteInventory :: UserId -> String -> Aff (Either String InventoryResponse)
deleteInventory userId itemId =
  Request.authDelete userId ("/inventory/" <> itemId)

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
    Right inventory -> Right $ InventoryData inventory Nothing

fetchInventoryFromHttp :: UserId -> FetchConfig -> Aff (Either String InventoryResponse)
fetchInventoryFromHttp userId config =
  Request.authGetFullUrl userId config.apiEndpoint

fetchInventory
  :: UserId -> FetchConfig -> QueryMode -> Aff (Either String InventoryResponse)
fetchInventory userId config = case _ of
  JsonMode -> fetchInventoryFromJson config
  HttpMode -> fetchInventoryFromHttp userId config