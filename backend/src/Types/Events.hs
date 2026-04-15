{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}

{- | All domain event payload types in one place.
Types.Events.Log and Types.Events.Availability stay separate
(different concerns, different consumers).
-}
module Types.Events (
  -- Inventory
  InventoryEvent (..),
  QuantityChangeReason (..),
  -- Register
  RegisterEvent (..),
  -- Session
  SessionEvent (..),
  -- Stock
  StockEvent (..),
  -- Transaction
  TransactionEvent (..),
) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)

import State.StockPullMachine (PullVertex)
import Types.Auth (UserRole)
import Types.Inventory (MenuItem)
import Types.Stock (PullMessage, PullRequest)
import Types.Transaction (PaymentTransaction, Transaction, TransactionItem)

-- ---------------------------------------------------------------------------
-- Inventory events
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Register events
-- ---------------------------------------------------------------------------

data RegisterEvent
  = RegisterOpened
      { reRegId :: UUID
      , reEmpId :: UUID
      , reStartingCash :: Int
      , reTimestamp :: UTCTime
      }
  | RegisterClosed
      { reRegId :: UUID
      , reEmpId :: UUID
      , reCountedCash :: Int
      , reVariance :: Int
      , reTimestamp :: UTCTime
      }
  deriving (Show, Eq, Generic)

instance ToJSON RegisterEvent
instance FromJSON RegisterEvent

-- ---------------------------------------------------------------------------
-- Session events
-- ---------------------------------------------------------------------------

data SessionEvent
  = SessionCreated
      { sesUserId :: UUID
      , sesRole :: UserRole
      , sesTimestamp :: UTCTime
      }
  | SessionExpired
      { sesUserId :: UUID
      , sesTimestamp :: UTCTime
      }
  | SessionRevoked
      { sesUserId :: UUID
      , sesActorId :: UUID
      , sesTimestamp :: UTCTime
      }
  deriving (Show, Eq, Generic)

instance ToJSON SessionEvent
instance FromJSON SessionEvent

-- ---------------------------------------------------------------------------
-- Stock events
-- ---------------------------------------------------------------------------

data StockEvent
  = PullRequestCreated
      { sePull :: PullRequest
      , seTimestamp :: UTCTime
      }
  | PullStatusChanged
      { sePullId :: UUID
      , seOldStatus :: PullVertex
      , seNewStatus :: PullVertex
      , seActorId :: UUID
      , seTimestamp :: UTCTime
      }
  | PullMessageAdded
      { sePullId :: UUID
      , seMessage :: PullMessage
      , seTimestamp :: UTCTime
      }
  | PullRequestCancelled
      { sePullId :: UUID
      , seReason :: Text
      , seTimestamp :: UTCTime
      }
  deriving (Show, Eq, Generic)

instance ToJSON StockEvent
instance FromJSON StockEvent

-- ---------------------------------------------------------------------------
-- Transaction events
-- ---------------------------------------------------------------------------

data TransactionEvent
  = TransactionCreated
      { teTx :: Transaction
      , teTimestamp :: UTCTime
      }
  | TransactionItemAdded
      { teTxId :: UUID
      , teItem :: TransactionItem
      , teTimestamp :: UTCTime
      }
  | TransactionItemRemoved
      { teTxId :: UUID
      , teItemId :: UUID
      , teItemSku :: UUID
      , teQty :: Int
      , teTimestamp :: UTCTime
      }
  | TransactionPaymentAdded
      { teTxId :: UUID
      , tePayment :: PaymentTransaction
      , teTimestamp :: UTCTime
      }
  | TransactionPaymentRemoved
      { teTxId :: UUID
      , tePaymentId :: UUID
      , teTimestamp :: UTCTime
      }
  | TransactionFinalized
      { teTxId :: UUID
      , teTx :: Transaction
      , teTimestamp :: UTCTime
      }
  | TransactionVoided
      { teTxId :: UUID
      , teReason :: Text
      , teActorId :: UUID
      , teTimestamp :: UTCTime
      }
  | TransactionRefunded
      { teTxId :: UUID
      , teReason :: Text
      , teActorId :: UUID
      , teRefTxId :: UUID
      , teTimestamp :: UTCTime
      }
  deriving (Show, Eq, Generic)

instance ToJSON TransactionEvent
instance FromJSON TransactionEvent
