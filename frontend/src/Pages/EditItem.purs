module Pages.EditItem where

import Prelude

import API.Inventory (readInventory)
import Control.Alt ((<|>))
import Control.Monad.ST.Class (liftST)
import Data.Array (find, length)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Hooks ((<#~>))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import FRP.Poll (Poll)
import FRP.Poll as Poll
import Services.AuthService (AuthState, UserId)
import Types.Inventory (Inventory(..), InventoryResponse(..), MenuItem(..))
import UI.Inventory.ItemForm (FormMode(..), itemForm)

testItemUUID :: String
testItemUUID = "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"

data PageStatus = Loading | Ready Nut | Error String

page :: Poll AuthState -> UserId -> String -> Effect Nut
page _authPoll userId rawUuid = do
  let uuid = if rawUuid == "test" then testItemUUID else rawUuid
  status <- liftST Poll.create

  Console.log $ "EditItem: Loading item " <> uuid

  launchAff_ do
    result <- readInventory userId
    liftEffect $ case result of
      Right (InventoryData (Inventory items)) -> do
        Console.log $ "Found " <> show (length items) <> " items"
        case find (\(MenuItem item) -> show item.sku == uuid) items of
          Just menuItem -> do
            Console.log $ "Found item: " <> uuid
            status.push (Ready (itemForm userId (EditMode menuItem)))
          Nothing -> do
            Console.error $ "Item not found: " <> uuid
            status.push (Error $ "Item with UUID " <> uuid <> " not found")
      Right (Message msg) ->
        status.push (Error $ "API error: " <> msg)
      Left err ->
        status.push (Error $ "Failed to fetch inventory: " <> err)

  pure $ (pure Loading <|> status.poll) <#~> case _ of
    Loading ->
      D.div [ DA.klass_ "loading-indicator" ] [ text_ "Loading item..." ]
    Ready nut -> nut
    Error msg ->
      D.div [ DA.klass_ "error-message bg-red-100 border-l-4 border-red-500 text-red-700 p-4" ]
        [ text_ $ "Error: " <> msg ]