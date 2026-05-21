{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Types.Primitives.Quantity
  (
    SaleQuantity
  , mkSaleQuantity
  , unsafeMkSaleQuantity
  , saleQuantityCount
  , zeroSaleQuantity
  , oneSaleQuantity
  , addSaleQuantity
  , subtractSaleQuantity
  , sumSaleQuantity

  , RefundQuantity
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

import Control.Lens ((&), (?~))
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.OpenApi
  ( NamedSchema (..)
  , OpenApiType (OpenApiInteger)
  , ToSchema (..)
  , description
  , format
  , minimum_
  , type_
  )

newtype SaleQuantity = SaleQuantity Int
  deriving stock (Eq, Ord, Show)

newtype RefundQuantity = RefundQuantity Int
  deriving stock (Eq, Ord, Show)

mkSaleQuantity :: Int -> Maybe SaleQuantity
mkSaleQuantity n
  | n >= 0    = Just (SaleQuantity n)
  | otherwise = Nothing

unsafeMkSaleQuantity :: Int -> SaleQuantity
unsafeMkSaleQuantity = SaleQuantity

saleQuantityCount :: SaleQuantity -> Int
saleQuantityCount (SaleQuantity n) = n

zeroSaleQuantity :: SaleQuantity
zeroSaleQuantity = SaleQuantity 0

oneSaleQuantity :: SaleQuantity
oneSaleQuantity = SaleQuantity 1

addSaleQuantity :: SaleQuantity -> SaleQuantity -> SaleQuantity
addSaleQuantity (SaleQuantity a) (SaleQuantity b) = SaleQuantity (a + b)

subtractSaleQuantity :: SaleQuantity -> SaleQuantity -> Maybe SaleQuantity
subtractSaleQuantity (SaleQuantity a) (SaleQuantity b)
  | a >= b    = Just (SaleQuantity (a - b))
  | otherwise = Nothing

sumSaleQuantity :: (Foldable f) => f SaleQuantity -> SaleQuantity
sumSaleQuantity = foldl' addSaleQuantity zeroSaleQuantity

mkRefundQuantity :: Int -> Maybe RefundQuantity
mkRefundQuantity n
  | n >= 0    = Just (RefundQuantity n)
  | otherwise = Nothing

unsafeMkRefundQuantity :: Int -> RefundQuantity
unsafeMkRefundQuantity = RefundQuantity

refundQuantityCount :: RefundQuantity -> Int
refundQuantityCount (RefundQuantity n) = n

zeroRefundQuantity :: RefundQuantity
zeroRefundQuantity = RefundQuantity 0

addRefundQuantity :: RefundQuantity -> RefundQuantity -> RefundQuantity
addRefundQuantity (RefundQuantity a) (RefundQuantity b) = RefundQuantity (a + b)

subtractRefundQuantity :: RefundQuantity -> RefundQuantity -> Maybe RefundQuantity
subtractRefundQuantity (RefundQuantity a) (RefundQuantity b)
  | a >= b    = Just (RefundQuantity (a - b))
  | otherwise = Nothing

sumRefundQuantity :: (Foldable f) => f RefundQuantity -> RefundQuantity
sumRefundQuantity = foldl' addRefundQuantity zeroRefundQuantity

toRefundQuantity :: SaleQuantity -> RefundQuantity
toRefundQuantity (SaleQuantity n) = RefundQuantity n

toSaleQuantity :: RefundQuantity -> SaleQuantity
toSaleQuantity (RefundQuantity n) = SaleQuantity n

-- ---------------------------------------------------------------------------
-- Wire format (Phase 2H-1)
-- ---------------------------------------------------------------------------
--
-- Encoding: bare non-negative integer. Both 'SaleQuantity' and
-- 'RefundQuantity' are non-negative counts; the refund-vs-sale
-- distinction is at the type level, not the sign level.
--
-- Decoding: routes through the smart constructors. Negative counts
-- fail to decode with a descriptive message.

instance ToJSON SaleQuantity where
  toJSON     = toJSON . saleQuantityCount
  toEncoding = toEncoding . saleQuantityCount

instance FromJSON SaleQuantity where
  parseJSON v = do
    n <- parseJSON v
    case mkSaleQuantity n of
      Just q  -> pure q
      Nothing -> fail $ "SaleQuantity must be >= 0, got " <> show n

instance ToSchema SaleQuantity where
  declareNamedSchema _ =
    pure $
      NamedSchema (Just "SaleQuantity") $
        mempty
          & type_       ?~ OpenApiInteger
          & format      ?~ "int32"
          & minimum_    ?~ 0
          & description ?~ "Non-negative count of units in a sale line."

instance ToJSON RefundQuantity where
  toJSON     = toJSON . refundQuantityCount
  toEncoding = toEncoding . refundQuantityCount

instance FromJSON RefundQuantity where
  parseJSON v = do
    n <- parseJSON v
    case mkRefundQuantity n of
      Just q  -> pure q
      Nothing -> fail $ "RefundQuantity must be >= 0, got " <> show n

instance ToSchema RefundQuantity where
  declareNamedSchema _ =
    pure $
      NamedSchema (Just "RefundQuantity") $
        mempty
          & type_       ?~ OpenApiInteger
          & format      ?~ "int32"
          & minimum_    ?~ 0
          & description ?~ "Non-negative count of units in a refund line."