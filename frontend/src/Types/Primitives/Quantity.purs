-- FILE: ./frontend/src/Types/Primitives/Quantity.purs
module Types.Primitives.Quantity
  ( SaleQuantity
  , RefundQuantity
  , mkSaleQuantity
  , unsafeMkSaleQuantity
  , saleQuantityCount
  , zeroSaleQuantity
  , oneSaleQuantity
  , addSaleQuantity
  , subtractSaleQuantity
  , sumSaleQuantity
  , mkRefundQuantity
  , unsafeMkRefundQuantity
  , refundQuantityCount
  , zeroRefundQuantity
  , addRefundQuantity
  , subtractRefundQuantity
  , sumRefundQuantity
  , toRefundQuantity
  , toSaleQuantity
  ) where

import Prelude

import Data.Foldable (class Foldable, foldl)
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, unwrap)
import Foreign (ForeignError(..), fail)
import Yoga.JSON (class ReadForeign, class WriteForeign, readImpl, writeImpl)

newtype SaleQuantity = SaleQuantity Int

derive instance newtypeSaleQuantity :: Newtype SaleQuantity _
derive newtype instance eqSaleQuantity :: Eq SaleQuantity
derive newtype instance ordSaleQuantity :: Ord SaleQuantity

instance showSaleQuantity :: Show SaleQuantity where
  show (SaleQuantity n) = "SaleQuantity " <> show n

instance writeForeignSaleQuantity :: WriteForeign SaleQuantity where
  writeImpl (SaleQuantity n) = writeImpl n

instance readForeignSaleQuantity :: ReadForeign SaleQuantity where
  readImpl f = do
    n <- readImpl f
    case mkSaleQuantity n of
      Just q -> pure q
      Nothing -> fail
        ( ForeignError $
            "SaleQuantity requires non-negative count, got: " <> show n
        )

mkSaleQuantity :: Int -> Maybe SaleQuantity
mkSaleQuantity n
  | n >= 0 = Just (SaleQuantity n)
  | otherwise = Nothing

unsafeMkSaleQuantity :: Int -> SaleQuantity
unsafeMkSaleQuantity = SaleQuantity

saleQuantityCount :: SaleQuantity -> Int
saleQuantityCount = unwrap

zeroSaleQuantity :: SaleQuantity
zeroSaleQuantity = SaleQuantity 0

oneSaleQuantity :: SaleQuantity
oneSaleQuantity = SaleQuantity 1

addSaleQuantity :: SaleQuantity -> SaleQuantity -> SaleQuantity
addSaleQuantity (SaleQuantity a) (SaleQuantity b) = SaleQuantity (a + b)

subtractSaleQuantity :: SaleQuantity -> SaleQuantity -> Maybe SaleQuantity
subtractSaleQuantity (SaleQuantity a) (SaleQuantity b) = mkSaleQuantity (a - b)

sumSaleQuantity :: forall f. Foldable f => f SaleQuantity -> SaleQuantity
sumSaleQuantity = foldl addSaleQuantity zeroSaleQuantity

newtype RefundQuantity = RefundQuantity Int

derive instance newtypeRefundQuantity :: Newtype RefundQuantity _
derive newtype instance eqRefundQuantity :: Eq RefundQuantity
derive newtype instance ordRefundQuantity :: Ord RefundQuantity

instance showRefundQuantity :: Show RefundQuantity where
  show (RefundQuantity n) = "RefundQuantity " <> show n

instance writeForeignRefundQuantity :: WriteForeign RefundQuantity where
  writeImpl (RefundQuantity n) = writeImpl n

instance readForeignRefundQuantity :: ReadForeign RefundQuantity where
  readImpl f = do
    n <- readImpl f
    case mkRefundQuantity n of
      Just q -> pure q
      Nothing -> fail
        ( ForeignError $
            "RefundQuantity requires non-positive count, got: " <> show n
        )

mkRefundQuantity :: Int -> Maybe RefundQuantity
mkRefundQuantity n
  | n <= 0 = Just (RefundQuantity n)
  | otherwise = Nothing

unsafeMkRefundQuantity :: Int -> RefundQuantity
unsafeMkRefundQuantity = RefundQuantity

refundQuantityCount :: RefundQuantity -> Int
refundQuantityCount = unwrap

zeroRefundQuantity :: RefundQuantity
zeroRefundQuantity = RefundQuantity 0

addRefundQuantity :: RefundQuantity -> RefundQuantity -> RefundQuantity
addRefundQuantity (RefundQuantity a) (RefundQuantity b) =
  RefundQuantity (a + b)

subtractRefundQuantity
  :: RefundQuantity -> RefundQuantity -> Maybe RefundQuantity
subtractRefundQuantity (RefundQuantity a) (RefundQuantity b) =
  mkRefundQuantity (a - b)

sumRefundQuantity :: forall f. Foldable f => f RefundQuantity -> RefundQuantity
sumRefundQuantity = foldl addRefundQuantity zeroRefundQuantity

toRefundQuantity :: SaleQuantity -> RefundQuantity
toRefundQuantity (SaleQuantity n) = RefundQuantity (negate n)

toSaleQuantity :: RefundQuantity -> SaleQuantity
toSaleQuantity (RefundQuantity n) = SaleQuantity (negate n)