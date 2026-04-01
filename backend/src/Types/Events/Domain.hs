{-# LANGUAGE DeriveGeneric #-}

-- Stub. Phase 2 replaces DomainEventPlaceholder with the full
-- InventoryEvent / TransactionEvent / RegisterEvent / SessionEvent tree.
module Types.Events.Domain
  ( DomainEvent (..)
  ) where

import Data.Aeson   (FromJSON, ToJSON)
import GHC.Generics (Generic)

data DomainEvent = DomainEventPlaceholder
  deriving (Show, Eq, Generic)

instance ToJSON   DomainEvent
instance FromJSON DomainEvent