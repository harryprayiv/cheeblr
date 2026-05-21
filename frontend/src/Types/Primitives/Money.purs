-- FILE: ./frontend/src/Types/Primitives/Money.purs
module Types.Primitives.Money
  ( SaleMoney
  , RefundMoney
  , mkSaleMoney
  , unsafeMkSaleMoney
  , saleMoneyCents
  , saleMoneyDiscrete
  , zeroSale
  , addSale
  , subtractSale
  , scaleSale
  , sumSale
  , mkRefundMoney
  , unsafeMkRefundMoney
  , refundMoneyCents
  , refundMoneyDiscrete
  , zeroRefund
  , addRefund
  , scaleRefund
  , sumRefund
  , negateToRefund
  , negateFromRefund
  , discreteToSaleMoney
  ) where

import Prelude

import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Foldable (class Foldable, foldl)
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, unwrap)
import Foreign (ForeignError(..), fail)
import Yoga.JSON (class ReadForeign, class WriteForeign, readImpl, writeImpl)

-- | Non-negative monetary amount. Wraps 'Discrete USD' for currency-typed
-- | arithmetic and formatting; serialises as a bare integer (cents) on the
-- | wire to match the backend's 'SaleMoney' newtype around 'Int'.
newtype SaleMoney = SaleMoney (Discrete USD)

derive instance newtypeSaleMoney :: Newtype SaleMoney _
derive newtype instance eqSaleMoney :: Eq SaleMoney
derive newtype instance ordSaleMoney :: Ord SaleMoney

instance showSaleMoney :: Show SaleMoney where
  show (SaleMoney (Discrete n)) = "SaleMoney " <> show n

instance writeForeignSaleMoney :: WriteForeign SaleMoney where
  writeImpl (SaleMoney (Discrete n)) = writeImpl n

instance readForeignSaleMoney :: ReadForeign SaleMoney where
  readImpl f = do
    n <- readImpl f
    case mkSaleMoney n of
      Just m -> pure m
      Nothing -> fail
        ( ForeignError $
            "SaleMoney requires non-negative cents, got: " <> show n
        )

mkSaleMoney :: Int -> Maybe SaleMoney
mkSaleMoney n
  | n >= 0 = Just (SaleMoney (Discrete n))
  | otherwise = Nothing

-- | Trusted-call-site escape hatch (test fixtures, internal conversions).
-- | Do not use in handler code; prefer 'mkSaleMoney'.
unsafeMkSaleMoney :: Int -> SaleMoney
unsafeMkSaleMoney = SaleMoney <<< Discrete

-- | Currency-typed view for arithmetic and formatting via 'Data.Finance.Money'.
saleMoneyDiscrete :: SaleMoney -> Discrete USD
saleMoneyDiscrete (SaleMoney d) = d

saleMoneyCents :: SaleMoney -> Int
saleMoneyCents (SaleMoney d) = unwrap d

zeroSale :: SaleMoney
zeroSale = SaleMoney (Discrete 0)

addSale :: SaleMoney -> SaleMoney -> SaleMoney
addSale (SaleMoney (Discrete a)) (SaleMoney (Discrete b)) =
  SaleMoney (Discrete (a + b))

-- | Underflow into negative returns 'Nothing'.
subtractSale :: SaleMoney -> SaleMoney -> Maybe SaleMoney
subtractSale (SaleMoney (Discrete a)) (SaleMoney (Discrete b)) =
  mkSaleMoney (a - b)

-- | Negative scalar returns 'Nothing'.
scaleSale :: SaleMoney -> Int -> Maybe SaleMoney
scaleSale (SaleMoney (Discrete a)) n = mkSaleMoney (a * n)

sumSale :: forall f. Foldable f => f SaleMoney -> SaleMoney
sumSale = foldl addSale zeroSale

-- | Non-positive monetary amount. Same shape as 'SaleMoney' but enforces the
-- | opposite sign invariant.
newtype RefundMoney = RefundMoney (Discrete USD)

derive instance newtypeRefundMoney :: Newtype RefundMoney _
derive newtype instance eqRefundMoney :: Eq RefundMoney
derive newtype instance ordRefundMoney :: Ord RefundMoney

instance showRefundMoney :: Show RefundMoney where
  show (RefundMoney (Discrete n)) = "RefundMoney " <> show n

instance writeForeignRefundMoney :: WriteForeign RefundMoney where
  writeImpl (RefundMoney (Discrete n)) = writeImpl n

instance readForeignRefundMoney :: ReadForeign RefundMoney where
  readImpl f = do
    n <- readImpl f
    case mkRefundMoney n of
      Just m -> pure m
      Nothing -> fail
        ( ForeignError $
            "RefundMoney requires non-positive cents, got: " <> show n
        )

mkRefundMoney :: Int -> Maybe RefundMoney
mkRefundMoney n
  | n <= 0 = Just (RefundMoney (Discrete n))
  | otherwise = Nothing

unsafeMkRefundMoney :: Int -> RefundMoney
unsafeMkRefundMoney = RefundMoney <<< Discrete

refundMoneyDiscrete :: RefundMoney -> Discrete USD
refundMoneyDiscrete (RefundMoney d) = d

refundMoneyCents :: RefundMoney -> Int
refundMoneyCents (RefundMoney d) = unwrap d

zeroRefund :: RefundMoney
zeroRefund = RefundMoney (Discrete 0)

addRefund :: RefundMoney -> RefundMoney -> RefundMoney
addRefund (RefundMoney (Discrete a)) (RefundMoney (Discrete b)) =
  RefundMoney (Discrete (a + b))

scaleRefund :: RefundMoney -> Int -> Maybe RefundMoney
scaleRefund (RefundMoney (Discrete a)) n = mkRefundMoney (a * n)

sumRefund :: forall f. Foldable f => f RefundMoney -> RefundMoney
sumRefund = foldl addRefund zeroRefund

negateToRefund :: SaleMoney -> RefundMoney
negateToRefund (SaleMoney (Discrete n)) = RefundMoney (Discrete (negate n))

negateFromRefund :: RefundMoney -> SaleMoney
negateFromRefund (RefundMoney (Discrete n)) = SaleMoney (Discrete (negate n))

discreteToSaleMoney :: Discrete USD -> Maybe SaleMoney
discreteToSaleMoney (Discrete n) = mkSaleMoney n