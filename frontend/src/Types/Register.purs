module Types.Register where

import Data.DateTime (DateTime)
import Data.Maybe (Maybe)
import Types.UUID (UUID)
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete)

type EntityId = UUID

type CartTotals =
  { subtotal :: Discrete USD
  , taxTotal :: Discrete USD
  , total :: Discrete USD
  , discountTotal :: Discrete USD
  }

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

-- The employee who opens or closes a register is the session user. Neither
-- request names one. Amounts are cents.

type OpenRegisterRequest =
  { openRegisterStartingCash :: Int
  }

type CloseRegisterRequest =
  { closeRegisterCountedCash :: Int
  }

type CloseRegisterResult =
  { closeRegisterResultRegister :: Register
  , closeRegisterResultVariance :: Int
  }

