{-# LANGUAGE OverloadedStrings #-}

module Test.Props.NegateSpec (spec) where

import Hedgehog
import Test.Hspec
import Test.Hspec.Hedgehog (hedgehog)

import DB.Transaction
import Test.Gen
import Types.Transaction

spec :: Spec
spec = describe "Props.Negate" $ do
  describe "negateTransactionItem" $ do
    it "double negate is identity on subtotal" $ hedgehog $ do
      item <- forAll genTransactionItem
      transactionItemSubtotal (negateTransactionItem (negateTransactionItem item))
        === transactionItemSubtotal item

    it "double negate is identity on total" $ hedgehog $ do
      item <- forAll genTransactionItem
      transactionItemTotal (negateTransactionItem (negateTransactionItem item))
        === transactionItemTotal item

    it "single negate inverts subtotal" $ hedgehog $ do
      item <- forAll genTransactionItem
      transactionItemSubtotal (negateTransactionItem item)
        === negate (transactionItemSubtotal item)

    it "single negate inverts total" $ hedgehog $ do
      item <- forAll genTransactionItem
      transactionItemTotal (negateTransactionItem item)
        === negate (transactionItemTotal item)

    it "negate preserves transactionItemId" $ hedgehog $ do
      item <- forAll genTransactionItem
      transactionItemId (negateTransactionItem item)
        === transactionItemId item

    it "negate preserves transactionItemTransactionId" $ hedgehog $ do
      item <- forAll genTransactionItem
      transactionItemTransactionId (negateTransactionItem item)
        === transactionItemTransactionId item

    it "negate preserves quantity" $ hedgehog $ do
      item <- forAll genTransactionItem
      transactionItemQuantity (negateTransactionItem item)
        === transactionItemQuantity item

    it "negate preserves pricePerUnit" $ hedgehog $ do
      item <- forAll genTransactionItem
      transactionItemPricePerUnit (negateTransactionItem item)
        === transactionItemPricePerUnit item

  describe "negateDiscountRecord" $ do
    it "double negate is identity on amount" $ hedgehog $ do
      d <- forAll genDiscountRecord
      discountAmount (negateDiscountRecord (negateDiscountRecord d))
        === discountAmount d

    it "single negate inverts amount" $ hedgehog $ do
      d <- forAll genDiscountRecord
      discountAmount (negateDiscountRecord d)
        === negate (discountAmount d)

    it "negate preserves discountType" $ hedgehog $ do
      d <- forAll genDiscountRecord
      discountType (negateDiscountRecord d)
        === discountType d

    it "negate preserves discountReason" $ hedgehog $ do
      d <- forAll genDiscountRecord
      discountReason (negateDiscountRecord d)
        === discountReason d

  describe "negateTaxRecord" $ do
    it "double negate is identity on amount" $ hedgehog $ do
      t <- forAll genTaxRecord
      taxAmount (negateTaxRecord (negateTaxRecord t))
        === taxAmount t

    it "single negate inverts amount" $ hedgehog $ do
      t <- forAll genTaxRecord
      taxAmount (negateTaxRecord t)
        === negate (taxAmount t)

    it "negate preserves taxCategory" $ hedgehog $ do
      t <- forAll genTaxRecord
      taxCategory (negateTaxRecord t)
        === taxCategory t

    it "negate preserves taxRate" $ hedgehog $ do
      t <- forAll genTaxRecord
      taxRate (negateTaxRecord t)
        === taxRate t

  describe "negatePaymentTransaction" $ do
    it "double negate is identity on amount" $ hedgehog $ do
      p <- forAll genPaymentTransaction
      paymentAmount (negatePaymentTransaction (negatePaymentTransaction p))
        === paymentAmount p

    it "single negate inverts amount" $ hedgehog $ do
      p <- forAll genPaymentTransaction
      paymentAmount (negatePaymentTransaction p)
        === negate (paymentAmount p)

    it "single negate inverts tendered" $ hedgehog $ do
      p <- forAll genPaymentTransaction
      paymentTendered (negatePaymentTransaction p)
        === negate (paymentTendered p)

    it "single negate inverts change" $ hedgehog $ do
      p <- forAll genPaymentTransaction
      paymentChange (negatePaymentTransaction p)
        === negate (paymentChange p)

    it "negate preserves paymentMethod" $ hedgehog $ do
      p <- forAll genPaymentTransaction
      paymentMethod (negatePaymentTransaction p)
        === paymentMethod p

    it "negate preserves paymentApproved" $ hedgehog $ do
      p <- forAll genPaymentTransaction
      paymentApproved (negatePaymentTransaction p)
        === paymentApproved p
