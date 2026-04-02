{-# LANGUAGE DeriveGeneric #-}

module Types.Events.Availability
  ( AvailabilityUpdate (..)
  ) where

import Data.Aeson   (FromJSON, ToJSON)
import Data.Time    (UTCTime)
import GHC.Generics (Generic)

import Types.Public.AvailableItem (AvailableItem)

data AvailabilityUpdate = AvailabilityUpdate
  { auItem      :: AvailableItem
  , auTimestamp :: UTCTime
  } deriving (Show, Eq, Generic)

instance ToJSON   AvailabilityUpdate
instance FromJSON AvailabilityUpdate