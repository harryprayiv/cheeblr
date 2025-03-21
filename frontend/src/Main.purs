module Main where

import Prelude

import API.Inventory (fetchInventory, readInventory)
import Control.Monad.ST.Class (liftST)
import CreateItem (createItem)
import Data.Array (find, length)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst, snd)
import Deku.Core (fixed)
import Deku.DOM as D
import Deku.Hooks (cycle)
import Deku.Toplevel (runInBody)
import DeleteItem (renderDeleteConfirmation)
import EditItem (editItem, renderError)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import FRP.Poll as Poll
import MenuLiveView (createMenuLiveView)
import Route (Route(..), nav, route)
import Routing.Duplex (parse)
import Routing.Hash (matchesWith)
import Types.Inventory (Inventory(..), InventoryResponse(..), MenuItem(..))
import Config.LiveView (defaultViewConfig)
import Utils.UUIDGen (genUUID)
import UI.Transaction.CreateTransaction (createTransaction)
import UI.Transaction.TransactionHistory (transactionHistory)
import UI.Transaction.LiveCart (liveCart)

testItemUUID :: String
testItemUUID = "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"

main :: Effect Unit
main = do
  Console.log "Application starting"

  currentRoute <- liftST Poll.create
  inventoryState <- liftST Poll.create
  loadingState <- liftST Poll.create
  errorState <- liftST Poll.create

  let
    menuLiveView = createMenuLiveView inventoryState.poll loadingState.poll
      errorState.poll

  let
    matcher _ r = do
      Console.log $ "Route changed to: " <> show r

      case r of
        LiveView -> do
          currentRoute.push $ Tuple r menuLiveView

          loadingState.push true
          errorState.push ""

          launchAff_ do
            liftEffect $ Console.log "Loading inventory data..."
            result <- fetchInventory defaultViewConfig.fetchConfig
              defaultViewConfig.mode

            liftEffect $ case result of
              Left err -> do
                Console.error $ "Error fetching inventory: " <> err
                loadingState.push false
                errorState.push $ "Error: " <> err

              Right (InventoryData inv) -> do
                Console.log $ "Loaded inventory successfully"
                inventoryState.push inv
                loadingState.push false

              Right (Message msg) -> do
                Console.log $ "Received message: " <> msg
                loadingState.push false
                errorState.push msg

        Create -> do
          newUUID <- genUUID
          let newUUIDStr = show newUUID
          Console.log $ "Generated new UUID for Create page: " <> newUUIDStr
          currentRoute.push $ Tuple r (createItem newUUIDStr)

        Edit uuid -> do
          let actualUuid = if uuid == "test" then testItemUUID else uuid
          Console.log $ "Loading item with UUID: " <> actualUuid

          loadingState.push true
          launchAff_ do
            liftEffect $ Console.log "Fetching inventory for edit..."
            result <- readInventory

            liftEffect case result of
              Right (InventoryData (Inventory items)) -> do
                Console.log $ "Found " <> show (length items) <>
                  " items in inventory"

                case
                  find (\(MenuItem item) -> show item.sku == actualUuid) items
                  of
                  Just menuItem -> do
                    Console.log $ "Found item with UUID: " <> actualUuid
                    currentRoute.push $ Tuple r (editItem menuItem)
                  Nothing -> do
                    Console.error $ "Item with UUID " <> actualUuid <>
                      " not found"
                    errorState.push $ "Error: Item with UUID " <> actualUuid <>
                      " not found"
                    currentRoute.push $ Tuple r
                      ( renderError $ "Item with UUID " <> actualUuid <>
                          " not found"
                      )

              Right (Message msg) -> do
                Console.error $ "API error: " <> msg
                errorState.push $ "API error: " <> msg
                currentRoute.push $ Tuple r (renderError $ "API error: " <> msg)

              Left err -> do
                Console.error $ "Failed to fetch inventory: " <> err
                errorState.push $ "Failed to fetch inventory: " <> err
                currentRoute.push $ Tuple r
                  (renderError $ "Failed to fetch inventory: " <> err)

            liftEffect $ loadingState.push false

        Delete uuid -> do
          let actualUuid = if uuid == "test" then testItemUUID else uuid
          Console.log $ "Loading item with UUID: " <> actualUuid <>
            " for deletion"

          loadingState.push true
          launchAff_ do
            liftEffect $ Console.log
              "Fetching inventory for delete confirmation..."
            result <- readInventory

            liftEffect case result of
              Right (InventoryData (Inventory items)) -> do
                Console.log $ "Found " <> show (length items) <>
                  " items in inventory"

                case
                  find (\(MenuItem item) -> show item.sku == actualUuid) items
                  of
                  Just (MenuItem item) -> do
                    Console.log $ "Found item with UUID: " <> actualUuid
                    currentRoute.push $ Tuple r
                      (renderDeleteConfirmation actualUuid item.name)
                  Nothing -> do
                    Console.error $ "Item with UUID " <> actualUuid <>
                      " not found"
                    errorState.push $ "Error: Item with UUID " <> actualUuid <>
                      " not found"
                    currentRoute.push $ Tuple r
                      ( renderError $ "Item with UUID " <> actualUuid <>
                          " not found"
                      )

              Right (Message msg) -> do
                Console.error $ "API error: " <> msg
                errorState.push $ "API error: " <> msg
                currentRoute.push $ Tuple r (renderError $ "API error: " <> msg)

              Left err -> do
                Console.error $ "Failed to fetch inventory: " <> err
                errorState.push $ "Failed to fetch inventory: " <> err
                currentRoute.push $ Tuple r
                  (renderError $ "Failed to fetch inventory: " <> err)

            liftEffect $ loadingState.push false

        CreateTransaction -> do
          Console.log "Navigating to Create Transaction page"
          currentRoute.push $ Tuple r createTransaction

        TransactionHistory -> do
          Console.log "Navigating to Transaction History page"
          currentRoute.push $ Tuple r transactionHistory
          
        InventorySelector -> do
          Console.log "Navigating to Inventory Selector page"
          
          loadingState.push true
          errorState.push ""
          
          let dummyUpdateFunction items = do
                Console.log $ "Selected " <> show (length items) <> " items"
          
          -- Create the component with the inventory poll
          currentRoute.push $ Tuple r (liveCart dummyUpdateFunction inventoryState.poll)
          
          -- Fetch inventory data
          launchAff_ do
            result <- fetchInventory defaultViewConfig.fetchConfig defaultViewConfig.mode
            
            liftEffect $ case result of
              Left err -> do
                Console.error $ "Error fetching inventory: " <> err
                loadingState.push false
                errorState.push $ "Error: " <> err
              
              Right (InventoryData inv@(Inventory items)) -> do
                Console.log $ "Loaded inventory successfully"
                inventoryState.push inv 
                loadingState.push false
              
              Right (Message msg) -> do
                Console.log $ "Received message: " <> msg
                loadingState.push false
                errorState.push msg

  void $ matchesWith (parse route) matcher

  void $ runInBody
    ( fixed
        [ nav (fst <$> currentRoute.poll)
        , D.div_ [ cycle (snd <$> currentRoute.poll) ]
        ]
    )

  matcher Nothing LiveView