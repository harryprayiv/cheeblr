The container has Nix, so I'll try your flake's dev shell to get your real toolchain.

The mtl pin worked: singletons-base is compiling now. Still waiting on lens, openapi3 and crem.

Same GHC 9.10 Prelude gap as in pelotero. I'll patch the scratch copy only.

Everything compiled except my probe module. Checking its errors:

Harry, I've written `cheeblr.allium`, an Allium v3 spec for the backend on `delta` (8e193fa, Oct 17). You're right that cheeblr is more solid than pelotero.

**What's solid:**
- Pricing and tax: integer cents, rates in parts per million, rounding named per rule, and unknown codes are refused instead of being skipped.
- Locking: the sale's row lock is taken on every write, so finalize, clear, void and refund can't race each other.
- Stock and passwords: reservations are taken under item locks; the restock policy must be set in config before the server starts; passwords use Argon2id; logins are rate-limited.

**What's wrong:**

I ran five probes against copies of your real modules; all five fail. I used GHC 9.4.7 with mtl pinned to the installed 2.2, plus a `foldl'` import added to scratch copies because the code expects GHC 9.10's Prelude. Your tree wasn't patched.
- **C1: payments can exceed the total.** `finalizeProblems 2 2052 3000` returns no problems, so a $20.52 sale can be finalized with $30.00 on cards and no change recorded. Your own `SaleRulesSpec` asserts this, so either the test or the rule is wrong.
- **C2: a refund of that sale pays back $30.00 against a refund total of $20.52.** Refund payments are the sale's payments negated.
- **C3: refunds and voids record the wrong person.** The refund's employee is the original cashier; `toRefundTransaction` has no parameter for whoever issued it. Void and refund events do the same with `teActorId`.
- **C4: cashiers have `capCanEditItem`.** `PUT /inventory` lets a cashier set an item's price to 0, ring it up, and set the price back. It also lets them change on-hand counts.
- **C5: any employee can close any open register.** The register machine ignores who sends the close.

From reading the code (each has a "CODE:" note in the spec):
- **The expected drawer amount is never updated after opening.** Every close reports variance as starting cash minus counted cash, so every cash sale shows up as a shortage.
- **A sale's register and location both come from the request, unchecked.** A sale can be started on a closed register or another store's register. The location picks the tax rules, so a client can pick a cheaper tax jurisdiction.
- **Any session, including a customer account, can read every sale and refund** through `GET /sale` and `GET /refund`.
- **Voids of completed sales have problems.**
  - A completed sale can be voided at any time.
  - Its payments are left as they were, with no reversal, and with the restock policy set to restock, its stock goes back on the shelf.
  - The manager override void writes no compliance log entry; the `/sale` route does.
- **Clear has two problems.** It moves a sale from in progress back to created, an edge your crem topology doesn't have, by writing the status directly. It also deletes payments, so a card payment already taken disappears from the record.
- **Finalize has no floor on stock.** After an inventory edit lowers the on-hand count, finalize can push it negative.
- **The ledger and compliance routes return made-up successes.**
  - `POST` compliance verification returns the request body as though it were verified.
  - The daily reports return zeros.
- **Smaller items:**
  - Refunds are all-or-nothing.
  - Overlapping tax rules are both charged.
  - Once discounts are implemented, tax will be charged on the undiscounted price.
  - `verifyPassword` compares hashes with `==`, which is not constant-time, and ignores the parameters stored in the hash. Changing `argonOpts` would lock everyone out.

The spec ends with 15 open questions for your refactor.

**To add the probes (winsmuth, in `/home/bismuth/git/cheeblr/backend`):**
1. Save this as `test/Test/ProbeSpec.hs`:

```haskell
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
```

2. In `cheeblr-backend.cabal`, add `Test.ProbeSpec` to the `other-modules` list of `cheeblr-unit-tests`, on the line after `Test.Domain.SaleRulesSpec` (line 197).
3. Replace `test/Spec.hs` with this:

```haskell
module Main where

import Test.Hspec

import qualified Test.API.AdminSpec
import qualified Test.API.OpenApiSpec
import qualified Test.API.TransactionSpec
import qualified Test.App.CspSpec
import qualified Test.App.MiddlewareSpec
import qualified Test.DB.PureFunctionsSpec
import qualified Test.Domain.PricingSpec
import qualified Test.Domain.SaleRulesSpec
import qualified Test.Domain.TaxRuleSpec
import qualified Test.Effect.EventEmitterSpec
import qualified Test.Effect.InventoryDbSpec
import qualified Test.Effect.StockDbSpec
import qualified Test.GraphQL.ResolversSpec
import qualified Test.GraphQL.SchemaSpec
import qualified Test.Infrastructure.AvailabilityRelaySpec
import qualified Test.Manager.LogicSpec
import qualified Test.Manager.TypesSpec
import qualified Test.ProbeSpec
import qualified Test.Props.JsonRoundtripSpec
import qualified Test.Props.NegateSpec
import qualified Test.Props.ParseShowSpec
import qualified Test.Props.StateMachineSpec
import qualified Test.Server.CookieSpec
import qualified Test.Server.Middleware.TracingSpec
import qualified Test.Service.RegisterSpec
import qualified Test.Service.SaleSpec
import qualified Test.Service.StockSpec
import qualified Test.Service.TransactionSpec
import qualified Test.State.RegisterMachineSpec
import qualified Test.State.StockPullMachineSpec
import qualified Test.State.TransactionMachineSpec
import qualified Test.Types.AuthSpec
import qualified Test.Types.InventorySpec
import qualified Test.Types.Public.AvailableItemSpec
import qualified Test.Types.Public.FeedFrameSpec
import qualified Test.Types.Public.FeedPrivacySpec
import qualified Test.Types.TraceSpec
import qualified Test.Types.TransactionSpec
import qualified Test.Types.Primitives.MoneySpec
import qualified Test.Types.Primitives.QuantitySpec
import qualified Test.Types.Transaction.ConversionSpec
import qualified Test.DB.Transaction.SaleSpec
import qualified Test.DB.Transaction.RefundSpec

main :: IO ()
main = hspec $ do
  describe "Cheeblr Backend" $ do
    Test.ProbeSpec.spec
    Test.Types.AuthSpec.spec
    Test.Types.TraceSpec.spec
    Test.Types.TransactionSpec.spec
    Test.Types.InventorySpec.spec
    Test.Types.Public.AvailableItemSpec.spec
    Test.Types.Public.FeedFrameSpec.spec
    Test.Types.Public.FeedPrivacySpec.spec
    Test.Types.Primitives.MoneySpec.spec
    Test.Types.Primitives.QuantitySpec.spec
    Test.Domain.PricingSpec.spec
    Test.Domain.TaxRuleSpec.spec
    Test.Domain.SaleRulesSpec.spec
    Test.API.TransactionSpec.spec
    Test.API.OpenApiSpec.spec
    Test.API.AdminSpec.spec
    Test.DB.PureFunctionsSpec.spec
    Test.GraphQL.SchemaSpec.spec
    Test.GraphQL.ResolversSpec.spec
    Test.State.TransactionMachineSpec.spec
    Test.State.RegisterMachineSpec.spec
    Test.Effect.InventoryDbSpec.spec
    Test.Effect.EventEmitterSpec.spec
    Test.Server.CookieSpec.spec
    Test.Server.Middleware.TracingSpec.spec
    Test.App.CspSpec.spec
    Test.App.MiddlewareSpec.spec
    Test.Service.TransactionSpec.spec
    Test.Service.SaleSpec.spec
    Test.Service.RegisterSpec.spec
    Test.Props.JsonRoundtripSpec.spec
    Test.Props.ParseShowSpec.spec
    Test.Props.NegateSpec.spec
    Test.Props.StateMachineSpec.spec
    Test.Infrastructure.AvailabilityRelaySpec.spec
    Test.Manager.TypesSpec.spec
    Test.Manager.LogicSpec.spec
    Test.State.StockPullMachineSpec.spec
    Test.Effect.StockDbSpec.spec
    Test.Service.StockSpec.spec
    Test.Types.Transaction.ConversionSpec.spec
    Test.DB.Transaction.SaleSpec.spec
    Test.DB.Transaction.RefundSpec.spec
```

The two `let Right refund =` bindings will get an incomplete-pattern warning under `-Wall`. The drawer, sale-location and customer-read bugs go through the database and the HTTP handlers, so pure probes can't reach them. They need integration tests, or the puppet test rig you've been planning.

I'm not committing that file, for the same reasons as with pelotero. The only untracked file is the probe I wrote, `backend/test/Test/ProbeSpec.hs`. This copy of cheeblr was cloned read-only, and you haven't asked me to push anything.

The full file is in my last message for you to add yourself. If you want it committed on a branch instead, name the branch and I'll attach the repo with push access.