{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
-- {-# LANGUAGE OverloadedStrings #-}

module Types.Stock (
  PullRequest (..),
  PullMessage (..),
  PullRequestDetail (..),
  IssueReport (..),
  NewMessage (..),
) where

import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)

import State.StockPullMachine (PullVertex)
import Types.Location (LocationId)

data PullRequest = PullRequest
  { prId :: UUID
  , prTransactionId :: UUID
  , prItemSku :: UUID
  , prItemName :: Text
  , prQuantityNeeded :: Int
  , prStatus :: PullVertex
  , prCashierId :: Maybe UUID
  , prRegisterId :: Maybe UUID
  , prLocationId :: LocationId
  , prCreatedAt :: UTCTime
  , prUpdatedAt :: UTCTime
  , prFulfilledAt :: Maybe UTCTime
  }
  deriving (Show, Eq, Generic)

instance ToJSON PullRequest
instance FromJSON PullRequest
instance ToSchema PullRequest

data PullMessage = PullMessage
  { pmId :: UUID
  , pmPullRequestId :: UUID
  , pmFromRole :: Text
  , pmSenderId :: UUID
  , pmMessage :: Text
  , pmCreatedAt :: UTCTime
  }
  deriving (Show, Eq, Generic)

instance ToJSON PullMessage
instance FromJSON PullMessage
instance ToSchema PullMessage

data PullRequestDetail = PullRequestDetail
  { pdPullRequest :: PullRequest
  , pdMessages :: [PullMessage]
  }
  deriving (Show, Generic)

-- instance ToSchema PullRequestDetail where
--   declareNamedSchema _ = return $ NamedSchema (Just "PullRequestDetail") mempty

-- instance ToSchema IssueReport
-- instance ToSchema NewMessage

instance ToJSON PullRequestDetail
instance ToSchema PullRequestDetail

newtype IssueReport = IssueReport
  { irNote :: Text
  }
  deriving (Show, Eq, Generic)

instance ToJSON IssueReport
instance FromJSON IssueReport
instance ToSchema IssueReport

newtype NewMessage = NewMessage
  { nmMessage :: Text
  }
  deriving (Show, Eq, Generic)

instance ToJSON NewMessage
instance FromJSON NewMessage
instance ToSchema NewMessage
