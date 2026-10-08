{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}

-- | Conversions between the stored rows and the domain types, and the text
-- codes stored for statuses, types, payment methods and tax categories.
-- Nothing here touches the database.
module DB.Transaction.Rows where

import Data.Scientific (fromFloatDigits)
import Data.Text (Text)
import qualified Data.Text as T
import Data.UUID (UUID)
import Rel8 (Expr, Result, lit)

import DB.Schema
import Types.Location (LocationId (..), locationIdToUUID)
import Types.Transaction

txDomainToRow :: Transaction -> TransactionRow Expr
txDomainToRow tx =
  TransactionRow
    { txId                     = lit (transactionId tx)
    , txStatus                 = lit $ showStatus (transactionStatus tx)
    , txCreated                = lit (transactionCreated tx)
    , txCompleted              = lit (transactionCompleted tx)
    , txCustomerId             = lit (transactionCustomerId tx)
    , txEmployeeId             = lit (transactionEmployeeId tx)
    , txRegisterId             = lit (transactionRegisterId tx)
    , txLocationId             = lit (locationIdToUUID (transactionLocationId tx))
    , txSubtotal               = lit $ fromIntegral (transactionSubtotal tx)
    , txDiscountTotal          = lit $ fromIntegral (transactionDiscountTotal tx)
    , txTaxTotal               = lit $ fromIntegral (transactionTaxTotal tx)
    , txTotal                  = lit $ fromIntegral (transactionTotal tx)
    , txTransactionType        = lit $ showTransactionType (transactionType tx)
    , txIsVoided               = lit (transactionIsVoided tx)
    , txVoidReason             = lit (transactionVoidReason tx)
    , txIsRefunded             = lit (transactionIsRefunded tx)
    , txRefundReason           = lit (transactionRefundReason tx)
    , txReferenceTransactionId = lit (transactionReferenceTransactionId tx)
    , txNotes                  = lit (transactionNotes tx)
    }

txRowToDomain :: TransactionRow Result -> [TransactionItem] -> [PaymentTransaction] -> Transaction
txRowToDomain row items payments =
  Transaction
    { transactionId                     = DB.Schema.txId row
    , transactionStatus                 = parseTransactionStatus (T.unpack (txStatus row))
    , transactionCreated                = txCreated row
    , transactionCompleted              = txCompleted row
    , transactionCustomerId             = txCustomerId row
    , transactionEmployeeId             = txEmployeeId row
    , transactionRegisterId             = txRegisterId row
    , transactionLocationId             = LocationId (txLocationId row)
    , transactionItems                  = items
    , transactionPayments               = payments
    , transactionSubtotal               = fromIntegral (txSubtotal row)
    , transactionDiscountTotal          = fromIntegral (txDiscountTotal row)
    , transactionTaxTotal               = fromIntegral (txTaxTotal row)
    , transactionTotal                  = fromIntegral (txTotal row)
    , transactionType                   = parseTransactionType (T.unpack (txTransactionType row))
    , transactionIsVoided               = txIsVoided row
    , transactionVoidReason             = txVoidReason row
    , transactionIsRefunded             = txIsRefunded row
    , transactionRefundReason           = txRefundReason row
    , transactionReferenceTransactionId = txReferenceTransactionId row
    , transactionNotes                  = txNotes row
    }

tiDomainToRow :: TransactionItem -> TransactionItemRow Expr
tiDomainToRow ti =
  TransactionItemRow
    { tiId            = lit (transactionItemId ti)
    , tiTransactionId = lit (transactionItemTransactionId ti)
    , tiMenuItemSku   = lit (transactionItemMenuItemSku ti)
    , tiQuantity      = lit $ fromIntegral (transactionItemQuantity ti)
    , tiPricePerUnit  = lit $ fromIntegral (transactionItemPricePerUnit ti)
    , tiSubtotal      = lit $ fromIntegral (transactionItemSubtotal ti)
    , tiTotal         = lit $ fromIntegral (transactionItemTotal ti)
    }

itemRowToDomain :: TransactionItemRow Result -> [TaxRecord] -> [DiscountRecord] -> TransactionItem
itemRowToDomain row taxes discounts =
  TransactionItem
    { transactionItemId              = tiId row
    , transactionItemTransactionId   = tiTransactionId row
    , transactionItemMenuItemSku     = tiMenuItemSku row
    , transactionItemQuantity        = fromIntegral (tiQuantity row)
    , transactionItemPricePerUnit    = fromIntegral (tiPricePerUnit row)
    , transactionItemDiscounts       = discounts
    , transactionItemTaxes           = taxes
    , transactionItemSubtotal        = fromIntegral (tiSubtotal row)
    , transactionItemTotal           = fromIntegral (tiTotal row)
    }

taxDomainToRow :: UUID -> UUID -> TaxRecord -> TaxRow Expr
taxDomainToRow taxId itemId tax =
  TaxRow
    { taxRowId                = lit taxId
    , taxRowTransactionItemId = lit itemId
    , taxRowCategory          = lit $ showTaxCategory (taxCategory tax)
    , taxRowRate              = lit $ realToFrac (taxRate tax)
    , taxRowAmount            = lit $ fromIntegral (taxAmount tax)
    , taxRowDescription       = lit (taxDescription tax)
    }

taxRowToDomain :: TaxRow Result -> TaxRecord
taxRowToDomain row =
  TaxRecord
    { taxCategory    = parseTaxCategory (T.unpack (taxRowCategory row))
    , taxRate        = fromFloatDigits (taxRowRate row)
    , taxAmount      = fromIntegral (taxRowAmount row)
    , taxDescription = taxRowDescription row
    }

discountDomainToRow :: UUID -> UUID -> Maybe UUID -> DiscountRecord -> DiscountRow Expr
discountDomainToRow discId itemId mTxId discount =
  DiscountRow
    { discRowId                = lit discId
    , discRowTransactionItemId = lit (Just itemId)
    , discRowTransactionId     = lit mTxId
    , discRowType              = lit $ showDiscountType (discountType discount)
    , discRowAmount            = lit $ fromIntegral (discountAmount discount)
    , discRowPercent           = lit $ getDiscountPercent (discountType discount)
    , discRowReason            = lit (discountReason discount)
    , discRowApprovedBy        = lit (discountApprovedBy discount)
    }

getDiscountPercent :: DiscountType -> Maybe Double
getDiscountPercent (PercentOff pct) = Just (realToFrac pct)
getDiscountPercent _                = Nothing

discountRowToDomain :: DiscountRow Result -> DiscountRecord
discountRowToDomain row =
  DiscountRecord
    { discountType       = parseDiscountType
                             (discRowType row)
                             (discRowPercent row)
                             (fromIntegral (discRowAmount row))
    , discountAmount     = fromIntegral (discRowAmount row)
    , discountReason     = discRowReason row
    , discountApprovedBy = discRowApprovedBy row
    }

paymentDomainToRow :: PaymentTransaction -> PaymentRow Expr
paymentDomainToRow p =
  PaymentRow
    { pymtId                = lit (paymentId p)
    , pymtTransactionId     = lit (paymentTransactionId p)
    , pymtMethod            = lit $ showPaymentMethod (paymentMethod p)
    , pymtAmount            = lit $ fromIntegral (paymentAmount p)
    , pymtTendered          = lit $ fromIntegral (paymentTendered p)
    , pymtChange            = lit $ fromIntegral (paymentChange p)
    , pymtReference         = lit (paymentReference p)
    , pymtApproved          = lit (paymentApproved p)
    , pymtAuthorizationCode = lit (paymentAuthorizationCode p)
    }

paymentRowToDomain :: PaymentRow Result -> PaymentTransaction
paymentRowToDomain row =
  PaymentTransaction
    { paymentId               = pymtId row
    , paymentTransactionId    = pymtTransactionId row
    , paymentMethod           = parsePaymentMethod (T.unpack (pymtMethod row))
    , paymentAmount           = fromIntegral (pymtAmount row)
    , paymentTendered         = fromIntegral (pymtTendered row)
    , paymentChange           = fromIntegral (pymtChange row)
    , paymentReference        = pymtReference row
    , paymentApproved         = pymtApproved row
    , paymentAuthorizationCode = pymtAuthorizationCode row
    }

negateTransactionItem :: TransactionItem -> TransactionItem
negateTransactionItem ti =
  ti
    { transactionItemDiscounts = map negateDiscountRecord (transactionItemDiscounts ti)
    , transactionItemTaxes     = map negateTaxRecord (transactionItemTaxes ti)
    , transactionItemSubtotal  = negate (transactionItemSubtotal ti)
    , transactionItemTotal     = negate (transactionItemTotal ti)
    }

negateDiscountRecord :: DiscountRecord -> DiscountRecord
negateDiscountRecord d = d {discountAmount = negate (discountAmount d)}

negateTaxRecord :: TaxRecord -> TaxRecord
negateTaxRecord t = t {taxAmount = negate (taxAmount t)}

negatePaymentTransaction :: PaymentTransaction -> PaymentTransaction
negatePaymentTransaction p =
  p
    { paymentAmount   = negate (paymentAmount p)
    , paymentTendered = negate (paymentTendered p)
    , paymentChange   = negate (paymentChange p)
    }

showStatus :: TransactionStatus -> Text
showStatus Created    = "CREATED"
showStatus InProgress = "IN_PROGRESS"
showStatus Completed  = "COMPLETED"
showStatus Voided     = "VOIDED"
showStatus Refunded   = "REFUNDED"

showTransactionType :: TransactionType -> Text
showTransactionType Sale                = "SALE"
showTransactionType Return              = "RETURN"
showTransactionType Exchange            = "EXCHANGE"
showTransactionType InventoryAdjustment = "INVENTORY_ADJUSTMENT"
showTransactionType ManagerComp         = "MANAGER_COMP"
showTransactionType Administrative      = "ADMINISTRATIVE"

showPaymentMethod :: PaymentMethod -> Text
showPaymentMethod Cash        = "CASH"
showPaymentMethod Debit       = "DEBIT"
showPaymentMethod Credit      = "CREDIT"
showPaymentMethod ACH         = "ACH"
showPaymentMethod GiftCard    = "GIFT_CARD"
showPaymentMethod StoredValue = "STORED_VALUE"
showPaymentMethod Mixed       = "MIXED"
showPaymentMethod (Other t)   = "OTHER:" <> t

showTaxCategory :: TaxCategory -> Text
showTaxCategory RegularSalesTax = "REGULAR_SALES_TAX"
showTaxCategory ExciseTax       = "EXCISE_TAX"
showTaxCategory CannabisTax     = "CANNABIS_TAX"
showTaxCategory LocalTax        = "LOCAL_TAX"
showTaxCategory MedicalTax      = "MEDICAL_TAX"
showTaxCategory NoTax           = "NO_TAX"

showDiscountType :: DiscountType -> Text
showDiscountType (PercentOff _) = "PERCENT_OFF"
showDiscountType (AmountOff _)  = "AMOUNT_OFF"
showDiscountType BuyOneGetOne   = "BUY_ONE_GET_ONE"
showDiscountType (Custom _ _)   = "CUSTOM"

parseDiscountType :: Text -> Maybe Double -> Int -> DiscountType
parseDiscountType "PERCENT_OFF"     mPct _   = PercentOff (maybe 0 realToFrac mPct)
parseDiscountType "AMOUNT_OFF"      _    amt = AmountOff amt
parseDiscountType "BUY_ONE_GET_ONE" _    _   = BuyOneGetOne
parseDiscountType typ               _    amt = Custom typ amt

parseTransactionStatus :: String -> TransactionStatus
parseTransactionStatus "CREATED"     = Created
parseTransactionStatus "IN_PROGRESS" = InProgress
parseTransactionStatus "COMPLETED"   = Completed
parseTransactionStatus "VOIDED"      = Voided
parseTransactionStatus "REFUNDED"    = Refunded
parseTransactionStatus _             = Created

parseTransactionType :: String -> TransactionType
parseTransactionType "SALE"                 = Sale
parseTransactionType "RETURN"               = Return
parseTransactionType "EXCHANGE"             = Exchange
parseTransactionType "INVENTORY_ADJUSTMENT" = InventoryAdjustment
parseTransactionType "MANAGER_COMP"         = ManagerComp
parseTransactionType "ADMINISTRATIVE"       = Administrative
parseTransactionType _                      = Sale

parsePaymentMethod :: String -> PaymentMethod
parsePaymentMethod "CASH"         = Cash
parsePaymentMethod "Cash"         = Cash
parsePaymentMethod "DEBIT"        = Debit
parsePaymentMethod "Debit"        = Debit
parsePaymentMethod "CREDIT"       = Credit
parsePaymentMethod "Credit"       = Credit
parsePaymentMethod "ACH"          = ACH
parsePaymentMethod "GIFT_CARD"    = GiftCard
parsePaymentMethod "GiftCard"     = GiftCard
parsePaymentMethod "STORED_VALUE" = StoredValue
parsePaymentMethod "StoredValue"  = StoredValue
parsePaymentMethod "MIXED"        = Mixed
parsePaymentMethod "Mixed"        = Mixed
parsePaymentMethod s
  | take 6 s == "OTHER:" = Other (T.pack $ drop 6 s)
  | take 6 s == "Other:" = Other (T.pack $ drop 6 s)
  | otherwise            = Other (T.pack s)

parseTaxCategory :: String -> TaxCategory
parseTaxCategory "REGULAR_SALES_TAX" = RegularSalesTax
parseTaxCategory "RegularSalesTax"   = RegularSalesTax
parseTaxCategory "EXCISE_TAX"        = ExciseTax
parseTaxCategory "ExciseTax"         = ExciseTax
parseTaxCategory "CANNABIS_TAX"      = CannabisTax
parseTaxCategory "CannabisTax"       = CannabisTax
parseTaxCategory "LOCAL_TAX"         = LocalTax
parseTaxCategory "LocalTax"          = LocalTax
parseTaxCategory "MEDICAL_TAX"       = MedicalTax
parseTaxCategory "MedicalTax"        = MedicalTax
parseTaxCategory "NO_TAX"            = NoTax
parseTaxCategory "NoTax"             = NoTax
parseTaxCategory _                   = NoTax
