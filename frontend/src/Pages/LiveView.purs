module Pages.LiveView where

import Prelude

import API.Inventory (fetchInventory)
import Config.LiveView (defaultViewConfig)
import Control.Monad.ST.Class (liftST)
import Data.Either (Either(..))
import Deku.Core (Nut)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import FRP.Poll (Poll)
import FRP.Poll as Poll
import Services.AuthService (AuthState, UserId)
import Types.Inventory (InventoryResponse(..))
import UI.Inventory.MenuLiveView (createMenuLiveView)

page :: Poll AuthState -> UserId -> Effect Nut
page _authPoll userId = do
  inventoryState <- liftST Poll.create
  loadingState <- liftST Poll.create
  errorState <- liftST Poll.create

  loadingState.push true
  errorState.push ""

  launchAff_ do
    liftEffect $ Console.log "LiveView: Loading inventory..."
    result <- fetchInventory userId
      defaultViewConfig.fetchConfig
      defaultViewConfig.mode

    liftEffect $ case result of
      Left err -> do
        Console.error $ "Error fetching inventory: " <> err
        loadingState.push false
        errorState.push $ "Error: " <> err
      Right (InventoryData inv) -> do
        Console.log "Loaded inventory successfully"
        inventoryState.push inv
        loadingState.push false
      Right (Message msg) -> do
        Console.log $ "Received message: " <> msg
        loadingState.push false
        errorState.push msg

  pure $ createMenuLiveView inventoryState.poll loadingState.poll errorState.poll