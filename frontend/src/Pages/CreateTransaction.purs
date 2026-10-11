module Pages.CreateTransaction where

import Prelude

import API.Inventory (fetchInventory)
import API.Register as RegisterApi
import API.Request as Request
import Config.LiveView (defaultViewConfig)
import Control.Parallel (parallel, sequential)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot, (<#~>))
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Services.CurrentSale as CurrentSale
import Services.RegisterService as RegisterService
import Types.Inventory (Inventory)
import Types.Register (Register)
import Types.RemoteData (RemoteData(..))
import Types.Session (SessionResponse)
import Types.Transaction.Sale as Sale
import UI.Inventory.ItemForm (renderError)
import UI.Remote (onMount)
import UI.Transaction.CreateTransaction as TransactionUI

data TxPageStatus
  = TxPageLoading
  | TxPageNeedsRegister String
  | TxPageNoSale (RemoteData Inventory) Register
  | TxPageStarting
  | TxPageReady (RemoteData Inventory) Register Sale.SaleTransaction
  | TxPageError String

-- What the sale page needs before it can show a sale:
--   a register chosen on this device (Services.RegisterService),
--   that register existing on the backend and being open,
--   a sale to work on (Services.CurrentSale).
-- Nothing here creates or opens a register, and nothing here starts a sale.
-- When a register is missing or closed the page says so and links to the
-- registers page. When this user has no open sale on the register the page
-- shows a Start Sale button (TxPageNoSale); the sale is created when that
-- button is pressed.
load :: SessionResponse -> Aff TxPageStatus
load user = do
  mRegisterId <- liftEffect RegisterService.chosenRegisterId
  case mRegisterId of
    Nothing ->
      pure (TxPageNeedsRegister "No register is selected on this device.")
    Just registerId -> do
      Tuple inventory found <- sequential $
        Tuple
          <$> parallel
            (fetchInventory defaultViewConfig.fetchConfig defaultViewConfig.mode)
          <*> parallel (RegisterApi.getRegister registerId)
      case found of
        Left err | Request.isRefusal 404 err ->
          pure $ TxPageNeedsRegister
            "The register selected on this device no longer exists."
        Left err ->
          pure $ TxPageError
            ("Could not load the register: " <> Request.describe err)
        Right register | not register.registerIsOpen ->
          pure $ TxPageNeedsRegister
            ("Register " <> register.registerName <> " is closed.")
        Right register -> do
          previous <- CurrentSale.resume user register
          pure case previous of
            Left err ->
              TxPageError
                ("Could not load the open sale: " <> Request.describe err)
            Right Nothing ->
              TxPageNoSale (inventoryState inventory) register
            Right (Just sale) ->
              TxPageReady (inventoryState inventory) register sale
  where
  inventoryState = case _ of
    Right inventory -> Success inventory
    Left err -> Failure ("Inventory unavailable: " <> Request.describe err)

-- Starts a sale on the register, for the Start Sale button.
begin :: RemoteData Inventory -> Register -> Aff TxPageStatus
begin inventory register = do
  started <- CurrentSale.startOn register
  pure case started of
    Left err ->
      TxPageError ("Could not start a sale: " <> Request.describe err)
    Right sale ->
      TxPageReady inventory register sale

-- The page runs load when it is mounted.
page :: SessionResponse -> Nut
page user = Deku.do
  setStatus /\ statusV <- useHot TxPageLoading

  D.div
    [ onMount (launchAff_ (load user >>= (liftEffect <<< setStatus))) ]
    [ statusV <#~> case _ of
        TxPageLoading ->
          D.div [ DA.klass_ "loading-indicator" ]
            [ text_ "Loading..." ]

        TxPageNeedsRegister reason ->
          D.div [ DA.klass_ "register-needed" ]
            [ D.p [ DA.klass_ "error-message" ] [ text_ reason ]
            , D.a [ DA.href_ "/#/register", DA.klass_ "btn btn-primary" ]
                [ text_ "Go to registers" ]
            ]

        TxPageNoSale inventory register ->
          D.div [ DA.klass_ "no-sale" ]
            [ D.p_
                [ text_
                    ( "Register " <> register.registerName
                        <> " is open. No sale is in progress."
                    )
                ]
            , D.button
                [ DA.klass_ "btn btn-primary"
                , DL.click_ \_ -> do
                    setStatus TxPageStarting
                    launchAff_
                      (begin inventory register >>= (liftEffect <<< setStatus))
                ]
                [ text_ "Start Sale" ]
            ]

        TxPageStarting ->
          D.div [ DA.klass_ "loading-indicator" ]
            [ text_ "Starting sale..." ]

        TxPageError err ->
          renderError err

        TxPageReady inventory register sale ->
          TransactionUI.createTransaction inventory sale register
    ]