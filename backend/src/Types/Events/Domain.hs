{-# LANGUAGE DeriveGeneric #-}

module Types.Events.Domain
  ( DomainEvent (..)
  ) where

import Data.Aeson                (FromJSON, ToJSON)
import GHC.Generics              (Generic)
import Types.Events.Inventory    (InventoryEvent)
import Types.Events.Register     (RegisterEvent)
import Types.Events.Session      (SessionEvent)
import Types.Events.Transaction  (TransactionEvent)

data DomainEvent
  = InventoryEvt   InventoryEvent
  | TransactionEvt TransactionEvent
  | RegisterEvt    RegisterEvent
  | SessionEvt     SessionEvent
  deriving (Show, Eq, Generic)

instance ToJSON   DomainEvent
instance FromJSON DomainEvent