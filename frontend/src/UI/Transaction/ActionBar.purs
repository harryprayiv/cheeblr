module UI.Transaction.ActionBar
  ( ActionProps
  , actionBar
  ) where

import Prelude

import Data.Array (null)
import Data.Finance.Money (Discrete(..))
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Effect (Effect)
import FRP.Poll (Poll)
import Types.Primitives.Money (saleMoneyDiscrete)
import Types.Transaction.Sale as Sale
import UI.Transaction.Model (Activity, finalizeBlockers, isBusy, isOpen, remainingCents)
import Utils.Money (formatDiscretePrice)

type ActionProps =
  { sale :: Poll Sale.SaleTransaction
  , activity :: Poll Activity
  , clear :: Effect Unit
  , finalize :: Effect Unit
  , newSale :: Effect Unit
  }

-- Clear Items, the remaining balance, and Process Payment. Process Payment
-- is enabled only when finalizeBlockers is empty and no request is running.
-- Once the sale is closed, Process Payment is hidden and New Sale takes its
-- place.
actionBar :: ActionProps -> Nut
actionBar props =
  D.div [ DA.klass_ "action-bar" ]
    [ D.button
        [ DA.klass_ "cancel-btn"
        , DA.disabled $ canClear <#> \ok -> if ok then "" else "true"
        , DL.click_ \_ -> props.clear
        ]
        [ text_ "Clear Items" ]

    , D.div [ DA.klass_ "payment-summary" ]
        [ D.div [ DA.klass_ "remaining-balance" ]
            [ D.div [ DA.klass_ "remaining-label" ] [ text_ "Remaining:" ]
            , D.div
                [ DA.klass $ remaining <#> \r ->
                    "remaining-amount " <> if r <= 0 then "paid" else "unpaid"
                ]
                [ text (remaining <#> \r -> formatDiscretePrice (Discrete r)) ]
            ]
        ]

    , D.button
        [ DA.klass $ open <#> \o -> if o then "checkout-btn" else "hidden"
        , DA.disabled $ canFinalize <#> \ok -> if ok then "" else "true"
        , DL.runOn DL.click $ canFinalize <#> \ok ->
            if ok then props.finalize else pure unit
        ]
        [ text $ props.sale <#> \sale ->
            "Process Payment " <>
              formatDiscretePrice (saleMoneyDiscrete sale.saleTotal)
        ]

    , D.button
        [ DA.klass $ open <#> \o -> if o then "hidden" else "checkout-btn"
        , DA.disabled $ busy <#> \b -> if b then "true" else ""
        , DL.runOn DL.click $ busy <#> \b ->
            if b then pure unit else props.newSale
        ]
        [ text_ "New Sale" ]
    ]
  where
  remaining = remainingCents <$> props.sale

  open = props.sale <#> \sale -> isOpen sale.saleStatus

  busy = isBusy <$> props.activity

  canClear =
    ( \sale activity ->
        not (isBusy activity)
          && isOpen sale.saleStatus
          && not (null sale.saleItems)
    )
      <$> props.sale
      <*> props.activity

  canFinalize =
    ( \sale activity ->
        not (isBusy activity) && null (finalizeBlockers sale)
    )
      <$> props.sale
      <*> props.activity