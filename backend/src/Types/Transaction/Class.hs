-- src/Types/Transaction/Class.hs

-- | Shared interface for sale and refund transaction aggregates.
--
-- Per the architecture decision, 'SaleTransaction' and 'RefundTransaction' are
-- distinct types with distinct field sets and distinct lifecycles. Most
-- operations on them are type-specific (state machine, item negation, totals
-- with sign invariants). A small handful of queries genuinely don't care which
-- variant they're working with; those go here. Resist the urge to grow this
-- class beyond the minimum overlap.
module Types.Transaction.Class
  ( IsTransaction (..)
  ) where

import Data.Time (UTCTime)
import Data.UUID (UUID)

import Types.Location (LocationId)

class IsTransaction t where
  txId         :: t -> UUID
  txCreatedAt  :: t -> UTCTime
  txEmployeeId :: t -> UUID
  txRegisterId :: t -> UUID
  txLocationId :: t -> LocationId