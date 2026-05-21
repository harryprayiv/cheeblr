module API.Reservation
  ( AvailableInventory
  , ReservationRequest
  , InventoryReservation
  , getAvailableInventory
  , reserveInventory
  , releaseInventoryReservation
  ) where

import Prelude

import API.Request as Request
import Data.Either (Either)
import Effect.Aff (Aff)
import Services.AuthService (UserId)
import Types.UUID (UUID)

type AvailableInventory =
  { availableTotal :: Int
  , availableReserved :: Int
  , availableActual :: Int
  }

type ReservationRequest =
  { reserveItemSku :: UUID
  , reserveTransactionId :: UUID
  , reserveQuantity :: Int
  }

type InventoryReservation =
  { reservationItemSku :: UUID
  , reservationTransactionId :: UUID
  , reservationQuantity :: Int
  , reservationStatus :: String
  }

getAvailableInventory
  :: UserId -> UUID -> Aff (Either String AvailableInventory)
getAvailableInventory userId sku =
  Request.authGet userId ("/inventory/available/" <> show sku)

reserveInventory
  :: UserId
  -> ReservationRequest
  -> Aff (Either String InventoryReservation)
reserveInventory userId req =
  Request.authPost userId "/inventory/reserve" req

releaseInventoryReservation :: UserId -> UUID -> Aff (Either String Unit)
releaseInventoryReservation userId resId =
  Request.authDeleteUnit userId ("/inventory/release/" <> show resId)