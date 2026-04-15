{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module DB.Schema where

import Data.Int (Int32)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import Rel8

data MenuItemRow f = MenuItemRow
  { menuSort :: Column f Int32
  , menuSku :: Column f UUID
  , menuBrand :: Column f Text
  , menuName :: Column f Text
  , menuPrice :: Column f Int32
  , menuMeasureUnit :: Column f Text
  , menuPerPackage :: Column f Text
  , menuQuantity :: Column f Int32
  , menuCategory :: Column f Text
  , menuSubcategory :: Column f Text
  , menuDescription :: Column f Text
  , menuTags :: Column f [Text]
  , menuEffects :: Column f [Text]
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance (f ~ Result) => Show (MenuItemRow f)

menuItemSchema :: TableSchema (MenuItemRow Name)
menuItemSchema =
  TableSchema
    { name = "menu_items"
    , columns =
        MenuItemRow
          { menuSort = "sort"
          , menuSku = "sku"
          , menuBrand = "brand"
          , menuName = "name"
          , menuPrice = "price"
          , menuMeasureUnit = "measure_unit"
          , menuPerPackage = "per_package"
          , menuQuantity = "quantity"
          , menuCategory = "category"
          , menuSubcategory = "subcategory"
          , menuDescription = "description"
          , menuTags = "tags"
          , menuEffects = "effects"
          }
    }

data StrainLineageRow f = StrainLineageRow
  { slSku :: Column f UUID
  , slThc :: Column f Text
  , slCbg :: Column f Text
  , slStrain :: Column f Text
  , slCreator :: Column f Text
  , slSpecies :: Column f Text
  , slDominantTerpene :: Column f Text
  , slTerpenes :: Column f [Text]
  , slLineage :: Column f [Text]
  , slLeaflyUrl :: Column f Text
  , slImg :: Column f Text
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance (f ~ Result) => Show (StrainLineageRow f)

strainLineageSchema :: TableSchema (StrainLineageRow Name)
strainLineageSchema =
  TableSchema
    { name = "strain_lineage"
    , columns =
        StrainLineageRow
          { slSku = "sku"
          , slThc = "thc"
          , slCbg = "cbg"
          , slStrain = "strain"
          , slCreator = "creator"
          , slSpecies = "species"
          , slDominantTerpene = "dominant_terpene"
          , slTerpenes = "terpenes"
          , slLineage = "lineage"
          , slLeaflyUrl = "leafly_url"
          , slImg = "img"
          }
    }

data TransactionRow f = TransactionRow
  { txId :: Column f UUID
  , txStatus :: Column f Text
  , txCreated :: Column f UTCTime
  , txCompleted :: Column f (Maybe UTCTime)
  , txCustomerId :: Column f (Maybe UUID)
  , txEmployeeId :: Column f UUID
  , txRegisterId :: Column f UUID
  , txLocationId :: Column f UUID
  , txSubtotal :: Column f Int32
  , txDiscountTotal :: Column f Int32
  , txTaxTotal :: Column f Int32
  , txTotal :: Column f Int32
  , txTransactionType :: Column f Text
  , txIsVoided :: Column f Bool
  , txVoidReason :: Column f (Maybe Text)
  , txIsRefunded :: Column f Bool
  , txRefundReason :: Column f (Maybe Text)
  , txReferenceTransactionId :: Column f (Maybe UUID)
  , txNotes :: Column f (Maybe Text)
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance (f ~ Result) => Show (TransactionRow f)

transactionSchema :: TableSchema (TransactionRow Name)
transactionSchema =
  TableSchema
    { name = "transaction"
    , columns =
        TransactionRow
          { txId = "id"
          , txStatus = "status"
          , txCreated = "created"
          , txCompleted = "completed"
          , txCustomerId = "customer_id"
          , txEmployeeId = "employee_id"
          , txRegisterId = "register_id"
          , txLocationId = "location_id"
          , txSubtotal = "subtotal"
          , txDiscountTotal = "discount_total"
          , txTaxTotal = "tax_total"
          , txTotal = "total"
          , txTransactionType = "transaction_type"
          , txIsVoided = "is_voided"
          , txVoidReason = "void_reason"
          , txIsRefunded = "is_refunded"
          , txRefundReason = "refund_reason"
          , txReferenceTransactionId = "reference_transaction_id"
          , txNotes = "notes"
          }
    }

data TransactionItemRow f = TransactionItemRow
  { tiId :: Column f UUID
  , tiTransactionId :: Column f UUID
  , tiMenuItemSku :: Column f UUID
  , tiQuantity :: Column f Int32
  , tiPricePerUnit :: Column f Int32
  , tiSubtotal :: Column f Int32
  , tiTotal :: Column f Int32
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance (f ~ Result) => Show (TransactionItemRow f)

transactionItemSchema :: TableSchema (TransactionItemRow Name)
transactionItemSchema =
  TableSchema
    { name = "transaction_item"
    , columns =
        TransactionItemRow
          { tiId = "id"
          , tiTransactionId = "transaction_id"
          , tiMenuItemSku = "menu_item_sku"
          , tiQuantity = "quantity"
          , tiPricePerUnit = "price_per_unit"
          , tiSubtotal = "subtotal"
          , tiTotal = "total"
          }
    }

data TaxRow f = TaxRow
  { taxRowId :: Column f UUID
  , taxRowTransactionItemId :: Column f UUID
  , taxRowCategory :: Column f Text
  , taxRowRate :: Column f Double
  , taxRowAmount :: Column f Int32
  , taxRowDescription :: Column f Text
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance (f ~ Result) => Show (TaxRow f)

taxSchema :: TableSchema (TaxRow Name)
taxSchema =
  TableSchema
    { name = "transaction_tax"
    , columns =
        TaxRow
          { taxRowId = "id"
          , taxRowTransactionItemId = "transaction_item_id"
          , taxRowCategory = "category"
          , taxRowRate = "rate"
          , taxRowAmount = "amount"
          , taxRowDescription = "description"
          }
    }

data DiscountRow f = DiscountRow
  { discRowId :: Column f UUID
  , discRowTransactionItemId :: Column f (Maybe UUID)
  , discRowTransactionId :: Column f (Maybe UUID)
  , discRowType :: Column f Text
  , discRowAmount :: Column f Int32
  , discRowPercent :: Column f (Maybe Double)
  , discRowReason :: Column f Text
  , discRowApprovedBy :: Column f (Maybe UUID)
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance (f ~ Result) => Show (DiscountRow f)

discountSchema :: TableSchema (DiscountRow Name)
discountSchema =
  TableSchema
    { name = "discount"
    , columns =
        DiscountRow
          { discRowId = "id"
          , discRowTransactionItemId = "transaction_item_id"
          , discRowTransactionId = "transaction_id"
          , discRowType = "type"
          , discRowAmount = "amount"
          , discRowPercent = "percent"
          , discRowReason = "reason"
          , discRowApprovedBy = "approved_by"
          }
    }

data PaymentRow f = PaymentRow
  { pymtId :: Column f UUID
  , pymtTransactionId :: Column f UUID
  , pymtMethod :: Column f Text
  , pymtAmount :: Column f Int32
  , pymtTendered :: Column f Int32
  , pymtChange :: Column f Int32
  , pymtReference :: Column f (Maybe Text)
  , pymtApproved :: Column f Bool
  , pymtAuthorizationCode :: Column f (Maybe Text)
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance (f ~ Result) => Show (PaymentRow f)

paymentSchema :: TableSchema (PaymentRow Name)
paymentSchema =
  TableSchema
    { name = "payment_transaction"
    , columns =
        PaymentRow
          { pymtId = "id"
          , pymtTransactionId = "transaction_id"
          , pymtMethod = "method"
          , pymtAmount = "amount"
          , pymtTendered = "tendered"
          , pymtChange = "change_amount"
          , pymtReference = "reference"
          , pymtApproved = "approved"
          , pymtAuthorizationCode = "authorization_code"
          }
    }

data ReservationRow f = ReservationRow
  { resId :: Column f UUID
  , resItemSku :: Column f UUID
  , resTransactionId :: Column f UUID
  , resQuantity :: Column f Int32
  , resStatus :: Column f Text
  , resCreatedAt :: Column f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance (f ~ Result) => Show (ReservationRow f)

reservationSchema :: TableSchema (ReservationRow Name)
reservationSchema =
  TableSchema
    { name = "inventory_reservation"
    , columns =
        ReservationRow
          { resId = "id"
          , resItemSku = "item_sku"
          , resTransactionId = "transaction_id"
          , resQuantity = "quantity"
          , resStatus = "status"
          , resCreatedAt = "created_at"
          }
    }

data RegisterRow f = RegisterRow
  { regId :: Column f UUID
  , regName :: Column f Text
  , regLocationId :: Column f UUID
  , regIsOpen :: Column f Bool
  , regCurrentDrawerAmount :: Column f Int32
  , regExpectedDrawerAmount :: Column f Int32
  , regOpenedAt :: Column f (Maybe UTCTime)
  , regOpenedBy :: Column f (Maybe UUID)
  , regLastTransactionTime :: Column f (Maybe UTCTime)
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance (f ~ Result) => Show (RegisterRow f)

registerSchema :: TableSchema (RegisterRow Name)
registerSchema =
  TableSchema
    { name = "register"
    , columns =
        RegisterRow
          { regId = "id"
          , regName = "name"
          , regLocationId = "location_id"
          , regIsOpen = "is_open"
          , regCurrentDrawerAmount = "current_drawer_amount"
          , regExpectedDrawerAmount = "expected_drawer_amount"
          , regOpenedAt = "opened_at"
          , regOpenedBy = "opened_by"
          , regLastTransactionTime = "last_transaction_time"
          }
    }

data UserRow f = UserRow
  { userId :: Column f UUID
  , userName :: Column f Text
  , displayName :: Column f Text
  , email :: Column f (Maybe Text)
  , userRole :: Column f Text
  , userLocationId :: Column f (Maybe UUID)
  , passwordHash :: Column f Text
  , isActive :: Column f Bool
  , userCreatedAt :: Column f UTCTime
  , userUpdatedAt :: Column f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance (f ~ Result) => Show (UserRow f)

userSchema :: TableSchema (UserRow Name)
userSchema =
  TableSchema
    { name = "users"
    , columns =
        UserRow
          { userId = "id"
          , userName = "username"
          , displayName = "display_name"
          , email = "email"
          , userRole = "role"
          , userLocationId = "location_id"
          , passwordHash = "password_hash"
          , isActive = "is_active"
          , userCreatedAt = "created_at"
          , userUpdatedAt = "updated_at"
          }
    }

-- sessTokenRotatedAt tracks when the token was last rotated, distinct from
-- sessLastSeenAt (updated every request) and sessCreatedAt (set once).
-- The middleware checks this and issues a fresh token when the threshold
-- is exceeded, limiting the damage window of a stolen cookie.
data SessionRow f = SessionRow
  { sessId :: Column f UUID
  , sessUserId :: Column f UUID
  , sessTokenHash :: Column f Text
  , sessRegisterId :: Column f (Maybe UUID)
  , sessCreatedAt :: Column f UTCTime
  , sessLastSeenAt :: Column f UTCTime
  , sessExpiresAt :: Column f UTCTime
  , sessRevoked :: Column f Bool
  , sessRevokedAt :: Column f (Maybe UTCTime)
  , sessRevokedBy :: Column f (Maybe UUID)
  , sessUserAgent :: Column f (Maybe Text)
  , sessIpAddress :: Column f (Maybe Text)
  , sessTokenRotatedAt :: Column f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance (f ~ Result) => Show (SessionRow f)

sessionSchema :: TableSchema (SessionRow Name)
sessionSchema =
  TableSchema
    { name = "sessions"
    , columns =
        SessionRow
          { sessId = "id"
          , sessUserId = "user_id"
          , sessTokenHash = "token_hash"
          , sessRegisterId = "register_id"
          , sessCreatedAt = "created_at"
          , sessLastSeenAt = "last_seen_at"
          , sessExpiresAt = "expires_at"
          , sessRevoked = "revoked"
          , sessRevokedAt = "revoked_at"
          , sessRevokedBy = "revoked_by"
          , sessUserAgent = "user_agent"
          , sessIpAddress = "ip_address"
          , sessTokenRotatedAt = "token_rotated_at"
          }
    }

data LoginAttemptRow f = LoginAttemptRow
  { attemptId :: Column f UUID
  , attemptUsername :: Column f Text
  , attemptIpAddress :: Column f Text
  , attemptSuccess :: Column f Bool
  , attemptedAt :: Column f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance (f ~ Result) => Show (LoginAttemptRow f)

loginAttemptSchema :: TableSchema (LoginAttemptRow Name)
loginAttemptSchema =
  TableSchema
    { name = "login_attempts"
    , columns =
        LoginAttemptRow
          { attemptId = "id"
          , attemptUsername = "username"
          , attemptIpAddress = "ip_address"
          , attemptSuccess = "success"
          , attemptedAt = "attempted_at"
          }
    }
