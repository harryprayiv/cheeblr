{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Types.Events.Stock (
  StockEvent (..),
) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)

import State.StockPullMachine (PullVertex)
import Types.Stock (PullMessage, PullRequest)

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
