module API.Inventory where

import Prelude

import API.Request as Request
import Config.LiveView (QueryMode(..), FetchConfig)
import Data.Either (Either(..))
import Effect.Aff (Aff, attempt)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Now (now)
import Fetch (fetch)
import Fetch.Yoga.Json (fromJSON)
import GraphQL.API.Inventory (readInventoryGql)
import Services.AuthService (UserId)
import Types.Inventory (Inventory, MenuItem, MutationResponse)
import Types.Session (SessionResponse)

writeInventory :: UserId -> MenuItem -> Aff (Either String MutationResponse)
writeInventory userId menuItem =
  Request.authPost userId "/inventory" menuItem

readInventory :: UserId -> Aff (Either String Inventory)
readInventory userId =
  Request.authGet userId "/inventory"

updateInventory :: UserId -> MenuItem -> Aff (Either String MutationResponse)
updateInventory userId menuItem =
  Request.authPut userId "/inventory" menuItem

deleteInventory :: UserId -> String -> Aff (Either String MutationResponse)
deleteInventory userId itemId =
  Request.authDelete userId ("/inventory/" <> itemId)

fetchSession :: UserId -> Aff (Either String SessionResponse)
fetchSession userId =
  Request.authGet userId "/session"

fetchInventoryFromJson :: FetchConfig -> Aff (Either String Inventory)
fetchInventoryFromJson config = do
  result <- attempt do
    timestamp <- liftEffect $ show <$> now
    let url = config.jsonPath <> "?t=" <> timestamp
    liftEffect $ Console.log ("Fetching from JSON: " <> url)
    response <- fetch url {}
    fromJSON response.json :: Aff Inventory
  pure case result of
    Left err -> Left $ "JSON fetch error: " <> show err
    Right inventory -> Right inventory

fetchInventoryFromHttp :: UserId -> FetchConfig -> Aff (Either String Inventory)
fetchInventoryFromHttp userId config =
  Request.authGetFullUrl userId config.apiEndpoint

-- fetchInventory
--   :: UserId -> FetchConfig -> QueryMode -> Aff (Either String Inventory)
-- fetchInventory userId config = case _ of
--   JsonMode -> fetchInventoryFromJson config
--   HttpMode -> fetchInventoryFromHttp userId config

fetchInventory
  :: UserId -> FetchConfig -> QueryMode -> Aff (Either String Inventory)
fetchInventory userId config = case _ of
  JsonMode -> fetchInventoryFromJson config
  HttpMode -> fetchInventoryFromHttp userId config
  GqlMode  -> readInventoryGql userId