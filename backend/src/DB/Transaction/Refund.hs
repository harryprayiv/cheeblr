{-# LANGUAGE DisambiguateRecordFields #-}

-- | Hasql/Rel8 row encoders and decoders for the refund-side
-- transaction line types.
--
-- Mirrors 'DB.Transaction.Sale' for the refund types. Note that
-- 'itemPricePerUnit' is 'SaleMoney' on both sides (it's a non-negative
-- rate, not a directional flow), so it encodes and decodes the same
-- way regardless of which side this module belongs to. The aggregate
-- monetary fields ('itemSubtotal', 'itemTotal', 'discountAmount',
-- 'taxAmount', 'paymentAmount', etc.) are 'RefundMoney' — stored as
-- negative 'Int32' values in the DB.
--
-- 'itemQuantity' is 'RefundQuantity' — distinct from 'SaleQuantity'
-- at the type level but with the same non-negative invariant, so it
-- encodes to the same non-negative 'Int32' as a sale quantity would.
-- See the module documentation in 'Types.Primitives.Quantity' for the
-- rationale.
module DB.Transaction.Refund
  ( -- * Item
    itemDomainToRow
  , itemRowToDomain
    -- * Discount
  , discountDomainToRow
  , discountRowToDomain
    -- * Tax
  , taxDomainToRow
  , taxRowToDomain
    -- * Payment
  , paymentDomainToRow
  , paymentRowToDomain
  ) where

import Data.Scientific (fromFloatDigits)
import qualified Data.Text as T
import Data.UUID (UUID)
import Rel8

import DB.Schema (
  DiscountRow (..),
  PaymentRow (..),
  TaxRow (..),
  TransactionItemRow (..),
 )
import qualified DB.Transaction as DBT
import Types.Primitives.Money (
  refundMoneyCents,
  saleMoneyCents,
  unsafeMkRefundMoney,
  unsafeMkSaleMoney,
 )
import Types.Primitives.Quantity (
  refundQuantityCount,
  unsafeMkRefundQuantity,
 )
import qualified Types.Transaction.Refund as Refund

--------------------------------------------------------------------------------
-- Item

itemDomainToRow :: Refund.Item -> TransactionItemRow Expr
itemDomainToRow ri =
  TransactionItemRow
    { tiId            = lit (Refund.itemId ri)
    , tiTransactionId = lit (Refund.itemTransactionId ri)
    , tiMenuItemSku   = lit (Refund.itemMenuItemSku ri)
    , tiQuantity      = lit $ fromIntegral (refundQuantityCount (Refund.itemQuantity ri))
    , tiPricePerUnit  = lit $ fromIntegral (saleMoneyCents (Refund.itemPricePerUnit ri))
    , tiSubtotal      = lit $ fromIntegral (refundMoneyCents (Refund.itemSubtotal ri))
    , tiTotal         = lit $ fromIntegral (refundMoneyCents (Refund.itemTotal ri))
    }

itemRowToDomain ::
  TransactionItemRow Result ->
  [Refund.Tax] ->
  [Refund.Discount] ->
  Refund.Item
itemRowToDomain row taxes discounts =
  Refund.Item
    { Refund.itemId            = tiId row
    , Refund.itemTransactionId = tiTransactionId row
    , Refund.itemMenuItemSku   = tiMenuItemSku row
    , Refund.itemQuantity      = unsafeMkRefundQuantity (fromIntegral (tiQuantity row))
    , Refund.itemPricePerUnit  = unsafeMkSaleMoney (fromIntegral (tiPricePerUnit row))
    , Refund.itemDiscounts     = discounts
    , Refund.itemTaxes         = taxes
    , Refund.itemSubtotal      = unsafeMkRefundMoney (fromIntegral (tiSubtotal row))
    , Refund.itemTotal         = unsafeMkRefundMoney (fromIntegral (tiTotal row))
    }

--------------------------------------------------------------------------------
-- Discount

discountDomainToRow ::
  UUID -> UUID -> Maybe UUID -> Refund.Discount -> DiscountRow Expr
discountDomainToRow discId itemId mTxId d =
  DiscountRow
    { discRowId                = lit discId
    , discRowTransactionItemId = lit (Just itemId)
    , discRowTransactionId     = lit mTxId
    , discRowType              = lit $ DBT.showDiscountType (Refund.discountType d)
    , discRowAmount            = lit $ fromIntegral (refundMoneyCents (Refund.discountAmount d))
    , discRowPercent           = lit $ DBT.getDiscountPercent (Refund.discountType d)
    , discRowReason            = lit (Refund.discountReason d)
    , discRowApprovedBy        = lit (Refund.discountApprovedBy d)
    }

discountRowToDomain :: DiscountRow Result -> Refund.Discount
discountRowToDomain row =
  Refund.Discount
    { Refund.discountType =
        DBT.parseDiscountType
          (discRowType row)
          (discRowPercent row)
          (fromIntegral (discRowAmount row))
    , Refund.discountAmount =
        unsafeMkRefundMoney (fromIntegral (discRowAmount row))
    , Refund.discountReason     = discRowReason row
    , Refund.discountApprovedBy = discRowApprovedBy row
    }

--------------------------------------------------------------------------------
-- Tax

taxDomainToRow :: UUID -> UUID -> Refund.Tax -> TaxRow Expr
taxDomainToRow taxId itemId t =
  TaxRow
    { taxRowId                = lit taxId
    , taxRowTransactionItemId = lit itemId
    , taxRowCategory          = lit $ DBT.showTaxCategory (Refund.taxCategory t)
    , taxRowRate              = lit $ realToFrac (Refund.taxRate t)
    , taxRowAmount            = lit $ fromIntegral (refundMoneyCents (Refund.taxAmount t))
    , taxRowDescription       = lit (Refund.taxDescription t)
    }

taxRowToDomain :: TaxRow Result -> Refund.Tax
taxRowToDomain row =
  Refund.Tax
    { Refund.taxCategory    = DBT.parseTaxCategory (T.unpack (taxRowCategory row))
    , Refund.taxRate        = fromFloatDigits (taxRowRate row)
    , Refund.taxAmount      = unsafeMkRefundMoney (fromIntegral (taxRowAmount row))
    , Refund.taxDescription = taxRowDescription row
    }

--------------------------------------------------------------------------------
-- Payment

paymentDomainToRow :: Refund.Payment -> PaymentRow Expr
paymentDomainToRow p =
  PaymentRow
    { pymtId                = lit (Refund.paymentId p)
    , pymtTransactionId     = lit (Refund.paymentTransactionId p)
    , pymtMethod            = lit $ DBT.showPaymentMethod (Refund.paymentMethod p)
    , pymtAmount            = lit $ fromIntegral (refundMoneyCents (Refund.paymentAmount p))
    , pymtTendered          = lit $ fromIntegral (refundMoneyCents (Refund.paymentTendered p))
    , pymtChange            = lit $ fromIntegral (refundMoneyCents (Refund.paymentChange p))
    , pymtReference         = lit (Refund.paymentReference p)
    , pymtApproved          = lit (Refund.paymentApproved p)
    , pymtAuthorizationCode = lit (Refund.paymentAuthorizationCode p)
    }

paymentRowToDomain :: PaymentRow Result -> Refund.Payment
paymentRowToDomain row =
  Refund.Payment
    { Refund.paymentId            = pymtId row
    , Refund.paymentTransactionId = pymtTransactionId row
    , Refund.paymentMethod        = DBT.parsePaymentMethod (T.unpack (pymtMethod row))
    , Refund.paymentAmount        = unsafeMkRefundMoney (fromIntegral (pymtAmount row))
    , Refund.paymentTendered      = unsafeMkRefundMoney (fromIntegral (pymtTendered row))
    , Refund.paymentChange        = unsafeMkRefundMoney (fromIntegral (pymtChange row))
    , Refund.paymentReference     = pymtReference row
    , Refund.paymentApproved      = pymtApproved row
    , Refund.paymentAuthorizationCode = pymtAuthorizationCode row
    }