module Services.Cart where

import Prelude

import Data.Array (filter, find, (:))
import Data.Either (Either(..))
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (fromDiscrete', toDiscrete)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import Services.AuthService (AuthContext)
import Services.TransactionService (calculateCartTotals)
import Services.TransactionService as TransactionService
import Types.Inventory (MenuItem(..), Inventory(..))
import Types.Register (CartTotals)
import Types.Transaction (TaxCategory(..), TransactionItem(..))
import Types.UUID (UUID, genUUID)

getCartQuantityForSku :: UUID -> Array TransactionItem -> Int
getCartQuantityForSku sku cartItems =
  case find (\(TransactionItem item) -> item.transactionItemMenuItemSku == sku) cartItems of
    Just (TransactionItem item) -> item.transactionItemQuantity
    Nothing -> 0

isItemAvailable :: MenuItem -> Int -> Array TransactionItem -> Boolean
isItemAvailable (MenuItem item) requestedQty cartItems =
  let
    currentInCart = getCartQuantityForSku item.sku cartItems
    totalRequestedQty = currentInCart + requestedQty
  in
    totalRequestedQty <= item.quantity

getAvailableQuantity :: MenuItem -> Array TransactionItem -> Int
getAvailableQuantity (MenuItem item) cartItems =
  let
    currentInCart = getCartQuantityForSku item.sku cartItems
  in
    item.quantity - currentInCart

findUnavailableItems :: Array TransactionItem -> Inventory -> Array { id :: UUID, name :: String }
findUnavailableItems cartItems (Inventory inventory) =
  cartItems 
    # filter (\(TransactionItem item) -> 
        case find (\(MenuItem menuItem) -> menuItem.sku == item.transactionItemMenuItemSku) inventory of
          Just (MenuItem menuItem) -> 
            menuItem.quantity < item.transactionItemQuantity
          Nothing -> 
            true
      )
    # map (\(TransactionItem item) -> 
        let 
          name = case find (\(MenuItem menuItem) -> menuItem.sku == item.transactionItemMenuItemSku) inventory of
            Just (MenuItem menuItem) -> menuItem.name
            Nothing -> "Unknown Item"
        in
          { id: item.transactionItemId, name }
      )

findExistingItem :: MenuItem -> Array TransactionItem -> Maybe TransactionItem
findExistingItem (MenuItem menuItem) items =
  find (\(TransactionItem txItem) -> txItem.transactionItemMenuItemSku == menuItem.sku) items

removeItemFromTransaction
  :: UUID
  -> Array TransactionItem
  -> (Array TransactionItem -> Effect Unit)
  -> Effect Unit
removeItemFromTransaction itemId currentItems updateItems = do
  updateItems
    (filter (\(TransactionItem item) -> item.transactionItemId /= itemId) currentItems)

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
  setCheckingInventory = do
  
  if qty <= 0 then  
    setStatusMessage "Quantity must be greater than 0"
  else do
    setCheckingInventory true
    setStatusMessage "Checking inventory..."
    
    -- Check for existing item in cart
    let existingItem = find 
          (\(TransactionItem item) -> item.transactionItemMenuItemSku == record.sku) 
          currentItems
    
    let currentQtyInCart = case existingItem of
          Just (TransactionItem item) -> item.transactionItemQuantity
          Nothing -> 0 
    
    let totalRequestedQty = currentQtyInCart + qty
    
    -- Create the transaction item through the API
    void $ launchAff_ do
      result <- TransactionService.createTransactionItem
        authRef
        transactionId
        record.sku
        qty
        (unwrap record.price)
      
      liftEffect $ case result of
        Right newItem -> do
          -- Update local state with the new item
          let updatedItems = case existingItem of
                Just (TransactionItem existing) ->
                  -- Update existing item quantity
                  map (\(TransactionItem i) -> 
                    if i.transactionItemId == existing.transactionItemId 
                    then TransactionItem (i { transactionItemQuantity = totalRequestedQty })
                    else TransactionItem i
                  ) currentItems
                Nothing ->
                  newItem : currentItems
          
          let newTotals = TransactionService.calculateCartTotals updatedItems
          setItems updatedItems
          setTotals newTotals
          setCheckingInventory false
          setStatusMessage $ "Added " <> record.name <> " to cart"
          
        Left err -> do
          setCheckingInventory false
          setStatusMessage $ "Failed to add item: " <> err


removeItemFromCart
  :: Ref AuthContext
  -> UUID
  -> Array TransactionItem
  -> (Array TransactionItem -> Effect Unit)
  -> (CartTotals -> Effect Unit)
  -> (Boolean -> Effect Unit)
  -> Effect Unit
removeItemFromCart authRef itemId currentItems setItems setTotals setIsProcessing = do
  setIsProcessing true
  
  let itemInfo = case find (\(TransactionItem item) -> item.transactionItemId == itemId) currentItems of
                   Just (TransactionItem item) -> ", SKU: " <> show item.transactionItemMenuItemSku
                   Nothing -> ""
                   
  Console.log $ "Removing item ID: " <> show itemId <> itemInfo

  void $ launchAff_ do
    result <- TransactionService.removeTransactionItem authRef itemId

    liftEffect $ case result of
      Right _ -> do
        let
          newItems = filter (\(TransactionItem item) -> item.transactionItemId /= itemId) currentItems
        let newTotals = calculateCartTotals newItems

        setTotals newTotals
        setItems newItems
        Console.log $ "Successfully removed item and released reservation: " <> show itemId

      Left err -> do
        Console.error $ "Error removing item: " <> err

    liftEffect $ setIsProcessing false