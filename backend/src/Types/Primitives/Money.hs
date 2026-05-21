{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Types.Primitives.Money
  (
    SaleMoney
  , mkSaleMoney
  , unsafeMkSaleMoney
  , saleMoneyCents
  , zeroSale
  , addSale
  , subtractSale
  , scaleSale
  , sumSale

  , RefundMoney
  , mkRefundMoney
  , unsafeMkRefundMoney
  , refundMoneyCents
  , zeroRefund
  , addRefund
  , scaleRefund
  , sumRefund

  , negateToRefund
  , negateFromRefund
  ) where

import Control.Lens ((&), (?~))
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.OpenApi
  ( NamedSchema (..)
  , OpenApiType (OpenApiInteger)
  , ToSchema (..)
  , description
  , format
  , maximum_
  , minimum_
  , type_
  )

newtype SaleMoney = SaleMoney Int
  deriving stock (Eq, Ord, Show)

newtype RefundMoney = RefundMoney Int
  deriving stock (Eq, Ord, Show)

mkSaleMoney :: Int -> Maybe SaleMoney
mkSaleMoney n
  | n >= 0    = Just (SaleMoney n)
  | otherwise = Nothing

unsafeMkSaleMoney :: Int -> SaleMoney
unsafeMkSaleMoney = SaleMoney

saleMoneyCents :: SaleMoney -> Int
saleMoneyCents (SaleMoney n) = n

zeroSale :: SaleMoney
zeroSale = SaleMoney 0

addSale :: SaleMoney -> SaleMoney -> SaleMoney
addSale (SaleMoney a) (SaleMoney b) = SaleMoney (a + b)

subtractSale :: SaleMoney -> SaleMoney -> Maybe SaleMoney
subtractSale (SaleMoney a) (SaleMoney b)
  | a >= b    = Just (SaleMoney (a - b))
  | otherwise = Nothing

scaleSale :: SaleMoney -> Int -> Maybe SaleMoney
scaleSale (SaleMoney n) k
  | k >= 0    = Just (SaleMoney (n * k))
  | otherwise = Nothing

sumSale :: (Foldable f) => f SaleMoney -> SaleMoney
sumSale = foldl' addSale zeroSale

mkRefundMoney :: Int -> Maybe RefundMoney
mkRefundMoney n
  | n <= 0    = Just (RefundMoney n)
  | otherwise = Nothing

unsafeMkRefundMoney :: Int -> RefundMoney
unsafeMkRefundMoney = RefundMoney

refundMoneyCents :: RefundMoney -> Int
refundMoneyCents (RefundMoney n) = n

zeroRefund :: RefundMoney
zeroRefund = RefundMoney 0

addRefund :: RefundMoney -> RefundMoney -> RefundMoney
addRefund (RefundMoney a) (RefundMoney b) = RefundMoney (a + b)

scaleRefund :: RefundMoney -> Int -> Maybe RefundMoney
scaleRefund (RefundMoney n) k
  | k >= 0    = Just (RefundMoney (n * k))
  | otherwise = Nothing

sumRefund :: (Foldable f) => f RefundMoney -> RefundMoney
sumRefund = foldl' addRefund zeroRefund

negateToRefund :: SaleMoney -> RefundMoney
negateToRefund (SaleMoney n) = RefundMoney (negate n)

negateFromRefund :: RefundMoney -> SaleMoney
negateFromRefund (RefundMoney n) = SaleMoney (negate n)

-- ---------------------------------------------------------------------------
-- Wire format (Phase 2H-1)
-- ---------------------------------------------------------------------------
--
-- Encoding: bare integer (cents). 'SaleMoney 1500' encodes as 1500.
--
-- Decoding: routes through 'mkSaleMoney' / 'mkRefundMoney', so the
-- newtype invariant survives the wire. Negative cents in a 'SaleMoney'
-- payload, or positive cents in a 'RefundMoney' payload, are decode
-- failures with a descriptive message, not silently-accepted bad data.
-- The 'unsafeMk*' constructors are deliberately not on the parsing
-- path.
--
-- Schema: integer with 'minimum' (SaleMoney) or 'maximum' (RefundMoney)
-- so OpenAPI tooling and any generated client code can enforce the
-- same invariant.

instance ToJSON SaleMoney where
  toJSON     = toJSON . saleMoneyCents
  toEncoding = toEncoding . saleMoneyCents

instance FromJSON SaleMoney where
  parseJSON v = do
    n <- parseJSON v
    case mkSaleMoney n of
      Just m  -> pure m
      Nothing -> fail $ "SaleMoney must be >= 0, got " <> show n

instance ToSchema SaleMoney where
  declareNamedSchema _ =
    pure $
      NamedSchema (Just "SaleMoney") $
        mempty
          & type_       ?~ OpenApiInteger
          & format      ?~ "int32"
          & minimum_    ?~ 0
          & description ?~ "Non-negative monetary amount, in cents (1 USD = 100)."

instance ToJSON RefundMoney where
  toJSON     = toJSON . refundMoneyCents
  toEncoding = toEncoding . refundMoneyCents

instance FromJSON RefundMoney where
  parseJSON v = do
    n <- parseJSON v
    case mkRefundMoney n of
      Just m  -> pure m
      Nothing -> fail $ "RefundMoney must be <= 0, got " <> show n

instance ToSchema RefundMoney where
  declareNamedSchema _ =
    pure $
      NamedSchema (Just "RefundMoney") $
        mempty
          & type_       ?~ OpenApiInteger
          & format      ?~ "int32"
          & maximum_    ?~ 0
          & description ?~ "Non-positive monetary amount, in cents (a refund total or component thereof)."