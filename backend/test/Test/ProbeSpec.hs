{-# LANGUAGE OverloadedStrings #-}

-- | Probes for suspected defects on the delta branch. Each test asserts the
-- behaviour the spec (cheeblr.allium) requires; a failure is evidence for
-- the matching issue. C-numbers match the spec's comments.
module Test.ProbeSpec (spec) where

import Data.Maybe (fromJust)
import Data.Time (UTCTime (..), fromGregorian)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import Test.Hspec

import API.Transaction (Register (..))
import Domain.SaleRules (finalizeProblems)
import State.RegisterMachine
  ( RegCommand (..)
  , RegEvent (..)
  , fromRegister
  , runRegCommand
  )
import Types.Auth (UserCapabilities (..), UserRole (..), capabilitiesForRole)
import Types.Location (LocationId (..))
import Types.Primitives.Money (refundMoneyCents, unsafeMkSaleMoney)
import Types.Transaction (PaymentMethod (..), TransactionStatus (..))
import Types.Transaction.Conversion (toRefundTransaction)
import qualified Types.Transaction.Refund as Refund
import qualified Types.Transaction.Sale as Sale

uuid :: Int -> UUID
uuid n = fromJust (UUID.fromString ("00000000-0000-0000-0000-" <> pad (show n)))
  where
    pad s = replicate (12 - length s) '0' <> s

t0 :: UTCTime
t0 = UTCTime (fromGregorian 2026 10 23) 0

cents :: Int -> Sale.Payment -> Sale.Payment
cents n p = p {Sale.paymentAmount = unsafeMkSaleMoney n, Sale.paymentTendered = unsafeMkSaleMoney n}

cardPayment :: Int -> Int -> Sale.Payment
cardPayment pid n =
  cents
    n
    Sale.Payment
      { Sale.paymentId                = uuid pid
      , Sale.paymentTransactionId     = uuid 1
      , Sale.paymentMethod            = Credit
      , Sale.paymentAmount            = unsafeMkSaleMoney 0
      , Sale.paymentTendered          = unsafeMkSaleMoney 0
      , Sale.paymentChange            = unsafeMkSaleMoney 0
      , Sale.paymentReference         = Nothing
      , Sale.paymentApproved          = True
      , Sale.paymentAuthorizationCode = Nothing
      }

-- | A completed sale with a total of $20.52, paid with $30.00 on cards,
-- which finalize accepts today.
overpaidSale :: Sale.SaleTransaction
overpaidSale =
  Sale.SaleTransaction
    { Sale.saleId            = uuid 1
    , Sale.saleStatus        = Completed
    , Sale.saleCreated       = t0
    , Sale.saleCompleted     = Just t0
    , Sale.saleCustomerId    = Nothing
    , Sale.saleEmployeeId    = uuid 9
    , Sale.saleRegisterId    = uuid 8
    , Sale.saleLocationId    = LocationId (uuid 7)
    , Sale.saleItems         = []
    , Sale.salePayments      = [cardPayment 2 2000, cardPayment 3 1000]
    , Sale.saleSubtotal      = unsafeMkSaleMoney 1900
    , Sale.saleDiscountTotal = unsafeMkSaleMoney 0
    , Sale.saleTaxTotal      = unsafeMkSaleMoney 152
    , Sale.saleTotal         = unsafeMkSaleMoney 2052
    , Sale.saleKind          = Sale.StandardSale
    , Sale.saleIsVoided      = False
    , Sale.saleVoidReason    = Nothing
    , Sale.saleIsRefunded    = False
    , Sale.saleRefundReason  = Nothing
    , Sale.saleNotes         = Nothing
    }

openRegister :: Register
openRegister =
  Register
    { registerId                   = uuid 8
    , registerName                 = "front"
    , registerLocationId           = LocationId (uuid 7)
    , registerIsOpen               = True
    , registerCurrentDrawerAmount  = 10000
    , registerExpectedDrawerAmount = 10000
    , registerOpenedAt             = Just t0
    , registerOpenedBy             = Just (uuid 9)
    , registerLastTransactionTime  = Nothing
    }

isInvalid :: RegEvent -> Bool
isInvalid (InvalidRegCommand _) = True
isInvalid _                     = False

spec :: Spec
spec = describe "probes" $ do
  it "C1 finalize refuses payments that exceed the total" $
    finalizeProblems 2 2052 3000 `shouldNotBe` []

  it "C2 a refund pays back exactly the refund total" $ do
    let Right refund =
          toRefundTransaction t0 (uuid 100) [] [uuid 101, uuid 102] "probe" overpaidSale
        paidBack = sum (map (refundMoneyCents . Refund.paymentAmount) (Refund.refundPayments refund))
    paidBack `shouldBe` refundMoneyCents (Refund.refundTotal refund)

  it "C3 a refund records who issued it, not who rang the sale" $ do
    let Right refund =
          toRefundTransaction t0 (uuid 100) [] [uuid 101, uuid 102] "probe" overpaidSale
    -- toRefundTransaction has no parameter for the acting employee, so the
    -- refund can only ever carry the original cashier.
    Refund.refundEmployeeId refund `shouldNotBe` Sale.saleEmployeeId overpaidSale

  it "C4 a cashier cannot edit inventory items (prices, quantities)" $
    capCanEditItem (capabilitiesForRole Cashier) `shouldBe` False

  it "C5 only the employee who opened a register, or a manager, closes it" $ do
    let (evt, _) = runRegCommand (fromRegister openRegister) (CloseRegCmd (uuid 55) 10000)
    evt `shouldSatisfy` isInvalid