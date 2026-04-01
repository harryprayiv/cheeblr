{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Types.Events.Transaction
  ( TransactionEvent (..)
  ) where

import Data.Aeson        (FromJSON, ToJSON)
import Data.Text         (Text)
import Data.Time         (UTCTime)
import Data.UUID         (UUID)
import GHC.Generics      (Generic)
import Types.Transaction (PaymentTransaction, Transaction, TransactionItem)

data TransactionEvent
  = TransactionCreated
      { teTx        :: Transaction
      , teTimestamp :: UTCTime
      }
  | TransactionItemAdded
      { teTxId      :: UUID
      , teItem      :: TransactionItem
      , teTimestamp :: UTCTime
      }
  | TransactionItemRemoved
      { teTxId      :: UUID
      , teItemId    :: UUID
      , teItemSku   :: UUID
      , teQty       :: Int
      , teTimestamp :: UTCTime
      }
  | TransactionPaymentAdded
      { teTxId      :: UUID
      , tePayment   :: PaymentTransaction
      , teTimestamp :: UTCTime
      }
  | TransactionPaymentRemoved
      { teTxId      :: UUID
      , tePaymentId :: UUID
      , teTimestamp :: UTCTime
      }
  | TransactionFinalized
      { teTxId      :: UUID
      , teTx        :: Transaction
      , teTimestamp :: UTCTime
      }
  | TransactionVoided
      { teTxId      :: UUID
      , teReason    :: Text
      , teActorId   :: UUID
      , teTimestamp :: UTCTime
      }
  | TransactionRefunded
      { teTxId      :: UUID
      , teReason    :: Text
      , teActorId   :: UUID
      , teRefTxId   :: UUID
      , teTimestamp :: UTCTime
      }
  deriving (Show, Eq, Generic)

instance ToJSON   TransactionEvent
instance FromJSON TransactionEvent