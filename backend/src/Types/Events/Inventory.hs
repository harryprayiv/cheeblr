{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Types.Events.Inventory (
  InventoryEvent (..),
  QuantityChangeReason (..),
) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import Types.Inventory (MenuItem)

data InventoryEvent
  = ItemCreated
      { ieItem :: MenuItem
      , ieTimestamp :: UTCTime
      , ieActorId :: UUID
      }
  | ItemUpdated
      { ieOldItem :: MenuItem
      , ieNewItem :: MenuItem
      , ieTimestamp :: UTCTime
      , ieActorId :: UUID
      }
  | ItemDeleted
      { ieSku :: UUID
      , ieItemName :: Text
      , ieTimestamp :: UTCTime
      , ieActorId :: UUID
      }
  | QuantityChanged
      { ieItemSku :: UUID
      , ieOldQty :: Int
      , ieNewQty :: Int
      , ieReservedDelta :: Int
      , ieReason :: QuantityChangeReason
      , ieTimestamp :: UTCTime
      }
  deriving (Show, Eq, Generic)

instance ToJSON InventoryEvent
instance FromJSON InventoryEvent

data QuantityChangeReason
  = ReservedForTransaction UUID
  | ReleasedFromTransaction UUID
  | SaleCompleted UUID
  | RefundProcessed UUID
  | ManualAdjustment Text
  deriving (Show, Eq, Generic)

instance ToJSON QuantityChangeReason
instance FromJSON QuantityChangeReason
