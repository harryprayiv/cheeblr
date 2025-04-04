module UI.Transaction.LiveCart.PriceCalculator where

import Prelude

import Data.Array (filter, find, foldl, (:))
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (DiscreteMoney, fromDiscrete', toDiscrete)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Types.Inventory (MenuItem(..))
import Types.Transaction (TransactionItem(..), TaxCategory(..))
import Types.UUID (UUID)
import Utils.Money (formatMoney')
import Utils.UUIDGen (genUUID)

type CartTotals =
  { subtotal :: Discrete USD
  , taxTotal :: Discrete USD
  , total :: Discrete USD
  , discountTotal :: Discrete USD
  }

emptyCartTotals :: CartTotals
emptyCartTotals =
  { subtotal: Discrete 0
  , taxTotal: Discrete 0
  , total: Discrete 0
  , discountTotal: Discrete 0
  }

calculateCartTotals :: Array TransactionItem -> CartTotals
calculateCartTotals items =
  foldl addItemToTotals emptyCartTotals items
  where
  addItemToTotals :: CartTotals -> TransactionItem -> CartTotals
  addItemToTotals totals (TransactionItem item) =
    let
      itemSubtotal = toDiscrete item.subtotal
      itemTaxTotal = foldl (\acc tax -> acc + (toDiscrete tax.amount))
        (Discrete 0)
        item.taxes
      itemTotal = toDiscrete item.total
    in
      { subtotal: totals.subtotal + itemSubtotal
      , taxTotal: totals.taxTotal + itemTaxTotal
      , total: totals.total + itemTotal
      , discountTotal: totals.discountTotal
      }

formatPrice :: DiscreteMoney USD -> String
formatPrice = formatMoney'

formatDiscretePrice :: Discrete USD -> String
formatDiscretePrice = formatMoney' <<< fromDiscrete'

addItemToTransaction
  :: MenuItem
  -> Number
  -> Array TransactionItem
  -> (Array TransactionItem -> Effect Unit)
  -> Effect Unit
addItemToTransaction menuItem@(MenuItem item) qty currentItems updateItems = do
  launchAff_ do
    itemId <- liftEffect genUUID
    transactionId <- liftEffect genUUID

    let
      priceAsMoney = fromDiscrete' item.price

      qtyAsInt = Int.floor qty
      priceInCents = unwrap item.price
      subtotalInCents = priceInCents * qtyAsInt
      subtotalDiscrete = Discrete subtotalInCents
      subtotalAsMoney = fromDiscrete' subtotalDiscrete

      taxRate = 0.15
      taxRateInt = Int.floor (taxRate * 100.0)
      taxAmountInCents = (subtotalInCents * taxRateInt) / 100
      taxDiscrete = Discrete taxAmountInCents
      taxAsMoney = fromDiscrete' taxDiscrete

      totalInCents = subtotalInCents + taxAmountInCents
      totalDiscrete = Discrete totalInCents
      totalAsMoney = fromDiscrete' totalDiscrete

      newItem = TransactionItem
        { id: itemId
        , transactionId: transactionId
        , menuItemSku: item.sku
        , quantity: qty
        , pricePerUnit: priceAsMoney
        , discounts: []
        , taxes:
            [ { category: RegularSalesTax
              , rate: taxRate
              , amount: taxAsMoney
              , description: "Sales Tax"
              }
            ]
        , subtotal: subtotalAsMoney
        , total: totalAsMoney
        }

    liftEffect do
      let
        existingItem = find
          (\(TransactionItem i) -> i.menuItemSku == item.sku)
          currentItems

      case existingItem of
        Just (TransactionItem existing) ->
          let
            newQty = existing.quantity + qty
            newQtyInt = Int.floor newQty

            existingPriceDiscrete = toDiscrete existing.pricePerUnit
            existingPriceInCents = unwrap existingPriceDiscrete

            newSubtotalInCents = existingPriceInCents * newQtyInt
            newTaxInCents = (newSubtotalInCents * taxRateInt) / 100
            newTotalInCents = newSubtotalInCents + newTaxInCents

            newSubtotalDiscrete = Discrete newSubtotalInCents
            newTaxDiscrete = Discrete newTaxInCents
            newTotalDiscrete = Discrete newTotalInCents

            newSubtotalAsMoney = fromDiscrete' newSubtotalDiscrete
            newTaxAsMoney = fromDiscrete' newTaxDiscrete
            newTotalAsMoney = fromDiscrete' newTotalDiscrete

            newTaxRecord =
              { category: RegularSalesTax
              , rate: taxRate
              , amount: newTaxAsMoney
              , description: "Sales Tax"
              }

            updatedItem = TransactionItem $ existing
              { quantity = newQty
              , subtotal = newSubtotalAsMoney
              , total = newTotalAsMoney
              , taxes = [ newTaxRecord ]
              }

            updatedItems = map
              ( \i@(TransactionItem currItem) ->
                  if currItem.menuItemSku == item.sku then updatedItem
                  else i
              )
              currentItems
          in
            updateItems updatedItems

        Nothing ->
          updateItems (newItem : currentItems)

removeItemFromTransaction
  :: UUID
  -> Array TransactionItem
  -> (Array TransactionItem -> Effect Unit)
  -> Effect Unit
removeItemFromTransaction itemId currentItems updateItems = do
  updateItems
    (filter (\(TransactionItem item) -> item.id /= itemId) currentItems)

findExistingItem :: MenuItem -> Array TransactionItem -> Maybe TransactionItem
findExistingItem (MenuItem menuItem) items =
  find (\(TransactionItem txItem) -> txItem.menuItemSku == menuItem.sku) items