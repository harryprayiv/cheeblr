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

-- The pure half of the transaction screen. Nothing here touches the DOM or
-- the network. The sale itself is never edited locally: after every change
-- the screen refetches it from the backend, and these functions only read it.
-- Sale and item arguments use open record rows so the functions accept the
-- full Sale.SaleTransaction and tests can pass small records.

-- Which request, if any, is running. Buttons are disabled while it is not
-- Idle, so two requests cannot overlap.
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

-- category Nothing means every category.
type Filters =
  { search :: String
  , category :: Maybe ItemCategory
  }

-- All amounts in cents.
type Totals =
  { subtotal :: Int
  , discount :: Int
  , tax :: Int
  , total :: Int
  }

-- The categories that have at least one item, in enum order.
categoriesIn :: Inventory -> Array ItemCategory
categoriesIn (Inventory items) =
  sort (nub (items <#> \(MenuItem i) -> i.category))

-- The inventory rows to show for the current filters. Search matches the
-- item name, ignoring case and surrounding spaces.
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

-- Units of one SKU in the cart, summed across lines in case the backend
-- keeps more than one line for the same SKU.
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

-- How many more units can be added, going by the inventory the screen last
-- fetched. The backend reports each item's quantity with every open
-- reservation already subtracted, this cart's included, so nothing is
-- subtracted again here. The backend makes the real decision when the item
-- is added.
availableToAdd :: MenuItem -> Int
availableToAdd (MenuItem i) = max 0 i.quantity

-- Why an add would be refused before asking the backend, or Nothing.
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

-- Still owed, never below zero.
remainingCents
  :: forall r rp
   . { saleTotal :: SaleMoney
     , salePayments :: Array { paymentAmount :: SaleMoney | rp }
     | r
     }
  -> Int
remainingCents sale =
  max 0 (saleMoneyCents sale.saleTotal - paidCents sale.salePayments)

-- A sale that can still take items and payments.
isOpen :: TransactionStatus -> Boolean
isOpen = case _ of
  Created -> true
  InProgress -> true
  Completed -> false
  Voided -> false
  Refunded -> false

-- Every reason the sale cannot be finalized right now. An empty array means
-- the Process Payment button is enabled. The screen lists these in its
-- status panel.
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