module Pages.CreateTransaction where

import Prelude

import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Hooks ((<#~>))
import FRP.Poll (Poll)
import Services.AuthService (AuthState, UserId)
import Types.Inventory (Inventory)
import Types.Register (Register)
import Types.Transaction (Transaction)
import UI.Inventory.ItemForm (renderError)
import UI.Transaction.CreateTransaction as TransactionUI

data TxPageStatus
  = TxPageLoading
  | TxPageReady Inventory Register Transaction
  | TxPageError String

page :: Poll AuthState -> UserId -> Poll TxPageStatus -> Nut
page _authPoll userId statusPoll =
  statusPoll <#~> case _ of
    TxPageLoading ->
      D.div [ DA.klass_ "loading-indicator" ]
        [ text_ "Initializing transaction..." ]
    TxPageError err ->
      renderError err
    TxPageReady inventory register transaction ->
      TransactionUI.createTransaction userId
        (pure inventory)
        (pure transaction)
        register