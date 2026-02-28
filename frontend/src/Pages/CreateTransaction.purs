module Pages.CreateTransaction where

import Prelude

import API.Inventory (fetchInventory)
import Config.Entity (dummyEmployeeId, dummyLocationId)
import Config.LiveView (defaultViewConfig)
import Control.Alt ((<|>))
import Control.Monad.ST.Class (liftST)
import Data.Either (Either(..))
import Data.Maybe (fromMaybe)
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
import Services.RegisterService as RegisterService
import Services.TransactionService (startTransaction)
import Types.Inventory (InventoryResponse(..))
import UI.Inventory.ItemForm (renderError)
import UI.Transaction.CreateTransaction as TransactionUI

data PageStatus = Loading | Ready Nut | Error String

page :: Poll AuthState -> UserId -> Effect Nut
page authPoll userId = do
  Console.log "CreateTransaction: Initializing..."

  pageStatus <- liftST Poll.create
  inventoryState <- liftST Poll.create
  transactionState <- liftST Poll.create


  RegisterService.getOrInitLocalRegister
    userId
    dummyLocationId
    dummyEmployeeId
    ( \register -> do
        Console.log $ "Register ready: " <> register.registerName


        pageStatus.push $ Ready $ TransactionUI.createTransaction
          userId
          inventoryState.poll
          transactionState.poll
          register


        launchAff_ do
          txResult <- startTransaction userId
            { employeeId: fromMaybe register.registerId
                register.registerOpenedBy
            , registerId: register.registerId
            , locationId: register.registerLocationId
            }

          liftEffect $ case txResult of
            Right transaction -> do
              transactionState.push transaction
              Console.log "Transaction started"
            Left err ->
              Console.error $ "Failed to create transaction: " <> err
    )
    ( \err -> do
        Console.error $ "Register init failed: " <> err
        pageStatus.push $ Error $
          "Failed to initialize register: " <> err
    )


  launchAff_ do
    result <- fetchInventory userId
      defaultViewConfig.fetchConfig
      defaultViewConfig.mode

    liftEffect $ case result of
      Right (InventoryData inv) -> do
        Console.log "Inventory loaded for transaction page"
        inventoryState.push inv
      Right (Message msg) ->
        Console.log $ "Inventory message: " <> msg
      Left err ->
        Console.error $ "Error fetching inventory: " <> err

  pure $ (pure Loading <|> pageStatus.poll) <#~> case _ of
    Loading ->
      D.div [ DA.klass_ "loading-indicator" ]
        [ text_ "Initializing transaction..." ]
    Ready nut -> nut
    Error msg -> renderError msg