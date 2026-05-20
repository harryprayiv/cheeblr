-- src/Types/Transaction/Conversion.hs

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Conversions between the typed 'Sale.SaleTransaction' / 'Refund.RefundTransaction'
-- aggregates and the legacy untyped 'Legacy.Transaction', plus the typed
-- 'Sale' to 'Refund' direction used when issuing a refund.
--
-- Two directions:
--
-- [Sale to Refund] The typed conversion boundary that 2E-5 will use as
-- the named refund operation. 'toRefundTransaction' takes a
-- 'Sale.SaleTransaction', fresh UUIDs for the refund tx and each refund
-- child, a timestamp, and a reason, and produces a
-- 'Refund.RefundTransaction'. The amount-negation logic that used to live
-- inside 'DB.Transaction.refundTransaction' (and was duplicated in the pure
-- interpreter) now lives here as 'negateToRefund' calls at the typed
-- primitive layer.
--
-- [Legacy to Typed] 'fromLegacyTransaction' decodes the untyped
-- 'Legacy.Transaction' into 'Either Sale.SaleTransaction Refund.RefundTransaction'
-- based on 'Legacy.transactionType'. The outer 'Either Text' captures
-- conversion failures, which occur when:
--
--   * A sale-shaped legacy row carries a negative subtotal/total
--     ('SaleMoney' rejects negatives).
--   * A refund-shaped legacy row carries a positive subtotal/total
--     ('RefundMoney' rejects positives).
--   * A refund-shaped legacy row is missing required refund fields
--     ('transactionReferenceTransactionId', 'transactionRefundReason',
--     'transactionCompleted').
--
-- These failures should never happen on data we wrote ourselves; they
-- indicate either historical corruption or external mutation. Surfacing
-- them as 'Left' lets the DB hydration layer (2E-4) report the bad row
-- instead of silently producing an invariant-violating typed value.
--
-- Information loss in legacy-to-typed conversion (intentional):
--
--   * Sale-shaped legacy rows discard 'transactionReferenceTransactionId'.
--     Per the architecture decision, sales (including exchanges) do not
--     carry that field. Pre-existing data that uses it for exchanges loses
--     the link; record it elsewhere if you need it.
module Types.Transaction.Conversion
  ( -- * Sale to Refund
    toRefundItem
  , toRefundDiscount
  , toRefundTax
  , toRefundPayment
  , toRefundTransaction

    -- * Legacy to typed
  , fromLegacyTransaction
  , saleItemFromLegacy
  , refundItemFromLegacy
  , saleDiscountFromLegacy
  , refundDiscountFromLegacy
  , saleTaxFromLegacy
  , refundTaxFromLegacy
  , salePaymentFromLegacy
  , refundPaymentFromLegacy
  ) where

import Control.Monad (when)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import Data.UUID (UUID)

import Types.Primitives.Money
import Types.Primitives.Quantity
import qualified Types.Transaction as Legacy
import qualified Types.Transaction.Refund as Refund
import qualified Types.Transaction.Sale as Sale

--------------------------------------------------------------------------------
-- Sale to Refund
--------------------------------------------------------------------------------

-- | Convert a sale-side 'Sale.Item' into the refund-side shape with negated
-- aggregate amounts.
--
-- IDs are preserved; if the refund needs fresh IDs (it does for DB inserts
-- to avoid PK collision with the original sale), the caller overwrites
-- 'Refund.itemId' and 'Refund.itemTransactionId' after this call.
-- 'toRefundTransaction' does this in lockstep when it assembles the
-- aggregate.
toRefundItem :: Sale.Item -> Refund.Item
toRefundItem si =
  Refund.Item
    { Refund.itemId            = Sale.itemId si
    , Refund.itemTransactionId = Sale.itemTransactionId si
    , Refund.itemMenuItemSku   = Sale.itemMenuItemSku si
    , Refund.itemQuantity      = toRefundQuantity (Sale.itemQuantity si)
    , Refund.itemPricePerUnit  = Sale.itemPricePerUnit si
    , Refund.itemDiscounts     = map toRefundDiscount (Sale.itemDiscounts si)
    , Refund.itemTaxes         = map toRefundTax (Sale.itemTaxes si)
    , Refund.itemSubtotal      = negateToRefund (Sale.itemSubtotal si)
    , Refund.itemTotal         = negateToRefund (Sale.itemTotal si)
    }

toRefundDiscount :: Sale.Discount -> Refund.Discount
toRefundDiscount sd =
  Refund.Discount
    { Refund.discountType       = Sale.discountType sd
    , Refund.discountAmount     = negateToRefund (Sale.discountAmount sd)
    , Refund.discountReason     = Sale.discountReason sd
    , Refund.discountApprovedBy = Sale.discountApprovedBy sd
    }

toRefundTax :: Sale.Tax -> Refund.Tax
toRefundTax st =
  Refund.Tax
    { Refund.taxCategory    = Sale.taxCategory st
    , Refund.taxRate        = Sale.taxRate st
    , Refund.taxAmount      = negateToRefund (Sale.taxAmount st)
    , Refund.taxDescription = Sale.taxDescription st
    }

toRefundPayment :: Sale.Payment -> Refund.Payment
toRefundPayment sp =
  Refund.Payment
    { Refund.paymentId                = Sale.paymentId sp
    , Refund.paymentTransactionId     = Sale.paymentTransactionId sp
    , Refund.paymentMethod            = Sale.paymentMethod sp
    , Refund.paymentAmount            = negateToRefund (Sale.paymentAmount sp)
    , Refund.paymentTendered          = negateToRefund (Sale.paymentTendered sp)
    , Refund.paymentChange            = negateToRefund (Sale.paymentChange sp)
    , Refund.paymentReference         = Sale.paymentReference sp
    , Refund.paymentApproved          = Sale.paymentApproved sp
    , Refund.paymentAuthorizationCode = Sale.paymentAuthorizationCode sp
    }

-- | Construct a 'Refund.RefundTransaction' from a sale.
--
-- The caller supplies fresh UUIDs for the refund tx and for each refund line
-- item and payment, plus a timestamp and a reason. The item-id and
-- payment-id lists are positionally matched against the sale's children;
-- mismatched lengths return 'Left' with a diagnostic. Both new IDs replace
-- the original sale's IDs on the refund children, and
-- 'Refund.itemTransactionId' / 'Refund.paymentTransactionId' are repointed
-- at the new refund tx so the DB FKs are correct.
toRefundTransaction
  :: UTCTime
  -- ^ refund creation timestamp; also used for 'refundCompleted'
  -> UUID
  -- ^ fresh refund transaction id
  -> [UUID]
  -- ^ fresh refund item ids, one per sale item, in order
  -> [UUID]
  -- ^ fresh refund payment ids, one per sale payment, in order
  -> Text
  -- ^ reason
  -> Sale.SaleTransaction
  -> Either Text Refund.RefundTransaction
toRefundTransaction now refTxId itemIds pymtIds reason sale = do
  let saleItemList    = Sale.saleItems sale
      salePaymentList = Sale.salePayments sale
  when (length itemIds /= length saleItemList) $
    Left $
      "toRefundTransaction: expected "
        <> T.pack (show (length saleItemList))
        <> " refund item ids, got "
        <> T.pack (show (length itemIds))
  when (length pymtIds /= length salePaymentList) $
    Left $
      "toRefundTransaction: expected "
        <> T.pack (show (length salePaymentList))
        <> " refund payment ids, got "
        <> T.pack (show (length pymtIds))
  let refundItems =
        zipWith
          ( \newItemId si ->
              (toRefundItem si)
                { Refund.itemId            = newItemId
                , Refund.itemTransactionId = refTxId
                }
          )
          itemIds
          saleItemList
      refundPayments =
        zipWith
          ( \newPymtId sp ->
              (toRefundPayment sp)
                { Refund.paymentId            = newPymtId
                , Refund.paymentTransactionId = refTxId
                }
          )
          pymtIds
          salePaymentList
  Right $
    Refund.RefundTransaction
      { Refund.refundId                     = refTxId
      , Refund.refundCreated                = now
      , Refund.refundCompleted              = now
      , Refund.refundCustomerId             = Sale.saleCustomerId sale
      , Refund.refundEmployeeId             = Sale.saleEmployeeId sale
      , Refund.refundRegisterId             = Sale.saleRegisterId sale
      , Refund.refundLocationId             = Sale.saleLocationId sale
      , Refund.refundItems                  = refundItems
      , Refund.refundPayments               = refundPayments
      , Refund.refundSubtotal               = negateToRefund (Sale.saleSubtotal sale)
      , Refund.refundDiscountTotal          = negateToRefund (Sale.saleDiscountTotal sale)
      , Refund.refundTaxTotal               = negateToRefund (Sale.saleTaxTotal sale)
      , Refund.refundTotal                  = negateToRefund (Sale.saleTotal sale)
      , Refund.refundReferenceTransactionId = Sale.saleId sale
      , Refund.refundReason                 = reason
      , Refund.refundNotes                  = Nothing
      }

--------------------------------------------------------------------------------
-- Legacy to typed
--------------------------------------------------------------------------------

-- | Decode a legacy 'Legacy.Transaction' into the typed Sale-or-Refund split.
--
-- Dispatches on 'Legacy.transactionType'. 'Legacy.Return' becomes a
-- 'Refund.RefundTransaction'; all other variants become a
-- 'Sale.SaleTransaction' with the corresponding 'Sale.SaleType'. Returns
-- 'Left' on any invariant violation surfaced by the typed-primitive smart
-- constructors (negative sale money, positive refund money, etc.).
fromLegacyTransaction
  :: Legacy.Transaction
  -> Either Text (Either Sale.SaleTransaction Refund.RefundTransaction)
fromLegacyTransaction tx = case Legacy.transactionType tx of
  Legacy.Return              -> Right <$> fromLegacyToRefund tx
  Legacy.Sale                -> Left  <$> fromLegacyToSale Sale.StandardSale tx
  Legacy.Exchange            -> Left  <$> fromLegacyToSale Sale.Exchange tx
  Legacy.InventoryAdjustment -> Left  <$> fromLegacyToSale Sale.InventoryAdjustment tx
  Legacy.ManagerComp         -> Left  <$> fromLegacyToSale Sale.ManagerComp tx
  Legacy.Administrative      -> Left  <$> fromLegacyToSale Sale.Administrative tx

fromLegacyToSale
  :: Sale.SaleType
  -> Legacy.Transaction
  -> Either Text Sale.SaleTransaction
fromLegacyToSale st tx = do
  subtotal      <- saleMoneyOr "subtotal" (Legacy.transactionSubtotal tx)
  discountTotal <- saleMoneyOr "discountTotal" (Legacy.transactionDiscountTotal tx)
  taxTotal      <- saleMoneyOr "taxTotal" (Legacy.transactionTaxTotal tx)
  total         <- saleMoneyOr "total" (Legacy.transactionTotal tx)
  items         <- traverse saleItemFromLegacy (Legacy.transactionItems tx)
  payments      <- traverse salePaymentFromLegacy (Legacy.transactionPayments tx)
  Right $
    Sale.SaleTransaction
      { Sale.saleId            = Legacy.transactionId tx
      , Sale.saleStatus        = Legacy.transactionStatus tx
      , Sale.saleCreated       = Legacy.transactionCreated tx
      , Sale.saleCompleted     = Legacy.transactionCompleted tx
      , Sale.saleCustomerId    = Legacy.transactionCustomerId tx
      , Sale.saleEmployeeId    = Legacy.transactionEmployeeId tx
      , Sale.saleRegisterId    = Legacy.transactionRegisterId tx
      , Sale.saleLocationId    = Legacy.transactionLocationId tx
      , Sale.saleItems         = items
      , Sale.salePayments      = payments
      , Sale.saleSubtotal      = subtotal
      , Sale.saleDiscountTotal = discountTotal
      , Sale.saleTaxTotal      = taxTotal
      , Sale.saleTotal         = total
      , Sale.saleType          = st
      , Sale.saleIsVoided      = Legacy.transactionIsVoided tx
      , Sale.saleVoidReason    = Legacy.transactionVoidReason tx
      , Sale.saleIsRefunded    = Legacy.transactionIsRefunded tx
      , Sale.saleRefundReason  = Legacy.transactionRefundReason tx
      , Sale.saleNotes         = Legacy.transactionNotes tx
      }

fromLegacyToRefund :: Legacy.Transaction -> Either Text Refund.RefundTransaction
fromLegacyToRefund tx = do
  refTxId <- case Legacy.transactionReferenceTransactionId tx of
    Just rid -> Right rid
    Nothing  -> Left "legacy refund missing referenceTransactionId"
  reason <- case Legacy.transactionRefundReason tx of
    Just r  -> Right r
    Nothing -> Left "legacy refund missing refundReason"
  completed <- case Legacy.transactionCompleted tx of
    Just c  -> Right c
    Nothing -> Left "legacy refund missing completed timestamp"
  subtotal      <- refundMoneyOr "subtotal" (Legacy.transactionSubtotal tx)
  discountTotal <- refundMoneyOr "discountTotal" (Legacy.transactionDiscountTotal tx)
  taxTotal      <- refundMoneyOr "taxTotal" (Legacy.transactionTaxTotal tx)
  total         <- refundMoneyOr "total" (Legacy.transactionTotal tx)
  items         <- traverse refundItemFromLegacy (Legacy.transactionItems tx)
  payments      <- traverse refundPaymentFromLegacy (Legacy.transactionPayments tx)
  Right $
    Refund.RefundTransaction
      { Refund.refundId                     = Legacy.transactionId tx
      , Refund.refundCreated                = Legacy.transactionCreated tx
      , Refund.refundCompleted              = completed
      , Refund.refundCustomerId             = Legacy.transactionCustomerId tx
      , Refund.refundEmployeeId             = Legacy.transactionEmployeeId tx
      , Refund.refundRegisterId             = Legacy.transactionRegisterId tx
      , Refund.refundLocationId             = Legacy.transactionLocationId tx
      , Refund.refundItems                  = items
      , Refund.refundPayments               = payments
      , Refund.refundSubtotal               = subtotal
      , Refund.refundDiscountTotal          = discountTotal
      , Refund.refundTaxTotal               = taxTotal
      , Refund.refundTotal                  = total
      , Refund.refundReferenceTransactionId = refTxId
      , Refund.refundReason                 = reason
      , Refund.refundNotes                  = Legacy.transactionNotes tx
      }

--------------------------------------------------------------------------------
-- Legacy line items

saleItemFromLegacy :: Legacy.TransactionItem -> Either Text Sale.Item
saleItemFromLegacy ti = do
  qty      <- saleQuantityOr "itemQuantity" (Legacy.transactionItemQuantity ti)
  price    <- saleMoneyOr "itemPricePerUnit" (Legacy.transactionItemPricePerUnit ti)
  subtotal <- saleMoneyOr "itemSubtotal" (Legacy.transactionItemSubtotal ti)
  total    <- saleMoneyOr "itemTotal" (Legacy.transactionItemTotal ti)
  discs    <- traverse saleDiscountFromLegacy (Legacy.transactionItemDiscounts ti)
  taxes    <- traverse saleTaxFromLegacy (Legacy.transactionItemTaxes ti)
  Right $
    Sale.Item
      { Sale.itemId            = Legacy.transactionItemId ti
      , Sale.itemTransactionId = Legacy.transactionItemTransactionId ti
      , Sale.itemMenuItemSku   = Legacy.transactionItemMenuItemSku ti
      , Sale.itemQuantity      = qty
      , Sale.itemPricePerUnit  = price
      , Sale.itemDiscounts     = discs
      , Sale.itemTaxes         = taxes
      , Sale.itemSubtotal      = subtotal
      , Sale.itemTotal         = total
      }

refundItemFromLegacy :: Legacy.TransactionItem -> Either Text Refund.Item
refundItemFromLegacy ti = do
  qty      <- refundQuantityOr "itemQuantity" (Legacy.transactionItemQuantity ti)
  price    <- saleMoneyOr "itemPricePerUnit" (Legacy.transactionItemPricePerUnit ti)
  subtotal <- refundMoneyOr "itemSubtotal" (Legacy.transactionItemSubtotal ti)
  total    <- refundMoneyOr "itemTotal" (Legacy.transactionItemTotal ti)
  discs    <- traverse refundDiscountFromLegacy (Legacy.transactionItemDiscounts ti)
  taxes    <- traverse refundTaxFromLegacy (Legacy.transactionItemTaxes ti)
  Right $
    Refund.Item
      { Refund.itemId            = Legacy.transactionItemId ti
      , Refund.itemTransactionId = Legacy.transactionItemTransactionId ti
      , Refund.itemMenuItemSku   = Legacy.transactionItemMenuItemSku ti
      , Refund.itemQuantity      = qty
      , Refund.itemPricePerUnit  = price
      , Refund.itemDiscounts     = discs
      , Refund.itemTaxes         = taxes
      , Refund.itemSubtotal      = subtotal
      , Refund.itemTotal         = total
      }

saleDiscountFromLegacy :: Legacy.DiscountRecord -> Either Text Sale.Discount
saleDiscountFromLegacy d = do
  amt <- saleMoneyOr "discountAmount" (Legacy.discountAmount d)
  Right $
    Sale.Discount
      { Sale.discountType       = Legacy.discountType d
      , Sale.discountAmount     = amt
      , Sale.discountReason     = Legacy.discountReason d
      , Sale.discountApprovedBy = Legacy.discountApprovedBy d
      }

refundDiscountFromLegacy :: Legacy.DiscountRecord -> Either Text Refund.Discount
refundDiscountFromLegacy d = do
  amt <- refundMoneyOr "discountAmount" (Legacy.discountAmount d)
  Right $
    Refund.Discount
      { Refund.discountType       = Legacy.discountType d
      , Refund.discountAmount     = amt
      , Refund.discountReason     = Legacy.discountReason d
      , Refund.discountApprovedBy = Legacy.discountApprovedBy d
      }

saleTaxFromLegacy :: Legacy.TaxRecord -> Either Text Sale.Tax
saleTaxFromLegacy t = do
  amt <- saleMoneyOr "taxAmount" (Legacy.taxAmount t)
  Right $
    Sale.Tax
      { Sale.taxCategory    = Legacy.taxCategory t
      , Sale.taxRate        = Legacy.taxRate t
      , Sale.taxAmount      = amt
      , Sale.taxDescription = Legacy.taxDescription t
      }

refundTaxFromLegacy :: Legacy.TaxRecord -> Either Text Refund.Tax
refundTaxFromLegacy t = do
  amt <- refundMoneyOr "taxAmount" (Legacy.taxAmount t)
  Right $
    Refund.Tax
      { Refund.taxCategory    = Legacy.taxCategory t
      , Refund.taxRate        = Legacy.taxRate t
      , Refund.taxAmount      = amt
      , Refund.taxDescription = Legacy.taxDescription t
      }

salePaymentFromLegacy :: Legacy.PaymentTransaction -> Either Text Sale.Payment
salePaymentFromLegacy p = do
  amount   <- saleMoneyOr "paymentAmount" (Legacy.paymentAmount p)
  tendered <- saleMoneyOr "paymentTendered" (Legacy.paymentTendered p)
  change   <- saleMoneyOr "paymentChange" (Legacy.paymentChange p)
  Right $
    Sale.Payment
      { Sale.paymentId                = Legacy.paymentId p
      , Sale.paymentTransactionId     = Legacy.paymentTransactionId p
      , Sale.paymentMethod            = Legacy.paymentMethod p
      , Sale.paymentAmount            = amount
      , Sale.paymentTendered          = tendered
      , Sale.paymentChange            = change
      , Sale.paymentReference         = Legacy.paymentReference p
      , Sale.paymentApproved          = Legacy.paymentApproved p
      , Sale.paymentAuthorizationCode = Legacy.paymentAuthorizationCode p
      }

refundPaymentFromLegacy :: Legacy.PaymentTransaction -> Either Text Refund.Payment
refundPaymentFromLegacy p = do
  amount   <- refundMoneyOr "paymentAmount" (Legacy.paymentAmount p)
  tendered <- refundMoneyOr "paymentTendered" (Legacy.paymentTendered p)
  change   <- refundMoneyOr "paymentChange" (Legacy.paymentChange p)
  Right $
    Refund.Payment
      { Refund.paymentId                = Legacy.paymentId p
      , Refund.paymentTransactionId     = Legacy.paymentTransactionId p
      , Refund.paymentMethod            = Legacy.paymentMethod p
      , Refund.paymentAmount            = amount
      , Refund.paymentTendered          = tendered
      , Refund.paymentChange            = change
      , Refund.paymentReference         = Legacy.paymentReference p
      , Refund.paymentApproved          = Legacy.paymentApproved p
      , Refund.paymentAuthorizationCode = Legacy.paymentAuthorizationCode p
      }

--------------------------------------------------------------------------------
-- Internal validation helpers

saleMoneyOr :: Text -> Int -> Either Text SaleMoney
saleMoneyOr fieldName n = case mkSaleMoney n of
  Just m  -> Right m
  Nothing -> Left $ "sale " <> fieldName <> " must be >= 0, got " <> T.pack (show n)

refundMoneyOr :: Text -> Int -> Either Text RefundMoney
refundMoneyOr fieldName n = case mkRefundMoney n of
  Just m  -> Right m
  Nothing -> Left $ "refund " <> fieldName <> " must be <= 0, got " <> T.pack (show n)

saleQuantityOr :: Text -> Int -> Either Text SaleQuantity
saleQuantityOr fieldName n = case mkSaleQuantity n of
  Just q  -> Right q
  Nothing -> Left $ "sale " <> fieldName <> " must be >= 0, got " <> T.pack (show n)

refundQuantityOr :: Text -> Int -> Either Text RefundQuantity
refundQuantityOr fieldName n = case mkRefundQuantity n of
  Just q  -> Right q
  Nothing -> Left $ "refund " <> fieldName <> " must be >= 0, got " <> T.pack (show n)