{-# LANGUAGE OverloadedStrings #-}

-- | What happens to stock when a completed sale is voided or refunded.
--
-- Completing a sale takes its quantities out of stock. Whether a later void
-- or refund puts them back depends on the business: some goods can go back
-- on the shelf and some cannot. The backend can do either. Which one it
-- does is set in configuration, once for void and once for refund, and
-- there is no default: "Config.App" refuses to start without both.
--
-- Voiding a sale that was never completed is not covered by this setting.
-- Such a sale only holds reservations, and those are always released.
module Domain.StockPolicy (
  RestockPolicy (..),
  StockPolicy (..),
  parseRestockPolicy,
  restockPolicyText,
) where

import Data.Text (Text)
import qualified Data.Text as T

-- | 'ReturnToStock' adds every line's quantity back to its item's stock.
-- 'DoNotRestock' leaves stock as it is.
data RestockPolicy
  = ReturnToStock
  | DoNotRestock
  deriving (Show, Eq)

-- | 'restockOnVoid' applies when a COMPLETED sale is voided.
-- 'restockOnRefund' applies when a COMPLETED sale is refunded.
data StockPolicy = StockPolicy
  { restockOnVoid   :: RestockPolicy
  , restockOnRefund :: RestockPolicy
  }
  deriving (Show, Eq)

-- | Reads a configured value. The two accepted values are @restock@ and
-- @no-restock@. Case and surrounding spaces are ignored. Anything else is
-- an error that names the value it was given.
parseRestockPolicy :: Text -> Either Text RestockPolicy
parseRestockPolicy raw =
  case T.toLower (T.strip raw) of
    "restock"    -> Right ReturnToStock
    "no-restock" -> Right DoNotRestock
    _            ->
      Left ("expected \"restock\" or \"no-restock\", got \"" <> raw <> "\"")

-- | The configured spelling of a policy.
restockPolicyText :: RestockPolicy -> Text
restockPolicyText ReturnToStock = "restock"
restockPolicyText DoNotRestock  = "no-restock"