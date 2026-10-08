{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

-- | The sale operations a register calls. Each one takes a request that
-- says what is wanted, does the money on the server, and returns the whole
-- sale as it now stands.
--
-- State-machine guards, inventory reservation, domain events and stock
-- pulls stay in "Service.Transaction". This module adds what was missing
-- in front of it: the price comes from the menu, tax comes from the tax
-- rules in force, change is computed here, and ids are generated here.
-- Whether a sale may be completed is decided by the database layer under
-- the sale's row lock.
module Service.Sale (
  startSale,
  addItem,
  removeItem,
  addPayment,
  removePayment,
  clear,
  finalize,
) where

import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (fromMaybe)
import Data.Scientific (scientific)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.UUID (UUID)
import qualified Data.Vector as V
import Effectful
import Effectful.Error.Static
import Servant (ServerError (..), err400, err404, err409, err500)

import Domain.Pricing
  ( LinePricing (..)
  , LineTax (..)
  , PricingError (..)
  , priceLine
  , taxRatePpm
  )
import Domain.SaleRules (changeDue, paymentErrorText)
import Effect.Clock
import Effect.EventEmitter
import Effect.GenUUID
import qualified Effect.InventoryDb as EffInv
import qualified Effect.StockDb as StockDb
import Effect.TaxRules
import Effect.TransactionDb
import qualified Service.Transaction as Svc
import Types.Inventory (Inventory (..))
import qualified Types.Inventory as TI
import Types.Primitives.Money (unsafeMkSaleMoney, zeroSale)
import Types.Primitives.Quantity (unsafeMkSaleQuantity)
import Types.Transaction (TransactionStatus (..))
import Types.Transaction.Request
import qualified Types.Transaction.Sale as Sale

failWith :: (Error ServerError :> es) => ServerError -> Text -> Eff es a
failWith base message =
  throwError base {errBody = LBS.fromStrict (TE.encodeUtf8 message)}

loadSale ::
  (TransactionDb :> es, Error ServerError :> es) =>
  UUID ->
  Eff es Sale.SaleTransaction
loadSale saleId = do
  result <- getSaleById saleId
  case result of
    Right sale -> pure sale
    Left TypedNotFound ->
      failWith err404 "Sale not found"
    Left (TypedDecodeFailed e) ->
      failWith err500 ("Sale failed typed conversion: " <> e)
    Left TypedWrongKind ->
      failWith err409 "Cannot modify a refund transaction"

pricingErrorText :: PricingError -> Text
pricingErrorText (NonPositiveQuantity q) =
  "Quantity must be greater than zero, got " <> T.pack (show q)
pricingErrorText (NegativeUnitPrice p) =
  "Menu item has a negative price: " <> T.pack (show p)

-- | The stored form of a priced line. The rate is written as a decimal
-- fraction, so 62500 parts per million is stored as 0.0625.
toSaleItem :: UUID -> UUID -> UUID -> LinePricing -> Sale.Item
toSaleItem newItemId saleId sku pricing =
  Sale.Item
    { Sale.itemId            = newItemId
    , Sale.itemTransactionId = saleId
    , Sale.itemMenuItemSku   = sku
    , Sale.itemQuantity      = unsafeMkSaleQuantity (lineQuantity pricing)
    , Sale.itemPricePerUnit  = unsafeMkSaleMoney (lineUnitPrice pricing)
    , Sale.itemDiscounts     = []
    , Sale.itemTaxes         = map toSaleTax (lineTaxes pricing)
    , Sale.itemSubtotal      = unsafeMkSaleMoney (lineSubtotal pricing)
    , Sale.itemTotal         = unsafeMkSaleMoney (lineTotal pricing)
    }
  where
    toSaleTax tax =
      Sale.Tax
        { Sale.taxCategory    = lineTaxCategory tax
        , Sale.taxRate        = scientific (toInteger (taxRatePpm (lineTaxRate tax))) (-6)
        , Sale.taxAmount      = unsafeMkSaleMoney (lineTaxAmount tax)
        , Sale.taxDescription = lineTaxDescription tax
        }

-- | Open a new, empty sale. The backend generates the id and the
-- timestamp; totals start at zero.
startSale ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , GenUUID :> es
  ) =>
  StartSaleRequest ->
  Eff es Sale.SaleTransaction
startSale req = do
  newSaleId <- nextUUID
  now       <- currentTime
  Svc.createSaleSvc
    Sale.SaleTransaction
      { Sale.saleId            = newSaleId
      , Sale.saleStatus        = Created
      , Sale.saleCreated       = now
      , Sale.saleCompleted     = Nothing
      , Sale.saleCustomerId    = Nothing
      , Sale.saleEmployeeId    = startSaleEmployeeId req
      , Sale.saleRegisterId    = startSaleRegisterId req
      , Sale.saleLocationId    = startSaleLocationId req
      , Sale.saleItems         = []
      , Sale.salePayments      = []
      , Sale.saleSubtotal      = zeroSale
      , Sale.saleDiscountTotal = zeroSale
      , Sale.saleTaxTotal      = zeroSale
      , Sale.saleTotal         = zeroSale
      , Sale.saleKind          = Sale.StandardSale
      , Sale.saleIsVoided      = False
      , Sale.saleVoidReason    = Nothing
      , Sale.saleIsRefunded    = False
      , Sale.saleRefundReason  = Nothing
      , Sale.saleNotes         = Nothing
      }

-- | Add an item. The unit price is the menu price at this moment and the
-- taxes are the rules in force at the sale's location at this moment.
--
-- A sale holds one line per sku. When the sale already has a line for the
-- sku, the requested quantity is added to it and the line is priced again
-- at the combined quantity, keeping its id.
--
-- This function does not work out the combined quantity. It hands the
-- requested quantity and a pricing function to "Service.Transaction", and
-- the database layer reads the current line and prices the whole quantity
-- while it holds the sale's row lock. Two adds of the same sku to the same
-- sale therefore both count.
addItem ::
  ( TransactionDb :> es
  , StockDb.StockDb :> es
  , EffInv.InventoryDb :> es
  , TaxRules :> es
  , EventEmitter :> es
  , Clock :> es
  , GenUUID :> es
  , Error ServerError :> es
  ) =>
  AddItemRequest ->
  Eff es Sale.SaleTransaction
addItem req = do
  let saleId = addItemSaleId req
      sku    = addItemSku req
      addQty = addItemQuantity req
  sale <- loadSale saleId
  if addQty <= 0
    then failWith err400 (pricingErrorText (NonPositiveQuantity addQty))
    else pure ()
  now         <- currentTime
  rulesResult <- getActiveTaxRules (Sale.saleLocationId sale) now
  rules       <- case rulesResult of
    Right rs -> pure rs
    Left err -> failWith err500 ("Tax rules could not be read: " <> err)
  Inventory menu <- EffInv.getAllMenuItems
  menuItem <- case V.find (\m -> TI.sku m == sku) menu of
    Just m  -> pure m
    Nothing -> failWith err404 ("Item not found: " <> T.pack (show sku))
  let priceAt lineId wholeQty =
        case priceLine rules (TI.category menuItem) (TI.price menuItem) wholeQty of
          Right pricing -> Right (toSaleItem lineId saleId sku pricing)
          Left err      -> Left (pricingErrorText err)
  newItemId <- nextUUID
  _ <-
    Svc.addItem
      SaleLineAdd
        { lineAddSaleId    = saleId
        , lineAddSku       = sku
        , lineAddQuantity  = addQty
        , lineAddNewItemId = newItemId
        , lineAddPrice     = priceAt
        }
  loadSale saleId

removeItem ::
  ( TransactionDb :> es
  , StockDb.StockDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Eff es Sale.SaleTransaction
removeItem itemId = do
  mSaleId <- getTxIdByItemId itemId
  saleId  <- case mSaleId of
    Just sid -> pure sid
    Nothing  -> failWith err404 "Item not found"
  Svc.removeItem itemId
  loadSale saleId

-- | Record a payment. The change is computed here, and the payment is
-- marked approved here: there is no payment processor yet, so every
-- recorded payment is treated as taken.
addPayment ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , GenUUID :> es
  , Error ServerError :> es
  ) =>
  AddPaymentRequest ->
  Eff es Sale.SaleTransaction
addPayment req = do
  let saleId   = addPaymentSaleId req
      amount   = addPaymentAmount req
      tendered = fromMaybe amount (addPaymentTendered req)
  change <- case changeDue amount tendered of
    Right c  -> pure c
    Left err -> failWith err400 (paymentErrorText err)
  newPaymentId <- nextUUID
  _ <-
    Svc.addPayment
      Sale.Payment
        { Sale.paymentId                = newPaymentId
        , Sale.paymentTransactionId     = saleId
        , Sale.paymentMethod            = addPaymentMethod req
        , Sale.paymentAmount            = unsafeMkSaleMoney amount
        , Sale.paymentTendered          = unsafeMkSaleMoney tendered
        , Sale.paymentChange            = unsafeMkSaleMoney change
        , Sale.paymentReference         = addPaymentReference req
        , Sale.paymentApproved          = True
        , Sale.paymentAuthorizationCode = Nothing
        }
  loadSale saleId

removePayment ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Eff es Sale.SaleTransaction
removePayment paymentId = do
  mSaleId <- getTxIdByPaymentId paymentId
  saleId  <- case mSaleId of
    Just sid -> pure sid
    Nothing  -> failWith err404 "Payment not found"
  Svc.removePayment paymentId
  loadSale saleId

-- | Remove every item and payment from an open sale and return it empty.
-- A completed, voided or refunded sale cannot be cleared.
--
-- The check here gives an early 409. The database layer checks the status
-- again under the sale's row lock, so a clear cannot land on a sale that
-- was completed in between.
clear ::
  ( TransactionDb :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Eff es Sale.SaleTransaction
clear saleId = do
  sale <- loadSale saleId
  case Sale.saleStatus sale of
    Created    -> pure ()
    InProgress -> pure ()
    _          -> failWith err409 "Only an open sale can be cleared"
  outcome <- clearSale saleId
  case outcome of
    Left refusal -> Svc.refuseWrite refusal
    Right ()     -> loadSale saleId

-- | Complete a sale. Refused with every reason listed when the sale has no
-- items or its payments do not cover its total.
--
-- This function makes no check of its own. The database layer reads the
-- lines and the payments under the sale's row lock and decides there, so
-- the decision and the write cannot be separated by another request.
finalize ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Eff es Sale.SaleTransaction
finalize = Svc.finalizeTx