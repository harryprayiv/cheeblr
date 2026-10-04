{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

-- | What a register asks the backend to do to a sale. A request says what
-- is wanted and nothing about money the backend can work out itself: there
-- is no unit price, tax, total, change or approval flag in any of these.
-- The backend looks up the price, applies the tax rules in force, computes
-- the change and generates every id.
--
-- JSON field names are the Haskell record field names, the same convention
-- as "Types.Transaction.Sale".
module Types.Transaction.Request
  ( StartSaleRequest (..)
  , AddItemRequest (..)
  , AddPaymentRequest (..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Data.Text (Text)
import Data.UUID (UUID)
import GHC.Generics (Generic)

import Types.Location (LocationId)
import Types.Transaction (PaymentMethod)

-- | Open a new, empty sale.
data StartSaleRequest = StartSaleRequest
  { startSaleEmployeeId :: UUID
  , startSaleRegisterId :: UUID
  , startSaleLocationId :: LocationId
  }
  deriving stock (Show, Eq, Generic)

instance ToJSON StartSaleRequest
instance FromJSON StartSaleRequest
instance ToSchema StartSaleRequest

-- | Add a quantity of one menu item to a sale.
data AddItemRequest = AddItemRequest
  { addItemSaleId   :: UUID
  , addItemSku      :: UUID
  , addItemQuantity :: Int
  }
  deriving stock (Show, Eq, Generic)

instance ToJSON AddItemRequest
instance FromJSON AddItemRequest
instance ToSchema AddItemRequest

-- | Record a payment against a sale. Amounts are cents.
-- 'addPaymentTendered' is what the customer handed over; when it is absent
-- the payment is treated as exact.
data AddPaymentRequest = AddPaymentRequest
  { addPaymentSaleId    :: UUID
  , addPaymentMethod    :: PaymentMethod
  , addPaymentAmount    :: Int
  , addPaymentTendered  :: Maybe Int
  , addPaymentReference :: Maybe Text
  }
  deriving stock (Show, Eq, Generic)

instance ToJSON AddPaymentRequest
instance FromJSON AddPaymentRequest
instance ToSchema AddPaymentRequest
