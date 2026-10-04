{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The pure rules for taking a payment and for completing a sale. All
-- amounts are integer cents.
module Domain.SaleRules
  ( PaymentError (..)
  , paymentErrorText
  , changeDue
  , finalizeProblems
  , formatCents
  ) where

import Data.Text (Text)
import qualified Data.Text as T

data PaymentError
  = NonPositiveAmount Int
  | TenderedBelowAmount Int Int
  -- ^ amount, then tendered
  deriving stock (Eq, Show)

paymentErrorText :: PaymentError -> Text
paymentErrorText (NonPositiveAmount amount) =
  "Payment amount must be greater than zero, got " <> formatCents amount
paymentErrorText (TenderedBelowAmount amount tendered) =
  "Tendered " <> formatCents tendered <> " is less than the payment amount " <> formatCents amount

-- | The change owed for a payment of an amount when the customer hands over
-- the tendered sum.
changeDue
  :: Int
  -- ^ payment amount
  -> Int
  -- ^ tendered
  -> Either PaymentError Int
changeDue amount tendered
  | amount <= 0       = Left (NonPositiveAmount amount)
  | tendered < amount = Left (TenderedBelowAmount amount tendered)
  | otherwise         = Right (tendered - amount)

-- | Every reason a sale cannot be completed. An empty list means it can.
finalizeProblems
  :: Int
  -- ^ number of items on the sale
  -> Int
  -- ^ sale total
  -> Int
  -- ^ sum of payments
  -> [Text]
finalizeProblems itemCount total paid = noItems <> short
  where
    noItems
      | itemCount <= 0 = ["No items in transaction"]
      | otherwise      = []
    short
      | itemCount > 0 && paid < total =
          ["Payment is short by " <> formatCents (total - paid)]
      | otherwise = []

-- | Cents as dollars, for messages: 1999 is "$19.99", -5 is "-$0.05".
formatCents :: Int -> Text
formatCents cents
  | cents < 0 = "-" <> formatCents (negate cents)
  | otherwise =
      let (dollars, rest) = cents `quotRem` 100
          pad             = if rest < 10 then "0" else ""
       in "$" <> T.pack (show dollars) <> "." <> pad <> T.pack (show rest)
