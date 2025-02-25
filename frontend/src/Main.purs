module Main where

import Prelude

import API (fetchInventory)
import Control.Monad.ST.Class (liftST)
import CreateItem (createItem)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst, snd)
import Deku.Core (fixed)
import Deku.DOM as D
import Deku.Hooks (cycle)
import Deku.Toplevel (runInBody)
import EditItem (editItem)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import FRP.Poll as Poll
import MenuLiveView (createMenuLiveView)
import Route (Route(..), nav, route)
import Routing.Duplex (parse)
import Routing.Hash (matchesWith)
import Types (InventoryResponse(..))
import Types.LiveViewConfig (defaultViewConfig)
import UUIDGen (genUUID)

testItemUUID :: String
testItemUUID = "56b0d1f7-fa3b-4cd4-9e58-79e4724295b0"

main :: Effect Unit
main = do
  Console.log "Application starting"

  currentRoute <- liftST Poll.create
  inventoryState <- liftST Poll.create
  loadingState <- liftST Poll.create
  errorState <- liftST Poll.create


  currentUUID <- liftST Poll.create


  initialUUID <- genUUID
  let initialUUIDStr = show initialUUID
  Console.log $ "Initial UUID generated: " <> initialUUIDStr
  currentUUID.push initialUUIDStr

  let menuLiveView = createMenuLiveView inventoryState.poll loadingState.poll errorState.poll

  let routeToComponent = case _ of
        LiveView -> menuLiveView
        Create -> createItem currentUUID.poll
        Edit uuid -> editItem (if uuid == "test" then testItemUUID else uuid)

  let
    matcher _ r = do
      Console.log $ "Route changed to: " <> show r


      when (r == Create) do
        newUUID <- genUUID
        let newUUIDStr = show newUUID
        Console.log $ "Generated new UUID for Create page: " <> newUUIDStr
        currentUUID.push newUUIDStr

      currentRoute.push $ Tuple r (routeToComponent r)

      case r of
        LiveView -> do

          loadingState.push true
          errorState.push ""

          launchAff_ do
            liftEffect $ Console.log "Loading inventory data..."
            result <- fetchInventory defaultViewConfig.fetchConfig defaultViewConfig.mode

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

        _ -> pure unit

  void $ matchesWith (parse route) matcher

  void $ runInBody
    ( fixed
        [ nav (fst <$> currentRoute.poll)
        , D.div_ [ cycle (snd <$> currentRoute.poll) ]
        ]
    )

  matcher Nothing LiveView