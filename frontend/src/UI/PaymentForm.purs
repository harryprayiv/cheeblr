module Cheeblr.UI.Transaction.PaymentForm where

import Prelude

import Cheeblr.Core.Cart (CartTotals, remainingBalance, isFullyPaid, totalPayments)
import Cheeblr.Core.Money (formatCurrency, parseDollars, toDollars, zeroCents)
import Cheeblr.UI.FormHelpers (getInputValue, getSelectValue)
import Data.Array (null)
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete)
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useState, (<#~>))
import Effect (Effect)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Effect.Unsafe (unsafePerformEffect)
import FRP.Poll (Poll)

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

type PaymentEntry =
  { method :: PaymentMethod
  , amount :: Discrete USD
  }

paymentForm
  :: Poll CartTotals
  -> Poll (Array (Discrete USD))
  -> (PaymentEntry -> Effect Unit)
  -> (Effect Unit)
  -> Nut
paymentForm totalsPoll paymentsPoll onAddPayment onFinalize =
  let
    -- Refs to imperatively read current input values
    amountRef :: Ref String
    amountRef = unsafePerformEffect (Ref.new "")

    methodRef :: Ref String
    methodRef = unsafePerformEffect (Ref.new "Cash")
  in
    paymentFormInner totalsPoll paymentsPoll onAddPayment onFinalize amountRef methodRef

paymentFormInner
  :: Poll CartTotals
  -> Poll (Array (Discrete USD))
  -> (PaymentEntry -> Effect Unit)
  -> (Effect Unit)
  -> Ref String
  -> Ref String
  -> Nut
paymentFormInner totalsPoll paymentsPoll onAddPayment onFinalize amountRef methodRef = Deku.do
  setAmount /\ amountPoll <- useState ""
  setMethod /\ methodPoll <- useState "Cash"
  setError /\ errorPoll <- useState ""

  let
    updateAmount :: String -> Effect Unit
    updateAmount val = do
      Ref.write val amountRef
      setAmount val

    updateMethod :: String -> Effect Unit
    updateMethod val = do
      Ref.write val methodRef
      setMethod val

    handleAddPayment :: Effect Unit
    handleAddPayment = do
      amountStr <- Ref.read amountRef
      methodStr <- Ref.read methodRef
      case parseDollars amountStr of
        Nothing -> setError "Please enter a valid dollar amount"
        Just amount ->
          if amount <= zeroCents then
            setError "Amount must be greater than zero"
          else do
            onAddPayment
              { method: parsePaymentMethod methodStr
              , amount
              }
            -- Reset input
            updateAmount ""
            setError ""

  D.div
    [ DA.klass_ "payment-form" ]
    [ D.h3_ [ text_ "Payment" ]

    -- Payment summary
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

    -- Method selector
    , D.div
        [ DA.klass_ "payment-method-row" ]
        [ D.label_ [ text_ "Method" ]
        , D.select
            [ DA.klass_ "payment-method-select"
            , DL.change_ \evt -> do
                val <- getSelectValue evt
                updateMethod val
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
                updateAmount val
                setError ""
            ] []
        ]

    -- Quick amount buttons
    , totalsPoll <#~> \totals ->
        D.div
          [ DA.klass_ "payment-quick-amounts" ]
          [ quickButton "Exact" (formatAmount totals.total) updateAmount
          ]

    -- Error display
    , errorPoll <#~> \err ->
        if err == "" then D.span_ []
        else D.div [ DA.klass_ "payment-error" ] [ text_ err ]

    -- Add Payment button (actually wired now)
    , D.button
        [ DA.klass_ "payment-add-btn"
        , DL.click_ \_ -> handleAddPayment
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