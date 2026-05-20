{-# LANGUAGE OverloadedStrings #-}

module Test.Types.Primitives.MoneySpec (spec) where

import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Hspec
import Test.Hspec.Hedgehog (hedgehog)

import Types.Primitives.Money

--------------------------------------------------------------------------------
-- Generators
--
-- These are inline for now because no other test module consumes them yet.
-- When Test.Props or Test.Service tests start generating Transactions made of
-- typed Money, move these into Test.Gen alongside genTransactionItem etc.
--------------------------------------------------------------------------------

-- | A SaleMoney with cents in [0, 1_000_000]. The ceiling is well below
-- the realistic POS line-item bound; far below where Int overflow becomes
-- a concern. Adjust if a property needs a wider sweep.
genSaleMoney :: Gen SaleMoney
genSaleMoney = do
  n <- Gen.int (Range.linear 0 1000000)
  case mkSaleMoney n of
    Just s  -> pure s
    Nothing -> error "genSaleMoney: invariant violated"

genRefundMoney :: Gen RefundMoney
genRefundMoney = do
  n <- Gen.int (Range.linear (-1000000) 0)
  case mkRefundMoney n of
    Just r  -> pure r
    Nothing -> error "genRefundMoney: invariant violated"

genScalar :: Gen Int
genScalar = Gen.int (Range.linear 0 1000)

--------------------------------------------------------------------------------
-- Spec
--------------------------------------------------------------------------------

spec :: Spec
spec = describe "Types.Primitives.Money" $ do

  describe "SaleMoney construction" $ do
    it "rejects negative input" $ hedgehog $ do
      n <- forAll $ Gen.int (Range.linear (-1000000) (-1))
      mkSaleMoney n === Nothing

    it "accepts non-negative input and round-trips through saleMoneyCents" $ hedgehog $ do
      n <- forAll $ Gen.int (Range.linear 0 1000000)
      fmap saleMoneyCents (mkSaleMoney n) === Just n

  describe "SaleMoney addition" $ do
    it "zeroSale is the left identity" $ hedgehog $ do
      s <- forAll genSaleMoney
      addSale zeroSale s === s

    it "zeroSale is the right identity" $ hedgehog $ do
      s <- forAll genSaleMoney
      addSale s zeroSale === s

    it "is commutative" $ hedgehog $ do
      a <- forAll genSaleMoney
      b <- forAll genSaleMoney
      addSale a b === addSale b a

    it "is associative" $ hedgehog $ do
      a <- forAll genSaleMoney
      b <- forAll genSaleMoney
      c <- forAll genSaleMoney
      addSale (addSale a b) c === addSale a (addSale b c)

    it "matches integer addition on the cents" $ hedgehog $ do
      a <- forAll genSaleMoney
      b <- forAll genSaleMoney
      saleMoneyCents (addSale a b) === saleMoneyCents a + saleMoneyCents b

    it "preserves non-negativity" $ hedgehog $ do
      a <- forAll genSaleMoney
      b <- forAll genSaleMoney
      assert (saleMoneyCents (addSale a b) >= 0)

  describe "subtractSale" $ do
    it "subtracting from itself yields zero" $ hedgehog $ do
      s <- forAll genSaleMoney
      subtractSale s s === Just zeroSale

    it "subtracting zero is the identity" $ hedgehog $ do
      s <- forAll genSaleMoney
      subtractSale s zeroSale === Just s

    it "result is correct when defined, and undefined exactly when result would be negative" $ hedgehog $ do
      a <- forAll genSaleMoney
      b <- forAll genSaleMoney
      case subtractSale a b of
        Just dif ->
          saleMoneyCents dif === saleMoneyCents a - saleMoneyCents b
        Nothing ->
          assert (saleMoneyCents a < saleMoneyCents b)

  describe "scaleSale" $ do
    it "scaling by zero yields zero" $ hedgehog $ do
      s <- forAll genSaleMoney
      scaleSale s 0 === Just zeroSale

    it "scaling by one is the identity" $ hedgehog $ do
      s <- forAll genSaleMoney
      scaleSale s 1 === Just s

    it "matches integer multiplication on the cents (for non-negative scalars)" $ hedgehog $ do
      s <- forAll genSaleMoney
      k <- forAll genScalar
      fmap saleMoneyCents (scaleSale s k) === Just (saleMoneyCents s * k)

    it "rejects negative scalars" $ hedgehog $ do
      s <- forAll genSaleMoney
      k <- forAll $ Gen.int (Range.linear (-1000) (-1))
      scaleSale s k === Nothing

  describe "sumSale" $ do
    it "empty list yields zero" $
      sumSale [] `shouldBe` zeroSale

    it "singleton list returns the element" $ hedgehog $ do
      s <- forAll genSaleMoney
      sumSale [s] === s

    it "matches a right fold over addSale" $ hedgehog $ do
      xs <- forAll $ Gen.list (Range.linear 0 10) genSaleMoney
      sumSale xs === foldr addSale zeroSale xs

    it "preserves non-negativity" $ hedgehog $ do
      xs <- forAll $ Gen.list (Range.linear 0 20) genSaleMoney
      assert (saleMoneyCents (sumSale xs) >= 0)

  describe "RefundMoney construction" $ do
    it "rejects positive input" $ hedgehog $ do
      n <- forAll $ Gen.int (Range.linear 1 1000000)
      mkRefundMoney n === Nothing

    it "accepts non-positive input and round-trips through refundMoneyCents" $ hedgehog $ do
      n <- forAll $ Gen.int (Range.linear (-1000000) 0)
      fmap refundMoneyCents (mkRefundMoney n) === Just n

  describe "RefundMoney addition" $ do
    it "zeroRefund is the left identity" $ hedgehog $ do
      r <- forAll genRefundMoney
      addRefund zeroRefund r === r

    it "zeroRefund is the right identity" $ hedgehog $ do
      r <- forAll genRefundMoney
      addRefund r zeroRefund === r

    it "is commutative" $ hedgehog $ do
      a <- forAll genRefundMoney
      b <- forAll genRefundMoney
      addRefund a b === addRefund b a

    it "is associative" $ hedgehog $ do
      a <- forAll genRefundMoney
      b <- forAll genRefundMoney
      c <- forAll genRefundMoney
      addRefund (addRefund a b) c === addRefund a (addRefund b c)

    it "preserves non-positivity" $ hedgehog $ do
      a <- forAll genRefundMoney
      b <- forAll genRefundMoney
      assert (refundMoneyCents (addRefund a b) <= 0)

  describe "sumRefund" $ do
    it "empty list yields zero" $
      sumRefund [] `shouldBe` zeroRefund

    it "matches a right fold over addRefund" $ hedgehog $ do
      xs <- forAll $ Gen.list (Range.linear 0 10) genRefundMoney
      sumRefund xs === foldr addRefund zeroRefund xs

  describe "conversion between sale and refund" $ do
    it "negateToRefund flips sign" $ hedgehog $ do
      s <- forAll genSaleMoney
      refundMoneyCents (negateToRefund s) === negate (saleMoneyCents s)

    it "negateFromRefund flips sign" $ hedgehog $ do
      r <- forAll genRefundMoney
      saleMoneyCents (negateFromRefund r) === negate (refundMoneyCents r)

    it "zero maps to zero in both directions" $ do
      negateToRefund zeroSale `shouldBe` zeroRefund
      negateFromRefund zeroRefund `shouldBe` zeroSale

    it "round-trip Sale -> Refund -> Sale is the identity" $ hedgehog $ do
      s <- forAll genSaleMoney
      negateFromRefund (negateToRefund s) === s

    it "round-trip Refund -> Sale -> Refund is the identity" $ hedgehog $ do
      r <- forAll genRefundMoney
      negateToRefund (negateFromRefund r) === r