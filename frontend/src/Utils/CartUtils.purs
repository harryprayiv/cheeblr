module Utils.CartUtils where

import Prelude

import Data.Array (filter, find, foldl, (:))
import Data.Either (Either(..))
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (DiscreteMoney, fromDiscrete', toDiscrete)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import Services.AuthService (AuthContext)
import Services.TransactionService as TransactionService
import Types.Inventory (MenuItem(..))
import Types.Register (CartTotals)
import Types.Transaction (TaxCategory(..), TransactionItem(..))
import Types.UUID (UUID)
import Utils.Money (formatMoney')
import Utils.UUIDGen (genUUID)

-- Base cart totals structure
emptyCartTotals :: CartTotals
emptyCartTotals =
  { subtotal: Discrete 0
  , taxTotal: Discrete 0
  , total: Discrete 0
  , discountTotal: Discrete 0
  }

-- Calculate cart totals from transaction items
calculateCartTotals :: Array TransactionItem -> CartTotals
calculateCartTotals items =
  foldl addItemToTotals emptyCartTotals items
  where
  addItemToTotals :: CartTotals -> TransactionItem -> CartTotals
  addItemToTotals totals (TransactionItem item) =
    let
      itemSubtotal = toDiscrete item.transactionItemSubtotal
      itemTaxTotal = foldl (\acc tax -> acc + (toDiscrete tax.taxAmount))
        (Discrete 0)
        item.transactionItemTaxes
      itemTotal = toDiscrete item.transactionItemTotal
    in
      { subtotal: totals.subtotal + itemSubtotal
      , taxTotal: totals.taxTotal + itemTaxTotal
      , total: totals.total + itemTotal
      , discountTotal: totals.discountTotal
      }

-- Format price helpers
formatPrice :: DiscreteMoney USD -> String
formatPrice = formatMoney'

formatDiscretePrice :: Discrete USD -> String
formatDiscretePrice = formatMoney' <<< fromDiscrete'

addItemToTransaction
  :: MenuItem
  -> Int
  -> Array TransactionItem
  -> (Array TransactionItem -> Effect Unit)
  -> Effect Unit
addItemToTransaction menuItem@(MenuItem item) qty currentItems updateItems = do
  launchAff_ do
    itemId <- liftEffect genUUID
    transactionId <- liftEffect genUUID

    let
      priceAsMoney = fromDiscrete' item.price

      priceInCents = unwrap item.price
      subtotalInCents = priceInCents * qty
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
        { transactionItemId: itemId
        , transactionItemTransactionId: transactionId
        , transactionItemMenuItemSku: item.sku
        , transactionItemQuantity: qty
        , transactionItemPricePerUnit: priceAsMoney
        , transactionItemDiscounts: []
        , transactionItemTaxes:
            [ { taxCategory: RegularSalesTax
              , taxRate: taxRate
              , taxAmount: taxAsMoney
              , taxDescription: "Sales Tax"
              }
            ]
        , transactionItemSubtotal: subtotalAsMoney
        , transactionItemTotal: totalAsMoney
        }

    liftEffect do
      let
        existingItem = find
          (\(TransactionItem i) -> i.transactionItemMenuItemSku == item.sku)
          currentItems

      case existingItem of
        Just (TransactionItem existing) ->
          let
            newQty = existing.transactionItemQuantity + qty

            existingPriceDiscrete = toDiscrete existing.transactionItemPricePerUnit
            existingPriceInCents = unwrap existingPriceDiscrete

            newSubtotalInCents = existingPriceInCents * newQty
            newTaxInCents = (newSubtotalInCents * taxRateInt) / 100
            newTotalInCents = newSubtotalInCents + newTaxInCents

            newSubtotalDiscrete = Discrete newSubtotalInCents
            newTaxDiscrete = Discrete newTaxInCents
            newTotalDiscrete = Discrete newTotalInCents

            newSubtotalAsMoney = fromDiscrete' newSubtotalDiscrete
            newTaxAsMoney = fromDiscrete' newTaxDiscrete
            newTotalAsMoney = fromDiscrete' newTotalDiscrete

            newTaxRecord =
              { taxCategory: RegularSalesTax
              , taxRate: taxRate
              , taxAmount: newTaxAsMoney
              , taxDescription: "Sales Tax"
              }

            updatedItem = TransactionItem $ existing
              { transactionItemQuantity = newQty
              , transactionItemSubtotal = newSubtotalAsMoney
              , transactionItemTotal = newTotalAsMoney
              , transactionItemTaxes = [ newTaxRecord ]
              }

            updatedItems = map
              ( \i@(TransactionItem currItem) ->
                  if currItem.transactionItemMenuItemSku == item.sku then updatedItem
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
    (filter (\(TransactionItem item) -> item.transactionItemId /= itemId) currentItems)

findExistingItem :: MenuItem -> Array TransactionItem -> Maybe TransactionItem
findExistingItem (MenuItem menuItem) items =
   find (\(TransactionItem txItem) -> txItem.transactionItemMenuItemSku == menuItem.sku) items

addItemToCart
  :: Ref AuthContext
  -> MenuItem
  -> Int
  -> Array TransactionItem
  -> UUID
  -> (Array TransactionItem -> Effect Unit)
  -> (CartTotals -> Effect Unit)
  -> (String -> Effect Unit)
  -> (Boolean -> Effect Unit)
  -> Effect Unit
addItemToCart
  authRef
  menuItem@(MenuItem record)
  qty
  currentItems
  transactionId
  setItems
  setTotals
  setStatusMessage
  setIsProcessing = do

  if qty <= 0 then
    setStatusMessage "Quantity must be greater than 0"
  else do
    let
      currentQtyInCart =
        case
          find (\(TransactionItem item) -> item.transactionItemMenuItemSku == record.sku)
            currentItems
          of
          Just (TransactionItem item) -> item.transactionItemQuantity
          Nothing -> 0

      totalRequestedQty = currentQtyInCart + qty

    if totalRequestedQty > record.quantity then
      setStatusMessage $ "Cannot add " <> show qty <> " more items. Only "
        <> show (record.quantity - currentQtyInCart)
        <> " more available."
    else do
      -- Set processing state but don't block UI updates
      setIsProcessing true
      setStatusMessage "Adding item to transaction..."

      void $ launchAff_ do
        result <- TransactionService.createTransactionItem authRef
          transactionId
          record.sku
          qty
          (unwrap record.price)

        liftEffect $ case result of
          Right addedItem -> do
            let newItems = addedItem : currentItems
            let newTotals = calculateCartTotals newItems

            setTotals newTotals
            setItems newItems
            setStatusMessage "Item added to transaction and reserved"
            Console.log $ "Added and reserved item: " <> record.name

          Left err -> do
            setStatusMessage $ "Error: " <> err
            Console.error $ "Failed to reserve item: " <> err

        -- Always reset the processing state
        liftEffect $ setIsProcessing false

removeItemFromCart
  :: Ref AuthContext
  -> UUID
  -> Array TransactionItem
  -> (Array TransactionItem -> Effect Unit)
  -> (CartTotals -> Effect Unit)
  -> (Boolean -> Effect Unit) -- For loading state
  -> Effect Unit
removeItemFromCart authRef itemId currentItems setItems setTotals setIsProcessing = do
  -- Set loading state
  setIsProcessing true

  -- Make a backend call to release the reservation
  void $ launchAff_ do
    -- Call backend to remove the transaction item
    result <- TransactionService.removeTransactionItem authRef itemId

    liftEffect $ case result of
      Right _ -> do
        -- Item reservation released, update the cart
        let
          newItems = filter (\(TransactionItem item) -> item.transactionItemId /= itemId) currentItems

        -- Recalculate totals  
        let newTotals = calculateCartTotals newItems

        -- Update state
        setTotals newTotals
        setItems newItems
        Console.log $ "Removed item and released reservation with ID: " <> show
          itemId

      Left err -> do
        Console.error $ "Error removing item: " <> err

    -- End loading state  
    liftEffect $ setIsProcessing false