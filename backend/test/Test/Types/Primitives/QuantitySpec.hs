{-# LANGUAGE OverloadedStrings #-}

module Test.Types.Primitives.QuantitySpec (spec) where

import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Hspec
import Test.Hspec.Hedgehog (hedgehog)

import Types.Primitives.Quantity

--------------------------------------------------------------------------------
-- Generators
--
-- Move to Test.Gen alongside the existing transaction-domain generators
-- once Phase 2C lands and the new typed item generators land too.
--------------------------------------------------------------------------------

-- | A SaleQuantity in [0, 10_000]. Same shape as 'genRefundQuantity'
-- since both have the same underlying invariant. The two are still
-- distinct types in the API.
genSaleQuantity :: Gen SaleQuantity
genSaleQuantity = do
  n <- Gen.int (Range.linear 0 10000)
  case mkSaleQuantity n of
    Just q  -> pure q
    Nothing -> error "genSaleQuantity: invariant violated"

genRefundQuantity :: Gen RefundQuantity
genRefundQuantity = do
  n <- Gen.int (Range.linear 0 10000)
  case mkRefundQuantity n of
    Just q  -> pure q
    Nothing -> error "genRefundQuantity: invariant violated"

--------------------------------------------------------------------------------
-- Spec
--------------------------------------------------------------------------------

spec :: Spec
spec = describe "Types.Primitives.Quantity" $ do

  describe "SaleQuantity construction" $ do
    it "rejects negative input" $ hedgehog $ do
      n <- forAll $ Gen.int (Range.linear (-10000) (-1))
      mkSaleQuantity n === Nothing

    it "accepts non-negative input and round-trips through saleQuantityCount" $ hedgehog $ do
      n <- forAll $ Gen.int (Range.linear 0 10000)
      fmap saleQuantityCount (mkSaleQuantity n) === Just n

  describe "SaleQuantity constants" $ do
    it "zeroSaleQuantity has count 0" $
      saleQuantityCount zeroSaleQuantity `shouldBe` 0

    it "oneSaleQuantity has count 1" $
      saleQuantityCount oneSaleQuantity `shouldBe` 1

  describe "SaleQuantity addition" $ do
    it "zeroSaleQuantity is the left identity" $ hedgehog $ do
      q <- forAll genSaleQuantity
      addSaleQuantity zeroSaleQuantity q === q

    it "zeroSaleQuantity is the right identity" $ hedgehog $ do
      q <- forAll genSaleQuantity
      addSaleQuantity q zeroSaleQuantity === q

    it "is commutative" $ hedgehog $ do
      a <- forAll genSaleQuantity
      b <- forAll genSaleQuantity
      addSaleQuantity a b === addSaleQuantity b a

    it "is associative" $ hedgehog $ do
      a <- forAll genSaleQuantity
      b <- forAll genSaleQuantity
      c <- forAll genSaleQuantity
      addSaleQuantity (addSaleQuantity a b) c
        === addSaleQuantity a (addSaleQuantity b c)

    it "matches integer addition on the count" $ hedgehog $ do
      a <- forAll genSaleQuantity
      b <- forAll genSaleQuantity
      saleQuantityCount (addSaleQuantity a b)
        === saleQuantityCount a + saleQuantityCount b

    it "preserves non-negativity" $ hedgehog $ do
      a <- forAll genSaleQuantity
      b <- forAll genSaleQuantity
      assert (saleQuantityCount (addSaleQuantity a b) >= 0)

  describe "subtractSaleQuantity" $ do
    it "subtracting from itself yields zero" $ hedgehog $ do
      q <- forAll genSaleQuantity
      subtractSaleQuantity q q === Just zeroSaleQuantity

    it "subtracting zero is the identity" $ hedgehog $ do
      q <- forAll genSaleQuantity
      subtractSaleQuantity q zeroSaleQuantity === Just q

    it "result is correct when defined, and undefined exactly when result would be negative" $ hedgehog $ do
      a <- forAll genSaleQuantity
      b <- forAll genSaleQuantity
      case subtractSaleQuantity a b of
        Just dif ->
          saleQuantityCount dif
            === saleQuantityCount a - saleQuantityCount b
        Nothing ->
          assert (saleQuantityCount a < saleQuantityCount b)

  describe "sumSaleQuantity" $ do
    it "empty list yields zero" $
      sumSaleQuantity [] `shouldBe` zeroSaleQuantity

    it "singleton list returns the element" $ hedgehog $ do
      q <- forAll genSaleQuantity
      sumSaleQuantity [q] === q

    it "matches a right fold over addSaleQuantity" $ hedgehog $ do
      xs <- forAll $ Gen.list (Range.linear 0 10) genSaleQuantity
      sumSaleQuantity xs === foldr addSaleQuantity zeroSaleQuantity xs

    it "preserves non-negativity" $ hedgehog $ do
      xs <- forAll $ Gen.list (Range.linear 0 20) genSaleQuantity
      assert (saleQuantityCount (sumSaleQuantity xs) >= 0)

  describe "RefundQuantity construction" $ do
    it "rejects negative input" $ hedgehog $ do
      n <- forAll $ Gen.int (Range.linear (-10000) (-1))
      mkRefundQuantity n === Nothing

    it "accepts non-negative input and round-trips through refundQuantityCount" $ hedgehog $ do
      n <- forAll $ Gen.int (Range.linear 0 10000)
      fmap refundQuantityCount (mkRefundQuantity n) === Just n

  describe "RefundQuantity addition" $ do
    it "zeroRefundQuantity is the left identity" $ hedgehog $ do
      q <- forAll genRefundQuantity
      addRefundQuantity zeroRefundQuantity q === q

    it "zeroRefundQuantity is the right identity" $ hedgehog $ do
      q <- forAll genRefundQuantity
      addRefundQuantity q zeroRefundQuantity === q

    it "is commutative" $ hedgehog $ do
      a <- forAll genRefundQuantity
      b <- forAll genRefundQuantity
      addRefundQuantity a b === addRefundQuantity b a

    it "is associative" $ hedgehog $ do
      a <- forAll genRefundQuantity
      b <- forAll genRefundQuantity
      c <- forAll genRefundQuantity
      addRefundQuantity (addRefundQuantity a b) c
        === addRefundQuantity a (addRefundQuantity b c)

    it "preserves non-negativity" $ hedgehog $ do
      a <- forAll genRefundQuantity
      b <- forAll genRefundQuantity
      assert (refundQuantityCount (addRefundQuantity a b) >= 0)

  describe "subtractRefundQuantity" $ do
    it "subtracting from itself yields zero" $ hedgehog $ do
      q <- forAll genRefundQuantity
      subtractRefundQuantity q q === Just zeroRefundQuantity

    it "result is correct when defined, and undefined exactly when result would be negative" $ hedgehog $ do
      a <- forAll genRefundQuantity
      b <- forAll genRefundQuantity
      case subtractRefundQuantity a b of
        Just dif ->
          refundQuantityCount dif
            === refundQuantityCount a - refundQuantityCount b
        Nothing ->
          assert (refundQuantityCount a < refundQuantityCount b)

  describe "sumRefundQuantity" $ do
    it "empty list yields zero" $
      sumRefundQuantity [] `shouldBe` zeroRefundQuantity

    it "matches a right fold over addRefundQuantity" $ hedgehog $ do
      xs <- forAll $ Gen.list (Range.linear 0 10) genRefundQuantity
      sumRefundQuantity xs === foldr addRefundQuantity zeroRefundQuantity xs

  describe "conversion between sale and refund (nominal)" $ do
    it "toRefundQuantity preserves the underlying count" $ hedgehog $ do
      q <- forAll genSaleQuantity
      refundQuantityCount (toRefundQuantity q) === saleQuantityCount q

    it "toSaleQuantity preserves the underlying count" $ hedgehog $ do
      q <- forAll genRefundQuantity
      saleQuantityCount (toSaleQuantity q) === refundQuantityCount q

    it "zero maps to zero in both directions" $ do
      toRefundQuantity zeroSaleQuantity `shouldBe` zeroRefundQuantity
      toSaleQuantity zeroRefundQuantity `shouldBe` zeroSaleQuantity

    it "round-trip Sale -> Refund -> Sale is the identity" $ hedgehog $ do
      q <- forAll genSaleQuantity
      toSaleQuantity (toRefundQuantity q) === q

    it "round-trip Refund -> Sale -> Refund is the identity" $ hedgehog $ do
      q <- forAll genRefundQuantity
      toRefundQuantity (toSaleQuantity q) === q