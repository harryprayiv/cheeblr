-- src/DB/Transaction/Refund.hs

{-# LANGUAGE DisambiguateRecordFields #-}

-- | Hasql/Rel8 row encoders and decoders for the refund-side transaction
-- line types, plus the typed refund WRITE path.
--
-- The line-level encoders / decoders mirror 'DB.Transaction.Sale'. The
-- aggregate monetary fields are 'RefundMoney' — stored as negative
-- 'Int32' values in the DB. 'itemPricePerUnit' is 'SaleMoney' on both
-- sides (it's a non-negative rate, not a directional flow).
--
-- 'refundTxDomainToRow' encodes a full typed refund as a
-- 'TransactionRow' by going through the legacy 'Legacy.Transaction'
-- shape via 'refundToLegacyTransaction'. The intermediate legacy value
-- is throwaway; this composition is just DRY against the existing
-- 'DBT.txDomainToRow'.
--
-- 'writeTypedRefund' is the typed counterpart of the legacy
-- 'DB.Transaction.refundTransaction'. It takes a pre-built
-- 'Refund.RefundTransaction' and writes it directly to the DB, then
-- marks the original sale row as refunded. Unlike the legacy function,
-- it does NOT re-load the original sale to re-derive negations; the
-- typed value's pre-computed amounts go straight to the columns. The
-- 'toRefundTransaction' computation is now the single source of truth
-- for refund math.
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
    -- * Transaction (refund-shaped)
  , refundTxDomainToRow
  , writeTypedRefund
  ) where

import Control.Exception (throwIO)
import Control.Monad (forM_)
import Data.Scientific (fromFloatDigits)
import qualified Data.Text as T
import Data.UUID (UUID)
import Data.UUID.V4 (nextRandom)
import qualified Hasql.Session as Session
import Rel8

import DB.Database (DBPool, runSession)
import DB.Schema
import qualified DB.Transaction as DBT
import Types.Primitives.Money
  ( refundMoneyCents
  , saleMoneyCents
  , unsafeMkRefundMoney
  , unsafeMkSaleMoney
  )
import Types.Primitives.Quantity
  ( refundQuantityCount
  , unsafeMkRefundQuantity
  )
import qualified Types.Transaction as Legacy
import Types.Transaction.Conversion (refundToLegacyTransaction)
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

--------------------------------------------------------------------------------
-- Transaction (refund-shaped)

-- | Encode a typed refund as a 'TransactionRow Expr' for insert.
--
-- Implemented by routing through 'refundToLegacyTransaction' and
-- 'DBT.txDomainToRow'. The intermediate legacy value is throwaway; this
-- avoids a parallel copy of the column construction logic.
refundTxDomainToRow :: Refund.RefundTransaction -> TransactionRow Expr
refundTxDomainToRow = DBT.txDomainToRow . refundToLegacyTransaction

-- | Persist a typed 'Refund.RefundTransaction'.
--
-- Inserts the refund transaction row, its items (each with its taxes
-- and discounts), and its payments, then marks the original sale row's
-- @is_refunded@ flag. The amounts written are the typed value's pre-
-- computed fields; nothing is re-derived from the original sale.
--
-- Atomicity: NOT atomic. Each insert and the final update each run in
-- their own session. Matches the legacy 'DB.Transaction.refundTransaction'
-- semantics. A crash mid-write leaves a partially-inserted refund or a
-- refund without the original marked. Future cleanup: batch into one
-- session under a SQL transaction.
--
-- Existence check: a one-row read against the original sale before any
-- inserts, matching legacy behavior. Catches the narrow race where the
-- sale was deleted between the Service-layer load and this call.
--
-- Return value: the typed refund converted back via
-- 'refundToLegacyTransaction'. We do not re-read via 'hydrateTx'; the
-- typed value already has every field that hydrate would produce, by
-- construction.
writeTypedRefund :: DBPool -> Refund.RefundTransaction -> IO Legacy.Transaction
writeTypedRefund pool refund = do
  let origTxId = Refund.refundReferenceTransactionId refund
      reason   = Refund.refundReason refund

  -- Existence check on the original sale. Race-narrow guard; the
  -- service layer also loads the sale.
  mOrig <- DBT.getTransactionById pool origTxId
  case mOrig of
    Nothing -> throwIO $ userError $ "Original transaction not found: " <> show origTxId
    Just _  -> pure ()

  -- 1. Insert the refund transaction row.
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into       = transactionSchema
            , rows       = values [refundTxDomainToRow refund]
            , onConflict = Abort
            , returning  = NoReturning
            }

  -- 2. Insert the refund items, each with its taxes and discounts.
  forM_ (Refund.refundItems refund) $ \ri -> do
    runSession pool $
      Session.statement () $
        run_ $
          Rel8.insert $
            Insert
              { into       = transactionItemSchema
              , rows       = values [itemDomainToRow ri]
              , onConflict = Abort
              , returning  = NoReturning
              }
    forM_ (Refund.itemTaxes ri) $ \tax -> do
      taxId <- nextRandom
      runSession pool $
        Session.statement () $
          run_ $
            Rel8.insert $
              Insert
                { into       = taxSchema
                , rows       = values [taxDomainToRow taxId (Refund.itemId ri) tax]
                , onConflict = Abort
                , returning  = NoReturning
                }
    forM_ (Refund.itemDiscounts ri) $ \disc -> do
      discId <- nextRandom
      runSession pool $
        Session.statement () $
          run_ $
            Rel8.insert $
              Insert
                { into       = discountSchema
                , rows       = values [discountDomainToRow discId (Refund.itemId ri) Nothing disc]
                , onConflict = Abort
                , returning  = NoReturning
                }

  -- 3. Insert the refund payments.
  forM_ (Refund.refundPayments refund) $ \rp ->
    runSession pool $
      Session.statement () $
        run_ $
          Rel8.insert $
            Insert
              { into       = paymentSchema
              , rows       = values [paymentDomainToRow rp]
              , onConflict = Abort
              , returning  = NoReturning
              }

  -- 4. Mark the original sale as refunded.
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target      = transactionSchema
            , from        = pure ()
            , set         = \() row ->
                row
                  { txIsRefunded   = lit True
                  , txRefundReason = lit (Just reason)
                  }
            , updateWhere = \() row -> DB.Schema.txId row ==. lit origTxId
            , returning   = NoReturning
            }

  -- 5. Return the refund as a legacy 'Legacy.Transaction'.
  pure (refundToLegacyTransaction refund)