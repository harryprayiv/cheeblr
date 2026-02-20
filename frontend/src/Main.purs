module Main where

import Prelude

import API.Inventory (fetchInventory, readInventory)
import Config.Entity (dummyEmployeeId, dummyLocationId)
import Config.LiveView (defaultViewConfig)
import Control.Monad.ST.Class (liftST)
import UI.Inventory.CreateItem (createItem)
import Data.Array (find, length)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Tuple (Tuple(..), fst, snd)
import Deku.Core (fixed, text_)
import Deku.DOM as D
import Deku.Hooks (cycle)
import Deku.Toplevel (runInBody)
import UI.Inventory.DeleteItem (renderDeleteConfirmation)
import UI.Inventory.EditItem (editItem, renderError)
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import FRP.Poll as Poll
import UI.Inventory.MenuLiveView (createMenuLiveView)
import UI.Route (Route(..), nav, route)
import Routing.Duplex (parse)
import Routing.Hash (matchesWith)
import Services.AuthService (newAuthRef)
import Services.RegisterService as RegisterService
import Services.TransactionService (startTransaction)
import Types.Inventory (Inventory(..), InventoryResponse(..), MenuItem(..))
import UI.Transaction.CreateTransaction (createTransaction)
import UI.Transaction.LiveCart (liveCart)
import Utils.UUID (genUUID)

testItemUUID :: String
testItemUUID = "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"

run :: forall a r. Aff a -> { push :: a -> Effect Unit | r } -> Aff Unit
run aff { push } = aff >>= liftEffect <<< push

main :: Effect Unit
main = do
  -- Create auth context ref (shared across all components)
  authRef <- newAuthRef

  currentRoute <- liftST Poll.create
  inventoryState <- liftST Poll.create
  loadingState <- liftST Poll.create
  errorState <- liftST Poll.create
  registerState <- liftST Poll.create

  RegisterService.initLocalRegister
    authRef
    dummyLocationId
    dummyEmployeeId
    ( \register -> do
        Console.log "Register initialized at application startup"
        registerState.push (Just register)
    )
    ( \err -> do
        Console.error $ "Failed to initialize register at startup: " <> err
        registerState.push Nothing
    )

  let
    menuLiveView = createMenuLiveView
      inventoryState.poll
      loadingState.poll
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
            result <- fetchInventory authRef defaultViewConfig.fetchConfig
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
          currentRoute.push $ Tuple r (createItem authRef newUUIDStr)

        Edit uuid -> do
          let actualUuid = if uuid == "test" then testItemUUID else uuid
          Console.log $ "Loading item with UUID: " <> actualUuid

          loadingState.push true
          launchAff_ do
            liftEffect $ Console.log "Fetching inventory for edit..."
            result <- readInventory authRef

            liftEffect case result of
              Right (InventoryData (Inventory items)) -> do
                Console.log $ "Found " <> show (length items) <>
                  " items in inventory"

                case
                  find (\(MenuItem item) -> show item.sku == actualUuid) items
                  of
                  Just menuItem -> do
                    Console.log $ "Found item with UUID: " <> actualUuid
                    currentRoute.push $ Tuple r (editItem authRef menuItem)
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
            result <- readInventory authRef

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
                      (renderDeleteConfirmation authRef actualUuid item.name)
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

        LiveCart -> do
          Console.log "Navigating to Inventory Selector page"

          loadingState.push true
          errorState.push ""

          let
            showUpdateFunction items = do
              Console.log $ "Selected " <> show (length items) <> " items"

          currentRoute.push $ Tuple r
            (liveCart showUpdateFunction inventoryState.poll)

          launchAff_ do
            result <- fetchInventory authRef defaultViewConfig.fetchConfig
              defaultViewConfig.mode

            liftEffect $ case result of
              Left err -> do
                Console.error $ "Error fetching inventory: " <> err
                loadingState.push false
                errorState.push $ "Error: " <> err

              Right (InventoryData inv@(Inventory items)) -> do
                Console.log $ "Loaded inventory successfully for LiveCart"
                inventoryState.push inv
                loadingState.push false

              Right (Message msg) -> do
                Console.log $ "Received message: " <> msg
                loadingState.push false
                errorState.push msg

        CreateTransaction -> do
          Console.log "Navigating to Create Transaction page"

          loadingState.push true
          errorState.push ""

          transactionState <- liftST Poll.create

          -- Create the component FIRST with empty polls (just like LiveCart does)
          RegisterService.getOrInitLocalRegister
            authRef
            dummyLocationId
            dummyEmployeeId
            ( \register -> do
                -- Push the route IMMEDIATELY with the polls
                currentRoute.push $ Tuple r
                  ( createTransaction authRef inventoryState.poll
                      transactionState.poll
                      register
                  )
                
                -- NOW start the transaction (it will update transactionState.poll)
                launchAff_ do
                  txResult <- startTransaction authRef
                    { employeeId: fromMaybe register.registerId register.registerOpenedBy
                    , registerId: register.registerId
                    , locationId: register.registerLocationId
                    }

                  liftEffect case txResult of
                    Right transaction -> do
                      transactionState.push transaction
                      Console.log "Transaction started and pushed to poll"
                    Left txErr -> do
                      Console.error $ "Failed to create transaction: " <> txErr
                      errorState.push $ "Error: " <> txErr
            )
            ( \errMsg -> do
                errorState.push $ "Error: " <> errMsg
                currentRoute.push $ Tuple r
                  (renderError $ "Failed to initialize register: " <> errMsg)
            )

          -- NOW fetch inventory (exactly like LiveCart does)
          launchAff_ do
            result <- fetchInventory authRef defaultViewConfig.fetchConfig
              defaultViewConfig.mode

            liftEffect $ case result of
              Right (InventoryData inv) -> do
                Console.log "Pushing inventory to poll"
                inventoryState.push inv
                loadingState.push false
              Right (Message msg) -> do
                Console.log $ "Received message: " <> msg
                loadingState.push false
              Left err -> do
                Console.error $ "Error fetching inventory: " <> err
                loadingState.push false

        TransactionHistory -> do
          Console.log "Navigating to Transaction History page"
          currentRoute.push $ Tuple r
            (D.div_ [ text_ "Transaction History - Coming Soon" ])

  void $ matchesWith (parse route) matcher

  void $ runInBody
    ( fixed
        [ nav (fst <$> currentRoute.poll)
        , D.div_ [ cycle (snd <$> currentRoute.poll) ]
        ]
    )

  matcher Nothing LiveView