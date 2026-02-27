module Pages.TransactionHistory where

import Prelude

import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Effect (Effect)

page :: Effect Nut
page = pure $ D.div_ [ text_ "Transaction History - Coming Soon" ]