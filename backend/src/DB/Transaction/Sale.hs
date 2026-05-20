{-# LANGUAGE DisambiguateRecordFields #-}
-- {-# LANGUAGE OverloadedStrings #-}

-- | Hasql/Rel8 row encoders and decoders for the sale-side
-- transaction line types.
--
-- These functions are the boundary where typed primitives
-- ('SaleMoney', 'SaleQuantity') become raw 'Int32' database values
-- and vice versa. The decoders use 'unsafeMkSaleMoney' and
-- 'unsafeMkSaleQuantity' because the DB is treated as a trusted
-- source — any value already in the database was put there by code
-- that respected the invariants. See V1 in the hardening notes for
-- a planned future validation pass that will surface data
-- corruption at this boundary instead of silently producing
-- invariant-violating values.
--
-- The underlying DB schema is unchanged from the original
-- 'DB.Transaction' module — same tables, same columns, same
-- 'Int32' storage. The only difference is the Haskell-side domain
-- types these functions produce and consume.
module DB.Transaction.Sale
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
import Types.Primitives.Money (saleMoneyCents, unsafeMkSaleMoney)
import Types.Primitives.Quantity (
  saleQuantityCount,
  unsafeMkSaleQuantity,
 )
import qualified Types.Transaction.Sale as Sale

--------------------------------------------------------------------------------
-- Item

itemDomainToRow :: Sale.Item -> TransactionItemRow Expr
itemDomainToRow si =
  TransactionItemRow
    { tiId            = lit (Sale.itemId si)
    , tiTransactionId = lit (Sale.itemTransactionId si)
    , tiMenuItemSku   = lit (Sale.itemMenuItemSku si)
    , tiQuantity      = lit $ fromIntegral (saleQuantityCount (Sale.itemQuantity si))
    , tiPricePerUnit  = lit $ fromIntegral (saleMoneyCents (Sale.itemPricePerUnit si))
    , tiSubtotal      = lit $ fromIntegral (saleMoneyCents (Sale.itemSubtotal si))
    , tiTotal         = lit $ fromIntegral (saleMoneyCents (Sale.itemTotal si))
    }

itemRowToDomain ::
  TransactionItemRow Result ->
  [Sale.Tax] ->
  [Sale.Discount] ->
  Sale.Item
itemRowToDomain row taxes discounts =
  Sale.Item
    { Sale.itemId            = tiId row
    , Sale.itemTransactionId = tiTransactionId row
    , Sale.itemMenuItemSku   = tiMenuItemSku row
    , Sale.itemQuantity      = unsafeMkSaleQuantity (fromIntegral (tiQuantity row))
    , Sale.itemPricePerUnit  = unsafeMkSaleMoney (fromIntegral (tiPricePerUnit row))
    , Sale.itemDiscounts     = discounts
    , Sale.itemTaxes         = taxes
    , Sale.itemSubtotal      = unsafeMkSaleMoney (fromIntegral (tiSubtotal row))
    , Sale.itemTotal         = unsafeMkSaleMoney (fromIntegral (tiTotal row))
    }

--------------------------------------------------------------------------------
-- Discount

discountDomainToRow ::
  UUID -> UUID -> Maybe UUID -> Sale.Discount -> DiscountRow Expr
discountDomainToRow discId itemId mTxId d =
  DiscountRow
    { discRowId                = lit discId
    , discRowTransactionItemId = lit (Just itemId)
    , discRowTransactionId     = lit mTxId
    , discRowType              = lit $ DBT.showDiscountType (Sale.discountType d)
    , discRowAmount            = lit $ fromIntegral (saleMoneyCents (Sale.discountAmount d))
    , discRowPercent           = lit $ DBT.getDiscountPercent (Sale.discountType d)
    , discRowReason            = lit (Sale.discountReason d)
    , discRowApprovedBy        = lit (Sale.discountApprovedBy d)
    }

discountRowToDomain :: DiscountRow Result -> Sale.Discount
discountRowToDomain row =
  Sale.Discount
    { Sale.discountType =
        DBT.parseDiscountType
          (discRowType row)
          (discRowPercent row)
          (fromIntegral (discRowAmount row))
    , Sale.discountAmount =
        unsafeMkSaleMoney (fromIntegral (discRowAmount row))
    , Sale.discountReason     = discRowReason row
    , Sale.discountApprovedBy = discRowApprovedBy row
    }

--------------------------------------------------------------------------------
-- Tax

taxDomainToRow :: UUID -> UUID -> Sale.Tax -> TaxRow Expr
taxDomainToRow taxId itemId t =
  TaxRow
    { taxRowId                = lit taxId
    , taxRowTransactionItemId = lit itemId
    , taxRowCategory          = lit $ DBT.showTaxCategory (Sale.taxCategory t)
    , taxRowRate              = lit $ realToFrac (Sale.taxRate t)
    , taxRowAmount            = lit $ fromIntegral (saleMoneyCents (Sale.taxAmount t))
    , taxRowDescription       = lit (Sale.taxDescription t)
    }

taxRowToDomain :: TaxRow Result -> Sale.Tax
taxRowToDomain row =
  Sale.Tax
    { Sale.taxCategory    = DBT.parseTaxCategory (T.unpack (taxRowCategory row))
    , Sale.taxRate        = fromFloatDigits (taxRowRate row)
    , Sale.taxAmount      = unsafeMkSaleMoney (fromIntegral (taxRowAmount row))
    , Sale.taxDescription = taxRowDescription row
    }

--------------------------------------------------------------------------------
-- Payment

paymentDomainToRow :: Sale.Payment -> PaymentRow Expr
paymentDomainToRow p =
  PaymentRow
    { pymtId                = lit (Sale.paymentId p)
    , pymtTransactionId     = lit (Sale.paymentTransactionId p)
    , pymtMethod            = lit $ DBT.showPaymentMethod (Sale.paymentMethod p)
    , pymtAmount            = lit $ fromIntegral (saleMoneyCents (Sale.paymentAmount p))
    , pymtTendered          = lit $ fromIntegral (saleMoneyCents (Sale.paymentTendered p))
    , pymtChange            = lit $ fromIntegral (saleMoneyCents (Sale.paymentChange p))
    , pymtReference         = lit (Sale.paymentReference p)
    , pymtApproved          = lit (Sale.paymentApproved p)
    , pymtAuthorizationCode = lit (Sale.paymentAuthorizationCode p)
    }

paymentRowToDomain :: PaymentRow Result -> Sale.Payment
paymentRowToDomain row =
  Sale.Payment
    { Sale.paymentId            = pymtId row
    , Sale.paymentTransactionId = pymtTransactionId row
    , Sale.paymentMethod        = DBT.parsePaymentMethod (T.unpack (pymtMethod row))
    , Sale.paymentAmount        = unsafeMkSaleMoney (fromIntegral (pymtAmount row))
    , Sale.paymentTendered      = unsafeMkSaleMoney (fromIntegral (pymtTendered row))
    , Sale.paymentChange        = unsafeMkSaleMoney (fromIntegral (pymtChange row))
    , Sale.paymentReference     = pymtReference row
    , Sale.paymentApproved      = pymtApproved row
    , Sale.paymentAuthorizationCode = pymtAuthorizationCode row
    }