module Cheeblr.Core.Register where

import Prelude

import Data.Maybe (Maybe(..))
import Types.UUID (UUID)

----------------------------------------------------------------------
-- Register record (matches backend JSON shape)
----------------------------------------------------------------------

type Register =
  { registerId :: UUID
  , registerName :: String
  , registerLocationId :: UUID
  , registerIsOpen :: Boolean
  , registerCurrentDrawerAmount :: Int
  , registerExpectedDrawerAmount :: Int
  , registerOpenedAt :: Maybe String
  , registerOpenedBy :: Maybe UUID
  , registerLastTransactionTime :: Maybe String
  }

----------------------------------------------------------------------
-- API request / response types
----------------------------------------------------------------------

type OpenRegisterRequest =
  { openRegisterEmployeeId :: UUID
  , openRegisterStartingCash :: Int
  }

type CloseRegisterRequest =
  { closeRegisterEmployeeId :: UUID
  , closeRegisterCountedCash :: Int
  }

type CloseRegisterResult =
  { closeRegisterResultVariance :: Int
  }

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

emptyRegister :: UUID -> UUID -> Register
emptyRegister registerId locationId =
  { registerId
  , registerName: "Register " <> show registerId
  , registerLocationId: locationId
  , registerIsOpen: false
  , registerCurrentDrawerAmount: 0
  , registerExpectedDrawerAmount: 0
  , registerOpenedAt: Nothing
  , registerOpenedBy: Nothing
  , registerLastTransactionTime: Nothing
  }

formatDrawerAmount :: Int -> String
formatDrawerAmount cents =
  let
    dollars = show (cents / 100)
    rem = cents `mod` 100
    pad = if rem < 10 then "0" else ""
  in
    "$" <> dollars <> "." <> pad <> show rem