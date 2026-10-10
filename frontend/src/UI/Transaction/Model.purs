module UI.Transaction.Model
  ( Activity(..)
  , isBusy
  , activityLabel
  , Filters
  , Totals
  , categoriesIn
  , visibleItems
  , quantityInCart
  , availableToAdd
  , addBlocker
  , totals
  , paidCents
  , remainingCents
  , isOpen
  , canResume
  , voidable
  , refundable
  , finalizeBlockers
  ) where

import Prelude

import Data.Array (filter, nub, null, sort)
import Data.Foldable (sum)
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), contains, toLower, trim)
import Types.Inventory (Inventory(..), ItemCategory, MenuItem(..))
import Types.Primitives.Money (SaleMoney, saleMoneyCents)
import Types.Primitives.Quantity (SaleQuantity, saleQuantityCount)
import Types.Transaction (TransactionStatus(..))
import Types.UUID (UUID)
import Utils.Formatting (formatCentsToDollars)

data Activity
  = Idle
  | AddingItem
  | RemovingItem
  | AddingPayment
  | RemovingPayment
  | Clearing
  | Finalizing
  | StartingSale

derive instance Eq Activity

isBusy :: Activity -> Boolean
isBusy = (_ /= Idle)

activityLabel :: Activity -> String
activityLabel = case _ of
  Idle -> ""
  AddingItem -> "Adding item..."
  RemovingItem -> "Removing item..."
  AddingPayment -> "Adding payment..."
  RemovingPayment -> "Removing payment..."
  Clearing -> "Clearing cart..."
  Finalizing -> "Finalizing transaction..."
  StartingSale -> "Starting a new sale..."

type Filters =
  { search :: String
  , category :: Maybe ItemCategory
  }

type Totals =
  { subtotal :: Int
  , discount :: Int
  , tax :: Int
  , total :: Int
  }

categoriesIn :: Inventory -> Array ItemCategory
categoriesIn (Inventory items) =
  sort (nub (items <#> \(MenuItem i) -> i.category))

visibleItems :: Filters -> Inventory -> Array MenuItem
visibleItems filters (Inventory items) =
  filter (\item -> inCategory item && matchesSearch item) items
  where
  needle = toLower (trim filters.search)

  inCategory (MenuItem i) = case filters.category of
    Nothing -> true
    Just c -> i.category == c

  matchesSearch (MenuItem i) =
    needle == "" || contains (Pattern needle) (toLower i.name)

quantityInCart
  :: forall r
   . UUID
  -> Array { itemMenuItemSku :: UUID, itemQuantity :: SaleQuantity | r }
  -> Int
quantityInCart sku items =
  sum
    ( items
        # filter (\i -> i.itemMenuItemSku == sku)
        # map (\i -> saleQuantityCount i.itemQuantity)
    )

availableToAdd :: MenuItem -> Int
availableToAdd (MenuItem i) = max 0 i.quantity

addBlocker :: Int -> MenuItem -> Maybe String
addBlocker requested item =
  let
    available = availableToAdd item
  in
    if requested <= 0 then Just "Quantity must be greater than 0"
    else if available <= 0 then Just "Out of stock"
    else if requested > available then
      Just ("Only " <> show available <> " available")
    else Nothing

totals
  :: forall r
   . { saleSubtotal :: SaleMoney
     , saleDiscountTotal :: SaleMoney
     , saleTaxTotal :: SaleMoney
     , saleTotal :: SaleMoney
     | r
     }
  -> Totals
totals sale =
  { subtotal: saleMoneyCents sale.saleSubtotal
  , discount: saleMoneyCents sale.saleDiscountTotal
  , tax: saleMoneyCents sale.saleTaxTotal
  , total: saleMoneyCents sale.saleTotal
  }

paidCents :: forall r. Array { paymentAmount :: SaleMoney | r } -> Int
paidCents payments = sum (payments <#> \p -> saleMoneyCents p.paymentAmount)

remainingCents
  :: forall r rp
   . { saleTotal :: SaleMoney
     , salePayments :: Array { paymentAmount :: SaleMoney | rp }
     | r
     }
  -> Int
remainingCents sale =
  max 0 (saleMoneyCents sale.saleTotal - paidCents sale.salePayments)

isOpen :: TransactionStatus -> Boolean
isOpen = case _ of
  Created -> true
  InProgress -> true
  Completed -> false
  Voided -> false
  Refunded -> false

-- Whether the sale page may continue a sale it finds remembered in the
-- browser: the sale is still open, this user opened it, and it was opened on
-- the register this browser now sells on. The backend enforces the first
-- two on every write (409 and 403).
canResume
  :: forall r
   . UUID
  -> UUID
  -> { saleStatus :: TransactionStatus
     , saleEmployeeId :: UUID
     , saleRegisterId :: UUID
     | r
     }
  -> Boolean
canResume userId registerId sale =
  isOpen sale.saleStatus
    && sale.saleEmployeeId == userId
    && sale.saleRegisterId == registerId

-- The backend voids a sale that is open or completed. It refuses (409) a
-- sale that is already voided or was refunded.
voidable :: TransactionStatus -> Boolean
voidable = case _ of
  Created -> true
  InProgress -> true
  Completed -> true
  Voided -> false
  Refunded -> false

-- The backend refunds a completed sale, once. Every other status is
-- refused (409).
refundable :: TransactionStatus -> Boolean
refundable = (_ == Completed)

finalizeBlockers
  :: forall r ri rp
   . { saleStatus :: TransactionStatus
     , saleItems :: Array { | ri }
     , salePayments :: Array { paymentAmount :: SaleMoney | rp }
     , saleTotal :: SaleMoney
     | r
     }
  -> Array String
finalizeBlockers sale =
  if not (isOpen sale.saleStatus) then [ closedReason sale.saleStatus ]
  else noItems <> shortPayment
  where
  closedReason = case _ of
    Completed -> "Transaction is already completed"
    Voided -> "Transaction has been voided"
    Refunded -> "Transaction has been refunded"
    _ -> "Transaction is closed"

  noItems =
    if null sale.saleItems then [ "No items in transaction" ] else []

  remaining = remainingCents sale

  shortPayment =
    if not (null sale.saleItems) && remaining > 0 then
      [ "Payment is short by $" <> formatCentsToDollars remaining ]
    else []

