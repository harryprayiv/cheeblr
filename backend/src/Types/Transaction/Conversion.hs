{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Types.Transaction.Conversion
  ( -- * Typed sale → typed refund
    toRefundItem
  , toRefundDiscount
  , toRefundTax
  , toRefundPayment
  , toRefundTransaction

    -- * Legacy → typed
  , fromLegacyTransaction
  , saleItemFromLegacy
  , refundItemFromLegacy
  , saleDiscountFromLegacy
  , refundDiscountFromLegacy
  , saleTaxFromLegacy
  , refundTaxFromLegacy
  , salePaymentFromLegacy
  , refundPaymentFromLegacy

    -- * Typed refund → legacy
  , refundToLegacyTransaction
  , refundItemToLegacy
  , refundDiscountToLegacy
  , refundTaxToLegacy
  , refundPaymentToLegacy

    -- * Typed sale → legacy (2G-2)
  , saleToLegacyTransaction
  , saleItemToLegacy
  , saleDiscountToLegacy
  , saleTaxToLegacy
  , salePaymentToLegacy
  , saleTypeToLegacy
  ) where

import Control.Monad (when)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import Data.UUID (UUID)
import qualified Data.UUID as UUID

import Types.Primitives.Money
import Types.Primitives.Quantity
import qualified Types.Transaction as Legacy
import qualified Types.Transaction.Refund as Refund
import qualified Types.Transaction.Sale as Sale

-- ---------------------------------------------------------------------------
-- Typed sale → typed refund
-- ---------------------------------------------------------------------------

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

toRefundTransaction
  :: UTCTime
  -> UUID
  -> [UUID]
  -> [UUID]
  -> Text
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

-- ---------------------------------------------------------------------------
-- Legacy → typed
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Typed refund → legacy
-- ---------------------------------------------------------------------------

refundToLegacyTransaction :: Refund.RefundTransaction -> Legacy.Transaction
refundToLegacyTransaction r =
  Legacy.Transaction
    { Legacy.transactionId                     = Refund.refundId r
    , Legacy.transactionStatus                 = Legacy.Completed
    , Legacy.transactionCreated                = Refund.refundCreated r
    , Legacy.transactionCompleted              = Just (Refund.refundCompleted r)
    , Legacy.transactionCustomerId             = Refund.refundCustomerId r
    , Legacy.transactionEmployeeId             = Refund.refundEmployeeId r
    , Legacy.transactionRegisterId             = Refund.refundRegisterId r
    , Legacy.transactionLocationId             = Refund.refundLocationId r
    , Legacy.transactionItems                  = map refundItemToLegacy (Refund.refundItems r)
    , Legacy.transactionPayments               = map refundPaymentToLegacy (Refund.refundPayments r)
    , Legacy.transactionSubtotal               = refundMoneyCents (Refund.refundSubtotal r)
    , Legacy.transactionDiscountTotal          = refundMoneyCents (Refund.refundDiscountTotal r)
    , Legacy.transactionTaxTotal               = refundMoneyCents (Refund.refundTaxTotal r)
    , Legacy.transactionTotal                  = refundMoneyCents (Refund.refundTotal r)
    , Legacy.transactionType                   = Legacy.Return
    , Legacy.transactionIsVoided               = False
    , Legacy.transactionVoidReason             = Nothing
    , Legacy.transactionIsRefunded             = False
    , Legacy.transactionRefundReason           = Nothing
    , Legacy.transactionReferenceTransactionId = Just (Refund.refundReferenceTransactionId r)
    , Legacy.transactionNotes                  =
        Just $
          "Refund for transaction "
            <> T.pack (UUID.toString (Refund.refundReferenceTransactionId r))
            <> ": "
            <> Refund.refundReason r
    }

refundItemToLegacy :: Refund.Item -> Legacy.TransactionItem
refundItemToLegacy ri =
  Legacy.TransactionItem
    { Legacy.transactionItemId            = Refund.itemId ri
    , Legacy.transactionItemTransactionId = Refund.itemTransactionId ri
    , Legacy.transactionItemMenuItemSku   = Refund.itemMenuItemSku ri
    , Legacy.transactionItemQuantity      = refundQuantityCount (Refund.itemQuantity ri)
    , Legacy.transactionItemPricePerUnit  = saleMoneyCents (Refund.itemPricePerUnit ri)
    , Legacy.transactionItemDiscounts     = map refundDiscountToLegacy (Refund.itemDiscounts ri)
    , Legacy.transactionItemTaxes         = map refundTaxToLegacy (Refund.itemTaxes ri)
    , Legacy.transactionItemSubtotal      = refundMoneyCents (Refund.itemSubtotal ri)
    , Legacy.transactionItemTotal         = refundMoneyCents (Refund.itemTotal ri)
    }

refundDiscountToLegacy :: Refund.Discount -> Legacy.DiscountRecord
refundDiscountToLegacy d =
  Legacy.DiscountRecord
    { Legacy.discountType       = Refund.discountType d
    , Legacy.discountAmount     = refundMoneyCents (Refund.discountAmount d)
    , Legacy.discountReason     = Refund.discountReason d
    , Legacy.discountApprovedBy = Refund.discountApprovedBy d
    }

refundTaxToLegacy :: Refund.Tax -> Legacy.TaxRecord
refundTaxToLegacy t =
  Legacy.TaxRecord
    { Legacy.taxCategory    = Refund.taxCategory t
    , Legacy.taxRate        = Refund.taxRate t
    , Legacy.taxAmount      = refundMoneyCents (Refund.taxAmount t)
    , Legacy.taxDescription = Refund.taxDescription t
    }

refundPaymentToLegacy :: Refund.Payment -> Legacy.PaymentTransaction
refundPaymentToLegacy p =
  Legacy.PaymentTransaction
    { Legacy.paymentId                = Refund.paymentId p
    , Legacy.paymentTransactionId     = Refund.paymentTransactionId p
    , Legacy.paymentMethod            = Refund.paymentMethod p
    , Legacy.paymentAmount            = refundMoneyCents (Refund.paymentAmount p)
    , Legacy.paymentTendered          = refundMoneyCents (Refund.paymentTendered p)
    , Legacy.paymentChange            = refundMoneyCents (Refund.paymentChange p)
    , Legacy.paymentReference         = Refund.paymentReference p
    , Legacy.paymentApproved          = Refund.paymentApproved p
    , Legacy.paymentAuthorizationCode = Refund.paymentAuthorizationCode p
    }

-- ---------------------------------------------------------------------------
-- Typed sale → legacy (2G-2)
-- ---------------------------------------------------------------------------

-- | Convert a typed 'Sale.SaleTransaction' to a legacy 'Legacy.Transaction'.
--
-- The typed sale model does not carry a referenced transaction id, so
-- 'transactionReferenceTransactionId' is always 'Nothing'. Sales are not
-- voided-or-refunded at this layer (those flags are domain-level state
-- on the typed value); they map across directly.
--
-- Round-trip property:
-- @fromLegacyToSale st (saleToLegacyTransaction s) = Right s@
-- holds when @Sale.saleType s == st@. The legacy projection has no slot
-- for 'Sale.SaleType' separate from 'Legacy.TransactionType'; 'saleTypeToLegacy'
-- is total and surjective onto the non-'Return' constructors.
saleToLegacyTransaction :: Sale.SaleTransaction -> Legacy.Transaction
saleToLegacyTransaction s =
  Legacy.Transaction
    { Legacy.transactionId                     = Sale.saleId s
    , Legacy.transactionStatus                 = Sale.saleStatus s
    , Legacy.transactionCreated                = Sale.saleCreated s
    , Legacy.transactionCompleted              = Sale.saleCompleted s
    , Legacy.transactionCustomerId             = Sale.saleCustomerId s
    , Legacy.transactionEmployeeId             = Sale.saleEmployeeId s
    , Legacy.transactionRegisterId             = Sale.saleRegisterId s
    , Legacy.transactionLocationId             = Sale.saleLocationId s
    , Legacy.transactionItems                  = map saleItemToLegacy (Sale.saleItems s)
    , Legacy.transactionPayments               = map salePaymentToLegacy (Sale.salePayments s)
    , Legacy.transactionSubtotal               = saleMoneyCents (Sale.saleSubtotal s)
    , Legacy.transactionDiscountTotal          = saleMoneyCents (Sale.saleDiscountTotal s)
    , Legacy.transactionTaxTotal               = saleMoneyCents (Sale.saleTaxTotal s)
    , Legacy.transactionTotal                  = saleMoneyCents (Sale.saleTotal s)
    , Legacy.transactionType                   = saleTypeToLegacy (Sale.saleType s)
    , Legacy.transactionIsVoided               = Sale.saleIsVoided s
    , Legacy.transactionVoidReason             = Sale.saleVoidReason s
    , Legacy.transactionIsRefunded             = Sale.saleIsRefunded s
    , Legacy.transactionRefundReason           = Sale.saleRefundReason s
    , Legacy.transactionReferenceTransactionId = Nothing
    , Legacy.transactionNotes                  = Sale.saleNotes s
    }

saleItemToLegacy :: Sale.Item -> Legacy.TransactionItem
saleItemToLegacy si =
  Legacy.TransactionItem
    { Legacy.transactionItemId            = Sale.itemId si
    , Legacy.transactionItemTransactionId = Sale.itemTransactionId si
    , Legacy.transactionItemMenuItemSku   = Sale.itemMenuItemSku si
    , Legacy.transactionItemQuantity      = saleQuantityCount (Sale.itemQuantity si)
    , Legacy.transactionItemPricePerUnit  = saleMoneyCents (Sale.itemPricePerUnit si)
    , Legacy.transactionItemDiscounts     = map saleDiscountToLegacy (Sale.itemDiscounts si)
    , Legacy.transactionItemTaxes         = map saleTaxToLegacy (Sale.itemTaxes si)
    , Legacy.transactionItemSubtotal      = saleMoneyCents (Sale.itemSubtotal si)
    , Legacy.transactionItemTotal         = saleMoneyCents (Sale.itemTotal si)
    }

saleDiscountToLegacy :: Sale.Discount -> Legacy.DiscountRecord
saleDiscountToLegacy d =
  Legacy.DiscountRecord
    { Legacy.discountType       = Sale.discountType d
    , Legacy.discountAmount     = saleMoneyCents (Sale.discountAmount d)
    , Legacy.discountReason     = Sale.discountReason d
    , Legacy.discountApprovedBy = Sale.discountApprovedBy d
    }

saleTaxToLegacy :: Sale.Tax -> Legacy.TaxRecord
saleTaxToLegacy t =
  Legacy.TaxRecord
    { Legacy.taxCategory    = Sale.taxCategory t
    , Legacy.taxRate        = Sale.taxRate t
    , Legacy.taxAmount      = saleMoneyCents (Sale.taxAmount t)
    , Legacy.taxDescription = Sale.taxDescription t
    }

salePaymentToLegacy :: Sale.Payment -> Legacy.PaymentTransaction
salePaymentToLegacy p =
  Legacy.PaymentTransaction
    { Legacy.paymentId                = Sale.paymentId p
    , Legacy.paymentTransactionId     = Sale.paymentTransactionId p
    , Legacy.paymentMethod            = Sale.paymentMethod p
    , Legacy.paymentAmount            = saleMoneyCents (Sale.paymentAmount p)
    , Legacy.paymentTendered          = saleMoneyCents (Sale.paymentTendered p)
    , Legacy.paymentChange            = saleMoneyCents (Sale.paymentChange p)
    , Legacy.paymentReference         = Sale.paymentReference p
    , Legacy.paymentApproved          = Sale.paymentApproved p
    , Legacy.paymentAuthorizationCode = Sale.paymentAuthorizationCode p
    }

saleTypeToLegacy :: Sale.SaleType -> Legacy.TransactionType
saleTypeToLegacy Sale.StandardSale        = Legacy.Sale
saleTypeToLegacy Sale.Exchange            = Legacy.Exchange
saleTypeToLegacy Sale.InventoryAdjustment = Legacy.InventoryAdjustment
saleTypeToLegacy Sale.ManagerComp         = Legacy.ManagerComp
saleTypeToLegacy Sale.Administrative      = Legacy.Administrative