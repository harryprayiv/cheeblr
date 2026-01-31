module API.Inventory where

import Prelude

import Data.Either (Either(..))
import Effect.Aff (Aff, attempt)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Now (now)
import Effect.Ref (Ref)
import Fetch (Method(..), fetch)
import Fetch.Yoga.Json (fromJSON)
import NetworkConfig (currentConfig)
import Services.AuthService (AuthContext, getCurrentUserId)
import Types.Inventory (Inventory, InventoryResponse(..), MenuItem)
import Config.LiveView (QueryMode(..), FetchConfig)
import Yoga.JSON (writeJSON)

baseUrl :: String
baseUrl = currentConfig.apiBaseUrl

-- | Get the current user ID as a string for the X-User-Id header
getUserIdHeader :: Ref AuthContext -> Aff String
getUserIdHeader authRef = liftEffect $ show <$> getCurrentUserId authRef

writeInventory :: Ref AuthContext -> MenuItem -> Aff (Either String InventoryResponse)
writeInventory authRef menuItem = do
  userId <- getUserIdHeader authRef
  result <- attempt do
    let content = writeJSON menuItem
    liftEffect $ Console.log "Creating new menu item..."
    liftEffect $ Console.log $ "Sending content: " <> content

    response <- fetch (baseUrl <> "/inventory")
      { method: POST
      , body: content
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

  pure case result of
    Left err -> Left $ "Create error: " <> show err
    Right response -> Right response

readInventory :: Ref AuthContext -> Aff (Either String InventoryResponse)
readInventory authRef = do
  userId <- getUserIdHeader authRef
  result <- attempt do
    liftEffect $ Console.log $ "Fetching inventory from: " <> baseUrl <>
      "/inventory"
    response <- fetch (baseUrl <> "/inventory")
      { method: GET
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    liftEffect $ Console.log "Got response, parsing JSON..."
    inventoryResponse <- fromJSON response.json :: Aff InventoryResponse
    liftEffect $ Console.log "Successfully parsed inventory response"
    pure inventoryResponse

  pure case result of
    Left err -> Left $ "Failed to read inventory: " <> show err
    Right response -> Right response

updateInventory :: Ref AuthContext -> MenuItem -> Aff (Either String InventoryResponse)
updateInventory authRef menuItem = do
  userId <- getUserIdHeader authRef
  result <- attempt do
    let content = writeJSON menuItem
    liftEffect $ Console.log "Updating menu item..."
    liftEffect $ Console.log $ "Sending content: " <> content

    response <- fetch (baseUrl <> "/inventory")
      { method: PUT
      , body: content
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }

    fromJSON response.json :: Aff InventoryResponse

  pure case result of
    Left err -> Left $ "Update error: " <> show err
    Right response -> Right response

deleteInventory :: Ref AuthContext -> String -> Aff (Either String InventoryResponse)
deleteInventory authRef itemId = do
  userId <- getUserIdHeader authRef
  result <- attempt do
    response <- fetch (baseUrl <> "/inventory/" <> itemId)
      { method: DELETE
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json :: Aff InventoryResponse

  pure case result of
    Left err -> Left $ "Delete error: " <> show err
    Right response -> Right response

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

fetchInventoryFromHttp :: Ref AuthContext -> FetchConfig -> Aff (Either String InventoryResponse)
fetchInventoryFromHttp authRef config = do
  userId <- getUserIdHeader authRef
  liftEffect $ Console.log "Starting HTTP fetch..."
  liftEffect $ Console.log $ "Using endpoint: " <> config.apiEndpoint
  result <- attempt do
    liftEffect $ Console.log "Making fetch request..."

    response <- fetch config.apiEndpoint
      { method: GET
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }

    liftEffect $ Console.log "Got response, parsing JSON..."
    parsed <- fromJSON response.json :: Aff InventoryResponse
    liftEffect $ Console.log "Successfully parsed response"
    pure parsed

  case result of
    Left err -> do
      liftEffect $ Console.error $ "API fetch error details: " <> show err
      pure $ Left $ "API fetch error: " <> show err
    Right response -> do
      liftEffect $ Console.log "Success: Got inventory data"
      pure $ Right response

fetchInventory
  :: Ref AuthContext -> FetchConfig -> QueryMode -> Aff (Either String InventoryResponse)
fetchInventory authRef config = case _ of
  JsonMode -> do
    liftEffect $ Console.log "Using JSON mode (local file)"
    fetchInventoryFromJson config
  HttpMode -> do
    liftEffect $ Console.log "Using HTTP mode (backend API)"
    fetchInventoryFromHttp authRef config