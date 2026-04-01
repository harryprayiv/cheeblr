{-# LANGUAGE DeriveGeneric #-}

-- Stub. Phase 5 replaces AvailabilityUpdatePlaceholder with:
--   data AvailabilityUpdate = AvailabilityUpdate
--     { auItem :: AvailableItem, auTimestamp :: UTCTime }
module Types.Events.Availability
  ( AvailabilityUpdate (..)
  ) where

import Data.Aeson   (FromJSON, ToJSON)
import GHC.Generics (Generic)

data AvailabilityUpdate = AvailabilityUpdatePlaceholder
  deriving (Show, Eq, Generic)

instance ToJSON   AvailabilityUpdate
instance FromJSON AvailabilityUpdate