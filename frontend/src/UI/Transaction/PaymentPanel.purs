module UI.Transaction.PaymentPanel
  ( PaymentProps
  , paymentForm
  , paymentStyle
  , paymentPanel
  ) where

import Prelude

import Data.Array (null)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.String (trim)
import Data.Tuple (Tuple(..))
import Data.Validation.Semigroup (toEither)
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Hooks ((<#~>))
import Effect (Effect)
import FRP.Poll (Poll)
import Services.SaleActions (PaymentInput)
import Types.Primitives.Money (saleMoneyDiscrete)
import Types.Transaction (PaymentMethod(..))
import Types.Transaction.Sale as Sale
import Types.UUID (UUID)
import UI.Form (Built, Form, Style, choice, defaultStyle, dependent, text, visibleWhen)
import UI.Form.Parser (Parser, cents, optional)
import UI.Transaction.Model (Activity, isBusy, isOpen)
import Utils.Money (formatDiscretePrice)

-- The payment inputs use the screen's own classes. Hints are hidden here;
-- the screen lists the form's problems in its status panel instead.
paymentStyle :: Style
paymentStyle = defaultStyle
  { field = ""
  , line = "payment-input-row"
  , label = "payment-label"
  , input = "payment-field"
  , hint = "hidden"
  }

-- Blank means no code.
optionalText :: Parser (Maybe String)
optionalText raw =
  let
    s = trim raw
  in
    Right (if s == "" then Nothing else Just s)

methodOptions :: Array { value :: PaymentMethod, label :: String }
methodOptions =
  [ { value: Cash, label: "Cash" }
  , { value: Credit, label: "Credit" }
  , { value: Debit, label: "Debit" }
  , { value: ACH, label: "ACH" }
  , { value: GiftCard, label: "Gift Card" }
  , { value: StoredValue, label: "Stored Value" }
  , { value: Mixed, label: "Split Payment" }
  , { value: Other "", label: "Other" }
  ]

-- Method, amount, and the two fields that depend on the method. Tendered is
-- shown only for Cash and Auth Code only for Credit. A hidden field yields
-- Nothing, whatever text it still holds.
paymentForm :: Form PaymentInput
paymentForm =
  dependent method details <#> \(Tuple m d) ->
    { method: m
    , amount: d.amount
    , tendered: join d.tendered
    , authCode: join d.authCode
    }
  where
  method = choice
    { options: methodOptions
    , initial: Cash
    , groupClass: "payment-methods"
    , optionClass: "payment-method"
    }

  details selected = ado
    amount <- text
      { label: "Amount:", placeholder: "0.00", initial: "" }
      cents
    tendered <- visibleWhen (selected <#> eq (Just Cash)) $ text
      { label: "Tendered:", placeholder: "0.00", initial: "" }
      (optional cents)
    authCode <- visibleWhen (selected <#> eq (Just Credit)) $ text
      { label: "Auth Code:", placeholder: "", initial: "" }
      optionalText
    in { amount, tendered, authCode }

type PaymentProps =
  { form :: Built PaymentInput
  , sale :: Poll Sale.SaleTransaction
  , activity :: Poll Activity
  , addPayment :: PaymentInput -> Effect Unit
  , removePayment :: UUID -> Effect Unit
  }

-- The payment section: the form, the Add Payment button and the payments
-- already on the sale. The form is run by the screen, which passes the built
-- form in so it can also read the form's errors.
paymentPanel :: PaymentProps -> Nut
paymentPanel props =
  D.div [ DA.klass_ "payment-section" ]
    ( [ D.div [ DA.klass_ "payment-header" ] [ text_ "Payment Options" ] ]
        <> props.form.view
        <>
          [ D.button
              [ DA.klass_ "add-payment-btn"
              , DA.disabled $ canAdd <#> \ok -> if ok then "" else "true"
              , DL.runOn DL.click $
                  ( \result ok ->
                      case toEither result of
                        Right input | ok -> props.addPayment input
                        _ -> pure unit
                  )
                    <$> props.form.result
                    <*> canAdd
              ]
              [ text_ "Add Payment" ]

          , D.div [ DA.klass_ "existing-payments" ]
              [ props.sale <#~> \sale ->
                  if null sale.salePayments then D.div_ []
                  else
                    D.div [ DA.klass_ "payments-container" ]
                      [ D.div [ DA.klass_ "payments-header" ]
                          [ text_ "Current Payments:" ]
                      , D.div_ (map payment sale.salePayments)
                      ]
              ]
          ]
    )
  where
  busy = isBusy <$> props.activity

  canAdd =
    ( \result activity sale ->
        case toEither result of
          Right _ -> not (isBusy activity) && isOpen sale.saleStatus
          Left _ -> false
    )
      <$> props.form.result
      <*> props.activity
      <*> props.sale

  payment p =
    D.div [ DA.klass_ "payment-item" ]
      [ D.div [ DA.klass_ "payment-method" ] [ text_ (show p.paymentMethod) ]
      , D.div [ DA.klass_ "payment-amount" ]
          [ text_ (formatDiscretePrice (saleMoneyDiscrete p.paymentAmount)) ]
      , D.button
          [ DA.klass_ "payment-remove"
          , DA.disabled $ busy <#> \b -> if b then "true" else ""
          , DL.click_ \_ -> props.removePayment p.paymentId
          ]
          [ text_ "✕" ]
      ]
