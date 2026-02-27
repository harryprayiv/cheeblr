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
import Effect.Ref (Ref)
import FRP.Poll as Poll
import Services.AuthService (AuthContext)
import Services.RegisterService as RegisterService
import Services.TransactionService (startTransaction)
import Types.Inventory (InventoryResponse(..))
import UI.Inventory.EditItem (renderError)
import UI.Transaction.CreateTransaction as TransactionUI

data PageStatus = Loading | Ready Nut | Error String

page :: Ref AuthContext -> Effect Nut
page authRef = do
  Console.log "CreateTransaction: Initializing..."

  pageStatus <- liftST Poll.create
  inventoryState <- liftST Poll.create
  transactionState <- liftST Poll.create

  -- Initialize register, then wire up transaction UI
  RegisterService.getOrInitLocalRegister
    authRef
    dummyLocationId
    dummyEmployeeId
    ( \register -> do
        Console.log $ "Register ready: " <> register.registerName

        -- Push the fully-wired transaction UI
        pageStatus.push $ Ready $ TransactionUI.createTransaction
          authRef
          inventoryState.poll
          transactionState.poll
          register

        -- Start a new transaction
        launchAff_ do
          txResult <- startTransaction authRef
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

  -- Fetch inventory in parallel
  launchAff_ do
    result <- fetchInventory authRef
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