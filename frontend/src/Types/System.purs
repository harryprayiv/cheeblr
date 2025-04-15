module Types.System where

import Data.DateTime (DateTime)
import Data.Maybe (Maybe)
import Types.UUID (UUID)

type EntityId = UUID

type Register =
  { registerId :: UUID
  , registerName :: String
  , registerLocationId :: UUID
  , registerIsOpen :: Boolean
  , registerCurrentDrawerAmount :: Int
  , registerExpectedDrawerAmount :: Int
  , registerOpenedAt :: Maybe DateTime
  , registerOpenedBy :: Maybe UUID
  , registerLastTransactionTime :: Maybe DateTime
  }

-- Request model for opening a register
type OpenRegisterRequest =
  { openRegisterEmployeeId :: UUID
  , openRegisterStartingCash :: Int
  }

-- Request model for closing a register
type CloseRegisterRequest =
  { closeRegisterEmployeeId :: UUID
  , closeRegisterCountedCash :: Int
  }

-- Response when closing a register
type CloseRegisterResult =
  { closeRegisterResultRegister :: Register
  , closeRegisterResultVariance :: Int
  }