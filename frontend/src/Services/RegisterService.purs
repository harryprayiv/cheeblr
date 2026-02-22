module Services.RegisterService where

import Prelude

import API.Transaction as API
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import Services.AuthService (AuthContext)
import Types.Register (Register, CartTotals)
import Types.UUID (UUID, parseUUID, genUUID)
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage (getItem, setItem)
import Data.Array (filter, find, foldl, (:))
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (DiscreteMoney, fromDiscrete', toDiscrete)
import Data.Int as Int
import Data.Newtype (unwrap)
import Services.TransactionService as TransactionService
import Types.Transaction (TaxCategory(..), TransactionItem(..))
import Utils.Money (formatMoney')
import Types.Inventory (MenuItem(..), Inventory(..))


getOrInitLocalRegister :: Ref AuthContext -> UUID -> UUID -> (Register -> Effect Unit) -> (String -> Effect Unit) -> Effect Unit
getOrInitLocalRegister authRef locationId employeeId setRegister setError = do
  w <- window
  storage <- localStorage w
  storedRegId <- getItem "register_id" storage

  registerId <- case storedRegId >>= parseUUID of
    Just id -> pure id
    Nothing -> do
      newId <- genUUID
      w' <- window
      storage' <- localStorage w'
      setItem "register_id" (show newId) storage'
      pure newId

  launchAff_ do
    -- Try to get existing register first
    getResult <- API.getRegister authRef registerId

    case getResult of
      -- Register exists, use it
      Right register -> do
        liftEffect $ Console.log $ "Using existing register: " <>
          register.registerName
        liftEffect $ setRegister register

      -- Register doesn't exist, create a new one
      Left _ -> do
        liftEffect $ Console.log $
          "Register not found, creating a new one with ID: " <> show registerId

        let
          newRegister =
            { registerId: registerId
            , registerName: "Register ID: " <> show registerId
            , registerLocationId: locationId
            , registerIsOpen: false
            , registerCurrentDrawerAmount: 0
            , registerExpectedDrawerAmount: 0
            , registerOpenedAt: Nothing
            , registerOpenedBy: Nothing
            , registerLastTransactionTime: Nothing
            }

        createResult <- API.createRegister authRef newRegister

        case createResult of
          Right register -> do
            let
              openRequest =
                { openRegisterEmployeeId: employeeId
                , openRegisterStartingCash: 0
                }

            openResult <- API.openRegister authRef openRequest register.registerId

            liftEffect $ case openResult of
              Right openedRegister -> do
                setRegister openedRegister
                Console.log $ "New register created and opened successfully: "
                  <> openedRegister.registerName
              Left openErr -> do
                setError ("Failed to open new register: " <> openErr)

          Left createErr -> do
            liftEffect $ setError ("Failed to create register: " <> createErr)

-- create a local register if it doesn't exist
initLocalRegister :: Ref AuthContext -> UUID -> UUID -> (Register -> Effect Unit) -> (String -> Effect Unit) -> Effect Unit
initLocalRegister authRef locationId employeeId setRegister setError = do

  w <- window
  storage <- localStorage w
  storedRegId <- getItem "register_id" storage

  registerId <- case storedRegId >>= parseUUID of
    Just id -> pure id
    Nothing -> do
      newId <- genUUID
      w' <- window
      storage' <- localStorage w'
      setItem "register_id" (show newId) storage'
      pure newId

  launchAff_ do
    getResult <- API.getRegister authRef registerId

    case getResult of
      Right register -> do
        let
          openRequest =
            { openRegisterEmployeeId: employeeId
            , openRegisterStartingCash: 0
            }

        openResult <- API.openRegister authRef openRequest register.registerId

        liftEffect $ case openResult of
          Right openedRegister -> do
            setRegister openedRegister
            Console.log $ "Register opened successfully: " <>
              openedRegister.registerName
          Left err -> do
            setError ("Failed to open register: " <> err)

      Left _ -> do
        liftEffect $ Console.log $
          "Register not found, creating a new one with ID: " <> show registerId

        let
          newRegister =
            { registerId: registerId
            , registerName: "Register ID: " <> show registerId
            , registerLocationId: locationId
            , registerIsOpen: false
            , registerCurrentDrawerAmount: 0
            , registerExpectedDrawerAmount: 0
            , registerOpenedAt: Nothing
            , registerOpenedBy: Nothing
            , registerLastTransactionTime: Nothing
            }

        createResult <- API.createRegister authRef newRegister

        case createResult of
          Right register -> do
            let
              openRequest =
                { openRegisterEmployeeId: employeeId
                , openRegisterStartingCash: 0
                }

            openResult <- API.openRegister authRef openRequest register.registerId

            liftEffect $ case openResult of
              Right openedRegister -> do
                setRegister openedRegister
                Console.log $ "New register created and opened successfully: "
                  <> openedRegister.registerName
              Left openErr -> do
                setError ("Failed to open new register: " <> openErr)

          Left createErr -> do
            liftEffect $ setError ("Failed to create register: " <> createErr)


-- || local Register creation
createLocalRegister :: Ref AuthContext -> String -> UUID -> (Register -> Effect Unit) -> (String -> Effect Unit) -> Effect Unit
createLocalRegister authRef name locationId setRegister setError = do
  launchAff_ do

    _ <- liftEffect genUUID
    registerId <- liftEffect genUUID

    let
      newRegister =
        { registerId: registerId
        , registerName: name
        , registerLocationId: locationId
        , registerIsOpen: false
        , registerCurrentDrawerAmount: 0
        , registerExpectedDrawerAmount: 0
        , registerOpenedAt: Nothing
        , registerOpenedBy: Nothing
        , registerLastTransactionTime: Nothing
        }

    result <- API.createRegister authRef newRegister

    liftEffect case result of
      Right register -> do
        setRegister register
        Console.log $ "Register created successfully: " <> register.registerName
      Left err -> do
        setError ("Failed to create register: " <> err)

closeLocalRegister :: Ref AuthContext -> UUID -> UUID -> Int -> (String -> Effect Unit) -> Effect Unit
closeLocalRegister authRef registerId employeeId countedCash setMessage = do
  launchAff_ do
    let
      closeRequest =
        { closeRegisterEmployeeId: employeeId
        , closeRegisterCountedCash: countedCash
        }

    result <- API.closeRegister authRef closeRequest registerId

    liftEffect case result of
      Right closeResult -> do
        let variance = closeResult.closeRegisterResultVariance
        let
          varMsg =
            if variance /= 0 then " with variance of " <> show variance
            else " with no variance"
        setMessage $ "Register closed successfully" <> varMsg
        Console.log $ "Register closed: " <> show registerId

      Left err -> do
        setMessage $ "Failed to close register: " <> err

formatPrice :: DiscreteMoney USD -> String
formatPrice = formatMoney'

formatDiscretePrice :: Discrete USD -> String
formatDiscretePrice = formatMoney' <<< fromDiscrete'

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