{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

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

-- The sale's opener is the session user. The request does not name an
-- employee.
data StartSaleRequest = StartSaleRequest
  { startSaleRegisterId :: UUID
  , startSaleLocationId :: LocationId
  }
  deriving stock (Show, Eq, Generic)

instance ToJSON StartSaleRequest
instance FromJSON StartSaleRequest
instance ToSchema StartSaleRequest

data AddItemRequest = AddItemRequest
  { addItemSaleId   :: UUID
  , addItemSku      :: UUID
  , addItemQuantity :: Int
  }
  deriving stock (Show, Eq, Generic)

instance ToJSON AddItemRequest
instance FromJSON AddItemRequest
instance ToSchema AddItemRequest

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
