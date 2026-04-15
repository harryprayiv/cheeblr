{-# LANGUAGE DeriveGeneric #-}

module Types.Events.Domain (
  DomainEvent (..),
) where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

import Types.Events

data DomainEvent
  = InventoryEvt InventoryEvent
  | TransactionEvt TransactionEvent
  | RegisterEvt RegisterEvent
  | SessionEvt SessionEvent
  | StockEvt StockEvent
  deriving (Show, Eq, Generic)

instance ToJSON DomainEvent
instance FromJSON DomainEvent
