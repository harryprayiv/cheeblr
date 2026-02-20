module Cheeblr.UI.Transaction.PaymentForm where

import Prelude

import Cheeblr.Core.Cart (CartTotals, remainingBalance, isFullyPaid, totalPayments)
import Cheeblr.Core.Money (formatCurrency, toDollars)
import Cheeblr.UI.FormHelpers (getInputValue, getSelectValue)
import Data.Array (null)
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete)
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useState, (<#~>))
import Effect (Effect)
import FRP.Poll (Poll)

----------------------------------------------------------------------
-- Payment Method
----------------------------------------------------------------------

data PaymentMethod = Cash | Card | Other

derive instance Eq PaymentMethod

instance Show PaymentMethod where
  show Cash = "Cash"
  show Card = "Card"
  show Other = "Other"

parsePaymentMethod :: String -> PaymentMethod
parsePaymentMethod "Cash" = Cash
parsePaymentMethod "Card" = Card
parsePaymentMethod _ = Other

----------------------------------------------------------------------
-- Payment Entry
----------------------------------------------------------------------

type PaymentEntry =
  { method :: PaymentMethod
  , amount :: Discrete USD
  }

----------------------------------------------------------------------
-- Payment Form Component
----------------------------------------------------------------------

paymentForm
  :: Poll CartTotals
  -> Poll (Array (Discrete USD))        -- existing payments
  -> (PaymentEntry -> Effect Unit)       -- on add payment
  -> (Effect Unit)                       -- on finalize
  -> Nut
paymentForm totalsPoll paymentsPoll onAddPayment onFinalize = Deku.do
  setAmount /\ amountPoll <- useState ""
  setMethod /\ methodPoll <- useState "Cash"
  setError /\ errorPoll <- useState ""

  let
    handleAddPayment :: Effect Unit
    handleAddPayment = do
      -- Read current amount from the input
      -- In practice this needs the STRef pattern or to be called
      -- from within a reactive context. Simplified here.
      pure unit

  D.div
    [ DA.klass_ "payment-form" ]
    [ D.h3_ [ text_ "Payment" ]

    -- Remaining balance display
    , ((/\) <$> totalsPoll <*> paymentsPoll) <#~> \(totals /\ payments) ->
        let
          remaining = remainingBalance totals payments
          paid = totalPayments payments
        in
          D.div
            [ DA.klass_ "payment-summary" ]
            [ summaryRow "Order Total" (formatCurrency totals.total)
            , if not (null payments) then
                summaryRow "Paid" (formatCurrency paid)
              else D.span_ []
            , summaryRow "Remaining" (formatCurrency remaining)
            ]

    -- Payment method selector
    , D.div
        [ DA.klass_ "payment-method-row" ]
        [ D.label_ [ text_ "Method" ]
        , D.select
            [ DA.klass_ "payment-method-select"
            , DL.change_ \evt -> do
                val <- getSelectValue evt
                setMethod val
            ]
            [ D.option [ DA.value_ "Cash" ] [ text_ "Cash" ]
            , D.option [ DA.value_ "Card" ] [ text_ "Card" ]
            ]
        ]

    -- Amount input
    , D.div
        [ DA.klass_ "payment-amount-row" ]
        [ D.label_ [ text_ "Amount" ]
        , D.input
            [ DA.klass_ "payment-amount-input"
            , DA.xtype_ "text"
            , DA.placeholder_ "0.00"
            , DA.value amountPoll
            , DL.input_ \evt -> do
                val <- getInputValue evt
                setAmount val
                setError ""
            ] []
        ]

    -- Quick amount buttons
    , totalsPoll <#~> \totals ->
        D.div
          [ DA.klass_ "payment-quick-amounts" ]
          [ quickButton "Exact" (formatAmount totals.total) setAmount
          ]

    -- Error display
    , errorPoll <#~> \err ->
        if err == "" then D.span_ []
        else D.div [ DA.klass_ "payment-error" ] [ text_ err ]

    -- Add Payment button
    , D.button
        [ DA.klass_ "payment-add-btn"
        , DL.click_ \_ -> pure unit
            -- Actual implementation: read amountPoll and methodPoll
            -- via STRef, validate, call onAddPayment
        ]
        [ text_ "Add Payment" ]

    -- Finalize button (only when fully paid)
    , ((/\) <$> totalsPoll <*> paymentsPoll) <#~> \(totals /\ payments) ->
        if isFullyPaid totals payments then
          D.button
            [ DA.klass_ "payment-finalize-btn"
            , DL.click_ \_ -> onFinalize
            ]
            [ text_ "Complete Transaction" ]
        else
          D.span_ []
    ]

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

summaryRow :: String -> String -> Nut
summaryRow lbl amount =
  D.div
    [ DA.klass_ "payment-summary-row" ]
    [ D.span_ [ text_ lbl ]
    , D.span_ [ text_ amount ]
    ]

quickButton :: String -> String -> (String -> Effect Unit) -> Nut
quickButton lbl amount setAmount =
  D.button
    [ DA.klass_ "payment-quick-btn"
    , DL.click_ \_ -> setAmount amount
    ]
    [ text_ lbl ]

formatAmount :: Discrete USD -> String
formatAmount d =
  let n = toDollars d
  in show n
