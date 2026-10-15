{-# LANGUAGE KindSignatures #-}

-- The vocabulary of the model test: who acts, what they send, what the
-- model holds, and what is read back from the backend.
--
-- Registers, sales and menu items are named by slot numbers (0, 1, 2 ...)
-- and not by UUID. Model.Exec maps a slot to the UUID the backend knows.
-- A command is therefore plain data: it can be printed, replayed and
-- shrunk without knowing any id the backend generated.
module Model.Types
  ( Actor (..)
  , Status (..)
  , Method (..)
  , Cmd (..)
  , Rules (..)
  , SaleM (..)
  , RegisterM (..)
  , Model (..)
  , SaleView (..)
  , RegisterView (..)
  , StockView (..)
  , Observed (..)
  ) where

import Data.Kind (Type)
import Data.Map.Strict (Map)

-- The session a command is sent with. Anonymous sends no session cookie.
data Actor
  = Admin
  | CashierA
  | CashierB
  | Customer
  | Anonymous
  deriving (Eq, Ord, Show, Enum, Bounded)

-- Sale status. The constructor names are the strings the backend writes
-- in saleStatus.
data Status
  = Created
  | InProgress
  | Completed
  | Voided
  | Refunded
  deriving (Eq, Ord, Show)

-- Payment method. The constructor names are the strings the backend reads
-- and writes in paymentMethod.
data Method
  = Cash
  | Credit
  | Debit
  deriving (Eq, Ord, Show, Enum, Bounded)

-- One request the front end can make. Int arguments named register, sale
-- and sku are slot numbers.
data Cmd
  = CreateRegister Actor
  | OpenRegister Actor Int Int
    -- ^ register, starting cash in cents
  | CloseRegister Actor Int Int
    -- ^ register, counted cash in cents
  | StartSale Actor Int
    -- ^ register
  | AddItem Actor Int Int Int
    -- ^ sale, sku, quantity
  | RemoveItem Actor Int Int
    -- ^ sale, sku of the line to remove
  | AddPayment Actor Int Method Int (Maybe Int)
    -- ^ sale, method, amount in cents, tendered in cents
  | RemovePayment Actor Int Method Int
    -- ^ sale, method and amount of the payment to remove
  | Clear Actor Int
  | Finalize Actor Int
  | Void Actor Int
  | Refund Actor Int
  | Audit
    -- ^ sends no write; reads every sale and register back
  deriving (Eq, Show)

-- What the model has to be told about the backend it is checking.
data Rules = Rules
  { rulesTaxPpm          :: Int
    -- ^ sales tax in parts per million, rounded half up per line
  , rulesRestockOnVoid   :: Bool
  , rulesRestockOnRefund :: Bool
  , rulesPrices          :: Map Int Int
    -- ^ sku slot to unit price in cents
  , rulesStock           :: Map Int Int
    -- ^ sku slot to the stock each run starts with
  }
  deriving (Eq, Show)

data SaleM = SaleM
  { saleOwner    :: Actor
  , saleRegister :: Int
  , saleStatus   :: Status
  , saleLines    :: Map Int Int
    -- ^ sku slot to quantity; one line per sku
  , salePayments :: [(Method, Int)]
  }
  deriving (Eq, Show)

data RegisterM = RegisterM
  { registerOpen     :: Bool
  , registerExpected :: Int
  }
  deriving (Eq, Show)

-- The model state. The type parameter is required by Hedgehog's state
-- machine interface and is not used: the model holds no backend ids.
data Model (v :: Type -> Type) = Model
  { modelRegisters :: Map Int RegisterM
  , modelSales     :: Map Int SaleM
  , modelOnHand    :: Map Int Int
    -- ^ sku slot to the quantity in menu_items
  }
  deriving (Eq, Show)

-- A sale as the backend reports it, translated to slots. An owner,
-- register or sku the run does not know becomes Nothing or slot -1, which
-- never equals what the model expects.
data SaleView = SaleView
  { viewOwner     :: Maybe Actor
  , viewRegister  :: Maybe Int
  , viewStatus    :: String
  , viewLines     :: Map Int Int
  , viewPayments  :: [(String, Int)]
    -- ^ sorted, so that order does not matter
  , viewSubtotal  :: Int
  , viewTax       :: Int
  , viewTotal     :: Int
  , viewLineTotal :: Int
    -- ^ the sum of the lines' own totals
  }
  deriving (Eq, Show)

data RegisterView = RegisterView
  { viewOpen     :: Bool
  , viewExpected :: Int
  }
  deriving (Eq, Show)

data StockView = StockView
  { stockOnHand   :: Int
  , stockReserved :: Int
  }
  deriving (Eq, Show)

-- Everything read from the backend for one command: the answer to the
-- command itself, then the state read back afterwards with the admin
-- session.
data Observed = Observed
  { obsStatus       :: Int
  , obsBody         :: String
    -- ^ the start of the response body, for the failure report
  , obsBodySale     :: Maybe SaleView
    -- ^ the sale in the response body, for commands that answer with one
  , obsSale         :: Maybe SaleView
    -- ^ the sale the command named, read back afterwards
  , obsRegister     :: Maybe RegisterView
    -- ^ the register the command named, read back afterwards
  , obsVariance     :: Maybe Int
  , obsStock        :: Map Int StockView
    -- ^ read after every command
  , obsAllSales     :: Maybe (Map Int SaleView)
  , obsAllRegisters :: Maybe (Map Int RegisterView)
    -- ^ both filled only by Audit
  }
  deriving (Eq, Show)
