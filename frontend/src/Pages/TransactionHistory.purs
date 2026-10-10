module Pages.TransactionHistory where

import Prelude

import API.Request (ApiError)
import API.Request as Request
import API.Sale as SaleApi
import Data.Array (length, null, sortBy)
import Data.Either (Either(..))
import Data.Tuple.Nested ((/\))
import Data.Validation.Semigroup (toEither)
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot)
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Types.Primitives.Money (saleMoneyDiscrete)
import Types.RemoteData (RemoteData(..))
import Types.Session (SessionResponse)
import Types.Transaction.Sale as Sale
import UI.Form (Form, Style, defaultStyle, runFormWith)
import UI.Form (text) as F
import UI.Form.Parser (required)
import UI.Remote (onMount, standardView, useRemote, viewRemote)
import UI.Transaction.CreateTransaction (formatStatus, statusClass)
import UI.Transaction.Model (refundable, voidable)
import Utils.Formatting (formatDateTime)
import Utils.Money (formatDiscretePrice)

-- Every sale, newest first, with void and refund.
--
-- Void is offered with capCanVoidTransaction on a sale the backend would
-- void (UI.Transaction.Model.voidable). Refund is offered with
-- capCanRefundTransaction on a completed sale (refundable). A refunded sale
-- shows as Refunded and offers neither. Both need a reason.
--
-- The backend decides. A refusal shows the backend's message, and the list
-- is read again after every attempt, so a sale changed on another screen
-- shows its real status. Whether a void or a refund puts stock back is
-- backend configuration. This page does not say either way.

reasonStyle :: Style
reasonStyle = defaultStyle { field = "", hint = "hidden" }

reasonForm :: Form String
reasonForm = F.text
  { label: "Reason:", placeholder: "Why", initial: "" }
  required

page :: SessionResponse -> Nut
page user = Deku.do
  sales <- useRemote Loading SaleApi.getAllSales
  setMessage /\ messageV <- useHot ""
  setBusy /\ busyV <- useHot false

  let
    caps = user.sessionCapabilities

    run :: forall a. String -> Aff (Either ApiError a) -> Effect Unit
    run doneMessage request = do
      setBusy true
      setMessage ""
      launchAff_ do
        result <- request
        liftEffect do
          case result of
            Right _ -> setMessage doneMessage
            Left err -> setMessage ("Error: " <> Request.describe err)
          setBusy false
          sales.refresh

    void' sale reason =
      run "Sale voided." (SaleApi.voidSale sale.saleId reason)

    refund sale reason =
      run "Sale refunded." (SaleApi.refundSale sale.saleId reason)

    mayVoid sale = caps.capCanVoidTransaction && voidable sale.saleStatus

    mayRefund sale = caps.capCanRefundTransaction && refundable sale.saleStatus

    actionButton label form action =
      D.button
        [ DA.klass_ "btn btn-sm"
        , DA.disabled $
            ( \result busy ->
                case toEither result of
                  Right _ | not busy -> ""
                  _ -> "true"
            )
              <$> form.result
              <*> busyV
        , DL.runOn DL.click $
            ( \result busy ->
                case toEither result of
                  Right reason | not busy -> action reason
                  _ -> pure unit
            )
              <$> form.result
              <*> busyV
        ]
        [ text_ label ]

    actions sale =
      if not (mayVoid sale || mayRefund sale) then D.div_ []
      else
        runFormWith reasonStyle reasonForm \form ->
          D.div [ DA.klass_ "sale-actions" ]
            ( form.view
                <> (if mayVoid sale then [ actionButton "Void" form (void' sale) ] else [])
                <> (if mayRefund sale then [ actionButton "Refund" form (refund sale) ] else [])
            )

    row :: Sale.SaleTransaction -> Nut
    row sale =
      D.div [ DA.klass_ "sale-row stat-card" ]
        [ D.div [ DA.klass_ "sale-created" ]
            [ text_ (formatDateTime sale.saleCreated) ]
        , D.div [ DA.klass_ ("status-value " <> statusClass sale.saleStatus) ]
            [ text_ (formatStatus sale.saleStatus) ]
        , D.div [ DA.klass_ "sale-lines" ]
            [ text_ (show (length sale.saleItems) <> " line(s)") ]
        , D.div [ DA.klass_ "sale-total" ]
            [ text_ (formatDiscretePrice (saleMoneyDiscrete sale.saleTotal)) ]
        , D.div [ DA.klass_ "sale-id" ] [ text_ (show sale.saleId) ]
        , actions sale
        ]

    newestFirst a b = compare b.saleCreated a.saleCreated

    list found =
      if null found then
        D.div [ DA.klass_ "empty-result" ] [ text_ "No sales yet" ]
      else
        D.div [ DA.klass_ "sale-list" ]
          (map row (sortBy newestFirst found))

  D.div
    [ DA.klass_ "sale-history"
    , onMount sales.reload
    ]
    [ D.div [ DA.klass_ "manager-header" ]
        [ D.h1_ [ text_ "Sales" ]
        , D.button
            [ DA.klass_ "btn btn-sm"
            , DL.click_ \_ -> sales.reload
            ]
            [ text_ "Refresh" ]
        ]
    , D.div [ DA.klass_ "status-message" ] [ text messageV ]
    , viewRemote (standardView "Loading sales...") list sales.value
    ]
