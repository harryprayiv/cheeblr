{-# LANGUAGE DeriveGeneric #-}

-- Stub. Phase 8 replaces StockEventPlaceholder with the
-- PullRequestCreated / PullStatusChanged / PullMessageAdded tree.
module Types.Events.Stock
  ( StockEvent (..)
  ) where

import Data.Aeson   (FromJSON, ToJSON)
import GHC.Generics (Generic)

data StockEvent = StockEventPlaceholder
  deriving (Show, Eq, Generic)

instance ToJSON   StockEvent
instance FromJSON StockEvent