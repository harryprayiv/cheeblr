module Services.CashRegister where

import Prelude

import Config.Entity (dummyEmployeeId, dummyLocationId, dummyPaymentId, dummyRegisterId, dummyTransactionId)
import Data.Array (foldl, null, filter, (:))
import Data.Array as Array
import Data.DateTime (DateTime)
import Data.Either (Either(..))
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..), formatDiscrete)
import Data.Finance.Money.Extended (fromDiscrete', toDiscrete)
import Data.Finance.Money.Format (numeric, numericC)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Effect.Now (now, nowDateTime)
import Types.Inventory (ItemCategory(..), MenuItem(..))
import Types.Transaction (DiscountRecord, DiscountType(..), PaymentMethod(..), PaymentTransaction(..), TaxCategory(..), TaxRecord, Transaction(..), TransactionItem(..), TransactionStatus(..), TransactionType(..))
import Types.UUID (UUID)
import Utils.Formatting (uuidToString)
import Utils.UUIDGen (genUUID)

data RegisterError
  = InvalidTransaction
  | PaymentRequired
  | InvalidPaymentAmount
  | InsufficientPayment
  | ProductNotFound
  | InventoryUnavailable
  | RegisterClosed
  | PermissionDenied
  | ReceiptPrinterError
  | NetworkError
  | InternalError String

derive instance eqRegisterError :: Eq RegisterError
derive instance ordRegisterError :: Ord RegisterError

instance showRegisterError :: Show RegisterError where
  show InvalidTransaction = "Invalid transaction"
  show PaymentRequired = "Payment required to complete transaction"
  show InvalidPaymentAmount = "Invalid payment amount"
  show InsufficientPayment = "Insufficient payment amount"
  show ProductNotFound = "Product not found"
  show InventoryUnavailable = "Product is not available in inventory"
  show RegisterClosed = "Register is closed"
  show PermissionDenied = "Permission denied for operation"
  show ReceiptPrinterError = "Receipt printer error"
  show NetworkError = "Network connection error"
  show (InternalError msg) = "Internal error: " <> msg

type RegisterState =
  { registerId :: UUID
  , isOpen :: Boolean
  , currentDrawerAmount :: Discrete USD
  , currentTransaction :: Maybe Transaction
  , openedAt :: Maybe DateTime
  , openedBy :: UUID
  , lastTransactionTime :: Maybe DateTime
  , expectedDrawerAmount :: Discrete USD
  }

type TransactionBuilder =
  { transactionId :: UUID
  , items :: Array TransactionItem
  , payments :: Array PaymentTransaction
  , customer :: Maybe UUID
  , employee :: UUID
  , register :: UUID
  , location :: UUID
  , discounts :: Array DiscountRecord
  , subtotal :: Discrete USD
  , taxTotal :: Discrete USD
  , total :: Discrete USD
  , status :: TransactionStatus
  , notes :: Maybe String
  }

initializeTransaction
  :: UUID  -- Transaction ID
  -> UUID  -- Employee ID
  -> UUID  -- Register ID
  -> UUID  -- Location ID
  -> Aff TransactionBuilder
initializeTransaction transactionId employeeId registerId locationId = do
  liftEffect $ log "Initializing new transaction"

  pure
    { transactionId
    , items: []
    , payments: []
    , customer: Nothing
    , employee: employeeId
    , register: registerId
    , location: locationId
    , discounts: []
    , subtotal: Discrete 0
    , taxTotal: Discrete 0
    , total: Discrete 0
    , status: Created
    , notes: Nothing
    }

addItemToTransaction
  :: TransactionBuilder
  -> MenuItem
  -> Number
  -> Aff (Either RegisterError TransactionBuilder)
addItemToTransaction builder menuItem quantity = do

  let MenuItem menuItemRecord = menuItem

  liftEffect $ log $ "Adding item to transaction: " <> menuItemRecord.name

  if menuItemRecord.quantity <= 0 then do
    liftEffect $ log "Item is out of stock"
    pure $ Left InventoryUnavailable
  else if quantity <= 0.0 then do
    liftEffect $ log "Invalid quantity"
    pure $ Left InvalidTransaction
  else do
    itemId <- liftEffect genUUID

    let
      -- Use the price directly since it's already a Discrete USD
      itemPrice = menuItemRecord.price
      -- Convert quantity to Discrete for multiplication
      itemSubtotal = itemPrice * (Discrete (Int.floor quantity))

      taxes = calculateTaxes itemSubtotal menuItem
      itemTaxTotal = foldl (\acc tax -> acc + (toDiscrete tax.amount))
        (Discrete 0)
        taxes

      -- Create a new TransactionItem by wrapping the record with the constructor
      newItem = TransactionItem
        { transactionItemId: itemId
        , transactionItemTransactionId: builder.transactionId 
        , transactionItemMenuItemSku: menuItemRecord.sku
        , transactionItemQuantity: quantity
        , transactionItemPricePerUnit: fromDiscrete' itemPrice
        , transactionItemDiscounts: []
        , transactionItemTaxes: taxes
        , transactionItemSubtotal: fromDiscrete' itemSubtotal
        , transactionItemTotal: fromDiscrete' (itemSubtotal + itemTaxTotal)
        }

      newSubtotal = builder.subtotal + itemSubtotal
      newTaxTotal = builder.taxTotal + itemTaxTotal
      newTotal = newSubtotal + newTaxTotal

      updatedBuilder = builder
        { items = newItem : builder.items
        , subtotal = newSubtotal
        , taxTotal = newTaxTotal
        , total = newTotal
        , status = InProgress
        }

    liftEffect $ log $ "Item added: " <> menuItemRecord.name
      <> ", Quantity: "
      <> show quantity
      <> ", Price: "
      <> formatDiscrete numericC itemPrice

    pure $ Right updatedBuilder

applyDiscount
  :: TransactionBuilder
  -> DiscountType
  -> String
  -> Maybe UUID
  -> Aff (Either RegisterError TransactionBuilder)
applyDiscount builder discountType reason maybeApprover = do
  liftEffect $ log "Applying discount to transaction"

  if builder.subtotal == Discrete 0 then do
    liftEffect $ log "Cannot apply discount to empty transaction"
    pure $ Left InvalidTransaction
  else do
    let
      discountAmount = case discountType of
        PercentOff percentage ->
          let
            percentAsInt = Int.floor (percentage * 100.0)
            -- Instead of division with /, use integer division on the raw Int
            rawSubtotal = unwrap builder.subtotal
            rawPercent = percentAsInt
            -- Multiply and then divide by 100 using integer arithmetic
            discountValue = Discrete (rawSubtotal * rawPercent / 100)
          in
            discountValue

        AmountOff amount ->
          if amount > builder.subtotal then builder.subtotal
          else amount

        BuyOneGetOne ->
          -- Similarly for division by 2
          let
            rawValue = unwrap builder.subtotal
          in
            Discrete (rawValue / 2)

        Custom _ amount ->
          if amount > builder.subtotal then builder.subtotal
          else amount

      newDiscount =
        { type: discountType
        , amount: fromDiscrete' discountAmount
        , reason
        , approvedBy: maybeApprover
        }

      newTotal = builder.subtotal - discountAmount + builder.taxTotal

      updatedBuilder = builder
        { discounts = newDiscount : builder.discounts
        , total = newTotal
        }

    liftEffect $ log $ "Discount applied: " <> formatDiscrete numericC
      discountAmount

    pure $ Right updatedBuilder

addPayment
  :: TransactionBuilder
  -> PaymentMethod
  -> Discrete USD
  -> Discrete USD
  -> Maybe String
  -> Aff (Either RegisterError TransactionBuilder)
addPayment builder method amount tendered reference = do
  liftEffect $ log $ "Adding payment: " <> show method <> " " <> formatDiscrete
    numericC
    amount

  if amount <= Discrete 0 then do
    liftEffect $ log "Invalid payment amount"
    pure $ Left InvalidPaymentAmount
  else do
    paymentId <- liftEffect genUUID

    let
      currentPaymentTotal = foldl
        ( \acc p ->
            let
              PaymentTransaction payment = p
            in
              acc + (toDiscrete payment.amount)
        )
        (Discrete 0)
        builder.payments

      remainingBalance = builder.total - currentPaymentTotal

      actualPaymentAmount =
        if amount > remainingBalance then remainingBalance
        else amount

      change =
        if method == Cash && tendered > actualPaymentAmount then tendered -
          actualPaymentAmount
        else Discrete 0

      newPaymentRecord =
        { id: paymentId
        , transactionId: builder.transactionId
        , method
        , amount: fromDiscrete' actualPaymentAmount
        , tendered: fromDiscrete'
            (if method == Cash then tendered else actualPaymentAmount)
        , change: fromDiscrete' change
        , reference
        , approved: true
        , authorizationCode: Nothing
        }

      newPayments = PaymentTransaction newPaymentRecord : builder.payments
      newPaymentTotal = currentPaymentTotal + actualPaymentAmount

      newStatus =
        if newPaymentTotal >= builder.total then Completed
        else InProgress

      updatedBuilder = builder
        { payments = newPayments
        , status = newStatus
        }

    liftEffect $ log $ "Payment added: " <> show method
      <> ", Amount: "
      <> formatDiscrete numericC actualPaymentAmount
      <>
        ( if change > Discrete 0 then ", Change: " <> formatDiscrete numericC
            change
          else ""
        )

    pure $ Right updatedBuilder

finalizeTransaction
  :: TransactionBuilder
  -> Aff (Either RegisterError Transaction)
finalizeTransaction builder = do
  liftEffect $ log "Finalizing transaction"

  if null builder.items then do
    liftEffect $ log "Cannot finalize transaction with no items"
    pure $ Left InvalidTransaction
  else do
    let
      totalPayments = foldl
        ( \acc payment ->
            case payment of
              PaymentTransaction p -> acc + (toDiscrete p.amount)
        )
        (Discrete 0)
        builder.payments

    if totalPayments < builder.total then do
      liftEffect $ log "Insufficient payment to complete transaction"
      pure $ Left InsufficientPayment
    else do
      timestamp <- liftEffect nowDateTime

      let
        discountTotal = foldl (\acc d -> acc + (toDiscrete d.amount))
          (Discrete 0)
          builder.discounts

      let
        updatedItems = map
          ( \item ->
              let
                TransactionItem ti = item
              in
                TransactionItem (ti { transactionItemTransactionId = builder.transactionId })
          )
          builder.items

        updatedPayments = map
          ( \payment ->
              let
                PaymentTransaction p = payment
              in
                PaymentTransaction (p { transactionId = builder.transactionId })  
          )
          builder.payments

        transaction = Transaction
          { transactionId: builder.transactionId 
          , transactionStatus: Completed
          , transactionCreated: timestamp
          , transactionCompleted: Just timestamp
          , transactionCustomerId: builder.customer
          , transactionEmployeeId: builder.employee
          , transactionRegisterId: builder.register
          , transactionLocationId: builder.location
          , transactionItems: updatedItems
          , transactionPayments: updatedPayments
          , transactionSubtotal: fromDiscrete' builder.subtotal
          , transactionDiscountTotal: fromDiscrete' discountTotal
          , transactionTaxTotal: fromDiscrete' builder.taxTotal
          , transactionTotal: fromDiscrete' builder.total
          , transactionType: Sale
          , transactionIsVoided: false
          , transactionVoidReason: Nothing
          , transactionIsRefunded: false
          , transactionRefundReason: Nothing
          , transactionReferenceTransactionId: Nothing
          , transactionNotes: builder.notes
          }

      liftEffect $ log $ "Transaction finalized: " <> uuidToString builder.transactionId
        <> ", Total: "
        <> formatDiscrete numericC builder.total

      pure $ Right transaction

generateReceipt :: Transaction -> String
generateReceipt transaction =
  let
    txData = unwrap transaction

    receiptHeader =
      "===================================\n"
        <> "        CANNABIS DISPENSARY        \n"
        <> "===================================\n"
        <> "Transaction: "
        <> uuidToString txData.transactionId
        <> "\n"
        <> "Date: "
        <> show txData.transactionCreated
        <> "\n"
        <>
          "\n"

    itemLines = foldl (\acc item -> acc <> formatTransactionItem item) ""
      txData.transactionItems

    subtotalLine =
      "\n"
        <> "Subtotal:         "
        <> formatDiscrete numeric (toDiscrete txData.transactionSubtotal)
        <> "\n"

    discountLine =
      if txData.transactionDiscountTotal > (fromDiscrete' (Discrete 0)) then
        "Discount:         -"
          <> formatDiscrete numeric (toDiscrete txData.transactionDiscountTotal)
          <> "\n"
      else ""

    taxLine = "Tax:              "
      <> formatDiscrete numeric (toDiscrete txData.transactionTaxTotal)
      <> "\n"

    totalLine =
      "TOTAL:            "
        <> formatDiscrete numericC (toDiscrete txData.transactionTotal)
        <> "\n\n"

    paymentLines = foldl (\acc payment -> acc <> formatPayment payment) ""
      txData.transactionPayments

    receiptFooter =
      "===================================\n"
        <> "       THANK YOU FOR VISITING      \n"
        <>
          "===================================\n"
  in
    receiptHeader <> itemLines <> subtotalLine <> discountLine <> taxLine
      <> totalLine
      <> paymentLines
      <> receiptFooter

formatTransactionItem :: TransactionItem -> String
formatTransactionItem (TransactionItem item) =
  let
    itemLine =
      ( if item.transactionItemQuantity /= 1.0 then show item.transactionItemQuantity <> " x "
        else ""
      )
        <> "Item @ "
        <> formatDiscrete numeric (toDiscrete item.transactionItemPricePerUnit)
        <> "\n"

    taxLines = foldl
      ( \acc tax ->
          acc <> "  " <> tax.description <> " (" <> show (tax.rate * 100.0)
            <> "%): "
            <> formatDiscrete numeric (toDiscrete tax.amount)
            <> "\n"
      )
      ""
      item.transactionItemTaxes

    totalLine = "  Item Total: "
      <> formatDiscrete numeric (toDiscrete item.transactionItemTotal)
      <> "\n\n"
  in
    itemLine <> taxLines <> totalLine

formatPayment :: PaymentTransaction -> String
formatPayment (PaymentTransaction payment) =
  let
    paymentLine = "Paid (" <> show payment.method <> "): "
      <> formatDiscrete numeric (toDiscrete payment.amount)
      <> "\n"

    changeLine =
      if payment.change > (fromDiscrete' (Discrete 0)) then "Change: "
        <> formatDiscrete numeric (toDiscrete payment.change)
        <> "\n"
      else ""
  in
    paymentLine <> changeLine

openRegister
  :: UUID
  -> UUID
  -> Discrete USD
  -> Aff (Either RegisterError RegisterState)
openRegister registerId employeeId startingCash = do
  timestamp <- liftEffect nowDateTime

  liftEffect $ log $ "Opening register " <> uuidToString registerId
    <> " with "
    <> formatDiscrete numericC startingCash

  pure $ Right
    { registerId
    , isOpen: true
    , currentDrawerAmount: startingCash
    , currentTransaction: Nothing
    , openedAt: Just timestamp
    , openedBy: employeeId
    , lastTransactionTime: Nothing
    , expectedDrawerAmount: startingCash
    }
closeRegister
  :: RegisterState
  -> UUID
  -> Discrete USD
  -> Aff
       ( Either RegisterError
           { closingState :: RegisterState, variance :: Discrete USD }
       )
closeRegister state employeeId countedCash = do
  timestamp <- liftEffect nowDateTime

  liftEffect $ log $ "Closing register with counted amount: " <> formatDiscrete
    numericC
    countedCash

  if not state.isOpen then do
    liftEffect $ log "Cannot close register that is not open"
    pure $ Left RegisterClosed
  else do

    let variance = countedCash - state.expectedDrawerAmount

    let
      closedState = state
        { isOpen = false
        , currentDrawerAmount = countedCash
        , currentTransaction = Nothing
        , lastTransactionTime = Just timestamp
        }

    liftEffect $ log $ "Register closed with variance: " <> formatDiscrete
      numericC
      variance

    pure $ Right
      { closingState: closedState
      , variance
      }

calculateTaxes :: Discrete USD -> MenuItem -> Array TaxRecord
calculateTaxes amount menuItem =
  let
    MenuItem menuItemRecord = menuItem

    salesTaxRate = 0.08
    cannabisTaxRate = 0.15

    isCannabisProduct = case menuItemRecord.category of
      Flower -> true
      PreRolls -> true
      Vaporizers -> true
      Edibles -> true
      Drinks -> true
      Concentrates -> true
      Topicals -> true
      Tinctures -> true
      _ -> false

    amountInCents = unwrap amount

    salesTaxAmount = Discrete
      (Int.floor (Int.toNumber amountInCents * salesTaxRate))
    cannabisTaxAmount =
      if isCannabisProduct then
        Discrete (Int.floor (Int.toNumber amountInCents * cannabisTaxRate))
      else Discrete 0

    salesTax =
      { category: RegularSalesTax
      , rate: salesTaxRate
      , amount: fromDiscrete' salesTaxAmount
      , description: "Sales Tax"
      }

    cannabisTax =
      { category: CannabisTax
      , rate: cannabisTaxRate
      , amount: fromDiscrete' cannabisTaxAmount
      , description: "Cannabis Excise Tax"
      }
  in
    if cannabisTaxAmount > Discrete 0 then [ salesTax, cannabisTax ]
    else [ salesTax ]

processRefund
  :: { id :: UUID }
  -> Array UUID
  -> String
  -> UUID
  -> Aff (Either RegisterError Transaction)
processRefund originalTransaction itemIdsToRefund reason employeeId = do
  liftEffect $ log $ "Processing refund for transaction " <> uuidToString
    originalTransaction.id

  timestamp <- liftEffect nowDateTime

  let txId = originalTransaction.id

  -- TODO:  transaction with all required fields
  let
    txData = unwrap
      ( Transaction
          { transactionId: txId
          , transactionStatus: Completed
          , transactionCreated: timestamp
          , transactionCompleted: Just timestamp
          , transactionCustomerId: Nothing
          , transactionEmployeeId: dummyEmployeeId
          , transactionRegisterId: dummyRegisterId
          , transactionLocationId: dummyLocationId
          , transactionItems: []
          , transactionPayments: []
          , transactionSubtotal: fromDiscrete' (Discrete 0)
          , transactionDiscountTotal: fromDiscrete' (Discrete 0)
          , transactionTaxTotal: fromDiscrete' (Discrete 0)
          , transactionTotal: fromDiscrete' (Discrete 0)
          , transactionType: Sale
          , transactionIsVoided: false
          , transactionVoidReason: Nothing
          , transactionIsRefunded: false
          , transactionRefundReason: Nothing
          , transactionReferenceTransactionId: Nothing
          , transactionNotes: Nothing
          }
      )

  if txData.transactionIsRefunded then do
    liftEffect $ log "Transaction has already been refunded"
    pure $ Left $ InternalError "Transaction has already been refunded"
  else if txData.transactionIsVoided then do
    liftEffect $ log "Cannot refund a voided transaction"
    pure $ Left $ InternalError "Cannot refund a voided transaction"
  else do

    refundId <- liftEffect genUUID
    currentTimestamp <- liftEffect nowDateTime

    let
      itemsToRefund =
        if null itemIdsToRefund then txData.transactionItems
        else filter (\item -> contains itemIdsToRefund (unwrap item).transactionItemId)
          txData.transactionItems

      refundSubtotal = foldl
        (\acc item -> acc + (toDiscrete (unwrap item).transactionItemSubtotal))
        (Discrete 0)
        itemsToRefund
      refundTaxTotal = foldl
        ( \acc item ->
            foldl (\acc2 tax -> acc2 + (toDiscrete tax.amount)) acc
              (unwrap item).transactionItemTaxes
        )
        (Discrete 0)
        itemsToRefund
      refundTotal = refundSubtotal + refundTaxTotal

      refundPayment =
        { id: dummyPaymentId
        , transactionId: refundId
        , method: Cash
        , amount: fromDiscrete' (negate refundTotal)
        , tendered: fromDiscrete' (negate refundTotal)
        , change: fromDiscrete' (Discrete 0)
        , reference: Nothing
        , approved: true
        , authorizationCode: Nothing
        }

      refundTransaction =
        { transactionId: refundId
        , transactionStatus: Completed
        , transactionCreated: currentTimestamp
        , transactionCompleted: Just currentTimestamp
        , transactionCustomerId: txData.transactionCustomerId
        , transactionEmployeeId: employeeId
        , transactionRegisterId: txData.transactionRegisterId
        , transactionLocationId: txData.transactionLocationId
        , transactionItems: map makeRefundItem itemsToRefund
        , transactionPayments: [ PaymentTransaction refundPayment ]
        , transactionSubtotal: fromDiscrete' (negate refundSubtotal)
        , transactionDiscountTotal: fromDiscrete' (Discrete 0)
        , transactionTaxTotal: fromDiscrete' (negate refundTaxTotal)
        , transactionTotal: fromDiscrete' (negate refundTotal)
        , transactionType: Return
        , transactionIsVoided: false
        , transactionVoidReason: Nothing
        , transactionIsRefunded: false
        , transactionRefundReason: Just reason
        , transactionReferenceTransactionId: Just txId
        , transactionNotes: Just $ "Refund for transaction " <> uuidToString
            txId
        }

    liftEffect $ log $ "Refund processed: " <> uuidToString refundId
      <> ", Amount: "
      <> formatDiscrete numericC refundTotal

    pure $ Right (Transaction refundTransaction)
  where

  contains :: Array UUID -> UUID -> Boolean
  contains ids targetId =
    case Array.uncons ids of
      Nothing -> false
      Just { head, tail } ->
        if head == targetId then true
        else contains tail targetId

  makeRefundItem :: TransactionItem -> TransactionItem
  makeRefundItem (TransactionItem item) =
    TransactionItem $ item
      { transactionItemTransactionId = dummyTransactionId
      , transactionItemSubtotal = fromDiscrete' (negate (toDiscrete item.transactionItemSubtotal))
      , transactionItemTotal = fromDiscrete' (negate (toDiscrete item.transactionItemTotal))
      , transactionItemTaxes = map
          ( \tax -> tax
              { amount = fromDiscrete' (negate (toDiscrete tax.amount)) }
          )
          item.transactionItemTaxes
      }