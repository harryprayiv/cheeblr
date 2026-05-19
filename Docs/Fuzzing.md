# Blunt take first

Don't port Fuzzapi. It is a Ruby black-box pentest tool that slings FuzzDB payloads at a request captured from Burp. Its whole reason for existing is that the target API is untyped and unspecified. You have the opposite problem: Servant types, an OpenAPI 3 spec, Hedgehog, crem state machines, and pure interpreters for every DB effect. Reimplementing Fuzzapi in Haskell would be throwing away every advantage you spent the last six months building.

What you should build is a layered fuzzer that uses your spec as the source of truth and treats Fuzzapi-style payload injection as one small layer near the top, not the whole architecture.

# Architecture I would actually build

Six layers, all driven by Hedgehog so a single failure shrinks to a minimal counterexample:

1. **Protocol invariants (servant-quickcheck)**. Generic checks every endpoint must satisfy: never returns 5xx, every 4xx has your structured error envelope, content-type honors Accept, OPTIONS reflects the route, HEAD agrees with GET, idempotent methods are actually idempotent, no endpoint accepts a stale session cookie after rotation. servant-quickcheck gives you most of this for free over a Servant API value.

2. **Schema-typed input fuzzing (Hedgehog + Generic)**. Derive `Gen` for every request type. Hedgehog generates well-typed but boundary-pathological inputs: empty Text, 10MB Text, Text containing every Unicode category, negative Money, zero-quantity inventory, dates at 1970 and 9999, NaN/Infinity where doubles leak in, decoder edge cases. This is where you catch the bugs your contract tests already started catching, but exhaustively. Run it against the pure effect interpreter and you can do millions of iterations per minute.

3. **Stateful fuzzing (Hedgehog `Var`/state machine, or crem traces)**. You already have `TransactionMachine` and `RegisterMachine`. Hedgehog's state-machine testing generates sequences of commands and asserts a model invariant after every step: `sum(transactions.amount) == register.balance`, no double-spend, no negative inventory, no orphan line items, audit log strictly grows. This is the single highest-value layer and Fuzzapi cannot do it at all.

4. **Authorization matrix**. Generate (user_role, endpoint, resource_owner) triples. For each, assert that the response code is the one your RBAC matrix says it should be. This catches IDOR, missing auth checks, and over-broad role grants in a way that scales with your endpoint count instead of with hand-written tests. Lives on top of your session/db effects.

5. **Adversarial payload corpus**. The actual Fuzzapi-equivalent layer. A FuzzDB-style corpus of XSS, SQLi, XXE, command injection, path traversal, header CRLF, open-redirect, and unicode/RTL-override payloads, injected into Text leaves of well-typed request bodies. Safety invariants: response status never 5xx, payload never reflected verbatim in body, content-type never flips to text/html on a JSON endpoint, error envelope present on 4xx. SQLi is almost a non-issue for you because of Rel8, but log injection (Katip), GraphQL string handling (Morpheus), and reflection through error messages are real and this layer catches them.

6. **Differential testing (REST vs GraphQL)**. You expose inventory both at REST and at `POST /graphql/inventory`. For any logical query expressible in both, the responses must agree after normalization. Fuzz the input space, hit both, diff. Catches every drift between the two layers before customers do.

Run layers 1 through 4 against the pure interpreter in unit-test time. Run layers 5 and 6 against the real Warp + Postgres stack in a nightly job because they need the actual wire protocol and SQL engine.

# Starter: the layer 5 module

This is the one that maps closest to your question, and the one that has no good off-the-shelf Haskell answer. It loads a payload corpus, walks any JSON `Value`, finds every Text leaf with a reconstruction setter, mutates one or more leaves with adversarial payloads, and checks safety invariants on the response. Glue it to your existing Hedgehog request runner.

Two things to fix when you drop this into your tree, because I do not have your exact module/cabal layout in front of me: replace the stub `catchIO` with `Control.Exception.catch` and the proper `IOError` import, and adjust the module path to wherever `Cheeblr.Test.*` actually lives. The rest compiles against the package set you already have (`aeson`, `hedgehog`, `text`, `bytestring`, `vector`, `filepath`).


# Where to go next

Pick one and I will write the next module. In rough order of value-for-effort:

- **Layer 3 (state-machine fuzz of `TransactionMachine`)**: highest payoff, leverages crem you already have, catches the bugs that cost real money.
- **Layer 4 (authorization matrix)**: cheapest to write, catches the bug class (IDOR, role escalation) that gets POS systems on the news.
- **Layer 6 (REST vs GraphQL diff)**: unique to your dual-API design and cannot drift silently once it exists.
- **Layer 1 (servant-quickcheck wiring)**: smallest code, gives you a credible "we fuzz the API" line in your security audit doc.

Layer 5 (the module above) is necessary but not where I would start; the bugs it finds are real but rarer than the state-machine and authorization bugs in a transactional system.


Updated LLM assesment:


Reading the actual suite, you've already built most of what I sketched. You have schema-typed Hedgehog generators for every domain type (Test.Gen), JSON roundtrip props, parse/show roundtrips, crem state-machine props for single commands, pure-interpreter tests for every effect, and 17 service-level tests with event-emission verification. The Fuzzapi-equivalent adversarial payload layer is the smallest delta against this stack because Rel8 closes SQL injection structurally and Aeson-derived instances close JSON injection. My previous post was directionally right but proposed the wrong starter for what you have.

The real gaps:

1. **Sequences against the state machines.** Your Props.StateMachineSpec tests Voided and Refunded as sinks one command at a time. Nothing tests interleavings (AddItem AddItem Void RemoveItem AddItem and so on) against the Service layer with invariants checked after every step. This is where reservation leaks, double holds, and orphan reservations hide. Your single-shot tests cover "addItem then removeItem restores reserved count"; the bug class lives in 15-command mixed-validity sequences.
2. **Servant-quickcheck against the wired Application.** Every test exercises types or pure functions. Nothing fuzzes the actual middleware stack (cookieAuth, tracing, CORS, CSP, OPTIONS short-circuit) plus handler as one wai Application.
3. **Authorization matrix as a generated property.** capabilitiesForRole is tested per role, but no test enumerates (endpoint × role) and asserts the response code matches the capability matrix. This is the IDOR and role-escalation defense.
4. **REST vs GraphQL differential on inventory.** Both paths can create, update, and delete MenuItem. No test asserts they agree on the same logical operation under fuzzed input.

Order of value-per-effort for a regulated-substance POS: 1, 3, 4, 2. Below is 1. It generates random command sequences, runs them through your existing pure interpreter stack with the same effects ordering Test.Service.TransactionSpec uses, and asserts three invariants after every step: no 5xx, reserved quantity matches a model maintained alongside the interpreter, observed status matches model status. Hedgehog shrinks failures to minimal counterexamples.

```haskell
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

-- |
-- Module      : Test.Props.TxLifecycleSpec
-- Description : Sequential property test for the transaction lifecycle.
--
-- Existing tests cover each Service.Transaction call in isolation
-- (Test.Service.TransactionSpec) and each crem transition in isolation
-- (Test.State.TransactionMachineSpec, Test.Props.StateMachineSpec).
-- This module covers the combinations.
--
-- It generates random sequences of mixed valid and invalid commands,
-- runs them against the same pure interpreter stack the existing
-- service spec uses, and after every step asserts:
--
--   1. No 5xx. Rejections must be 400/404/409.
--   2. Reservation invariant: the active-reserved count for the SKU
--      matches a Haskell-side model maintained alongside the
--      interpreter.
--   3. Status invariant: the observed transactionStatus matches the
--      model's status.
--
-- These are the bugs that drift over long shifts: reservation leaks,
-- double holds, and orphan reservations after a void.
module Test.Props.TxLifecycleSpec (spec) where

import Data.Foldable          (for_)
import Data.Map.Strict        qualified as Map
import Data.Text              qualified as T
import Data.Time              (UTCTime)
import Data.UUID              (UUID)
import Data.UUID              qualified as UUID
import Effectful              (Eff, IOE, runEff)
import Effectful.Error.Static
  ( Error
  , catchError
  , runErrorNoCallStack
  )
import Hedgehog
import Hedgehog.Gen           qualified as Gen
import Hedgehog.Range         qualified as Range
import Servant                (ServerError (..))
import Test.Hspec
import Test.Hspec.Hedgehog    (hedgehog)

import Effect.Clock           (Clock, runClockPure)
import Effect.EventEmitter    (EventEmitter, runEventEmitterNoop)
import Effect.GenUUID         (GenUUID, runGenUUIDPure)
import Effect.InventoryDb     (InventoryDb, runInventoryDbPure)
import Effect.StockDb         (StockDb, emptyStockStore, runStockDbPure)
import Effect.TransactionDb
import Service.Transaction    qualified as Svc
import Types.Location         (LocationId (..))
import Types.Transaction


-- --------------------------------------------------------------------------
-- Fixed universe
-- --------------------------------------------------------------------------

txUUID, skuUUID, empUUID, regUUID, locUUID :: UUID
txUUID  = UUID.fromWords 0x11111111 0x11111111 0x11111111 0x11111111
skuUUID = UUID.fromWords 0x22222222 0x22222222 0x22222222 0x22222222
empUUID = UUID.fromWords 0x33333333 0x33333333 0x33333333 0x33333333
regUUID = UUID.fromWords 0x44444444 0x44444444 0x44444444 0x44444444
locUUID = UUID.fromWords 0x55555555 0x55555555 0x55555555 0x55555555

testTime :: UTCTime
testTime = read "2024-06-15 10:00:00 UTC"

totalInventory :: Int
totalInventory = 1000

itemUUID :: Int -> UUID
itemUUID i = UUID.fromWords 0xAAAAAAAA 0 0 (fromIntegral i)

paymentUUID :: Int -> UUID
paymentUUID i = UUID.fromWords 0xBBBBBBBB 0 0 (fromIntegral i)

-- 10k is comfortably more than any reasonable sequence needs.
uuidSupply :: [UUID]
uuidSupply =
  [UUID.fromWords 0xCCCCCCCC 0 0 (fromIntegral i) | i <- [1 .. 10000 :: Int]]


-- --------------------------------------------------------------------------
-- Initial transaction and store
-- --------------------------------------------------------------------------

initialTx :: Transaction
initialTx = Transaction
  { transactionId                     = txUUID
  , transactionStatus                 = Created
  , transactionCreated                = testTime
  , transactionCompleted              = Nothing
  , transactionCustomerId             = Nothing
  , transactionEmployeeId             = empUUID
  , transactionRegisterId             = regUUID
  , transactionLocationId             = LocationId locUUID
  , transactionItems                  = []
  , transactionPayments               = []
  , transactionSubtotal               = 0
  , transactionDiscountTotal          = 0
  , transactionTaxTotal               = 0
  , transactionTotal                  = 0
  , transactionType                   = Sale
  , transactionIsVoided               = False
  , transactionVoidReason             = Nothing
  , transactionIsRefunded             = False
  , transactionRefundReason           = Nothing
  , transactionReferenceTransactionId = Nothing
  , transactionNotes                  = Nothing
  }

initialStore :: TxStore
initialStore = emptyTxStore
  { tsTxs       = Map.singleton txUUID initialTx
  , tsInventory = Map.singleton skuUUID totalInventory
  }


-- --------------------------------------------------------------------------
-- Commands and model
-- --------------------------------------------------------------------------

data Cmd
  = AddItem            !Int !Int   -- item index, quantity
  | RemoveOldestItem
  | AddPayment         !Int !Int   -- payment index, amount cents
  | RemoveOldestPayment
  | Finalize
  | Void               !T.Text
  deriving (Show, Eq)

data Model = Model
  { mStatus   :: !TransactionStatus
  , mItems    :: ![(UUID, Int)]    -- FIFO of (item_id, qty) still attached
  , mPayments :: ![UUID]
  }
  deriving (Show)

initialModel :: Model
initialModel = Model { mStatus = Created, mItems = [], mPayments = [] }

genCmd :: Gen Cmd
genCmd = Gen.frequency
  [ (5, AddItem    <$> Gen.int (Range.linear 0 500) <*> Gen.int (Range.linear 1 5))
  , (3, pure RemoveOldestItem)
  , (3, AddPayment <$> Gen.int (Range.linear 0 500) <*> Gen.int (Range.linear 1 10000))
  , (2, pure RemoveOldestPayment)
  , (1, pure Finalize)
  , (1, Void <$> Gen.text (Range.linear 1 20) Gen.alphaNum)
  ]

genCmds :: Gen [Cmd]
genCmds = Gen.list (Range.linear 1 30) genCmd

mkItem :: Int -> Int -> TransactionItem
mkItem i q = TransactionItem
  { transactionItemId            = itemUUID i
  , transactionItemTransactionId = txUUID
  , transactionItemMenuItemSku   = skuUUID
  , transactionItemQuantity      = q
  , transactionItemPricePerUnit  = 1000
  , transactionItemDiscounts     = []
  , transactionItemTaxes         = []
  , transactionItemSubtotal      = 1000 * q
  , transactionItemTotal         = 1000 * q
  }

mkPayment :: Int -> Int -> PaymentTransaction
mkPayment i amt = PaymentTransaction
  { paymentId                = paymentUUID i
  , paymentTransactionId     = txUUID
  , paymentMethod            = Cash
  , paymentAmount            = amt
  , paymentTendered          = amt
  , paymentChange            = 0
  , paymentReference         = Nothing
  , paymentApproved          = True
  , paymentAuthorizationCode = Nothing
  }


-- --------------------------------------------------------------------------
-- Effect runner. Same shape as Test.Service.TransactionSpec.runTest, but
-- it preserves the final TxStore so we can thread state across commands.
-- --------------------------------------------------------------------------

type TestEffs =
  '[ TransactionDb
   , StockDb
   , InventoryDb
   , Clock
   , GenUUID
   , EventEmitter
   , Error ServerError
   , IOE
   ]

runStep
  :: TxStore
  -> Eff TestEffs a
  -> IO (Either ServerError (a, TxStore))
runStep store action =
  fmap repack
    $ runEff
      . runErrorNoCallStack @ServerError
      . runEventEmitterNoop
      . runGenUUIDPure uuidSupply
      . runClockPure testTime
      . runInventoryDbPure Map.empty
      . runStockDbPure emptyStockStore
      . runTransactionDbPure store
    $ action
  where
    -- Either ServerError (((((a, TxStore), StockStore), InvMap), [UUID]))
    repack = fmap (\((((a, tx), _stk), _inv), _uu) -> (a, tx))

-- | Catch a ServerError thrown by one command so queries that follow
-- in the same Eff still run. Rejections become Left rather than
-- short-circuiting the whole step.
attempt
  :: (Error ServerError :> es)
  => Eff es a
  -> Eff es (Either ServerError a)
attempt action =
  (Right <$> action) `catchError` (\_ e -> pure (Left e))


-- --------------------------------------------------------------------------
-- One command plus observation
-- --------------------------------------------------------------------------

data StepObservation = StepObservation
  { stepCmd    :: !Cmd
  , stepResult :: !(Either ServerError ())
  , stepAvail  :: !(Maybe (Int, Int))    -- (total, reserved) for skuUUID
  , stepStatus :: !(Maybe TransactionStatus)
  , stepModel  :: !Model
  }
  deriving (Show)

oneCommand
  :: Cmd
  -> Eff TestEffs (Either ServerError (), Maybe (Int, Int), Maybe TransactionStatus)
oneCommand cmd = do
  r      <- attempt (executeCmd cmd)
  avail  <- getInventoryAvailability skuUUID
  status <- fmap transactionStatus <$> getTransactionById txUUID
  pure (() <$ r, avail, status)
  where
    executeCmd = \case
      AddItem i q          -> () <$ Svc.addItem (mkItem i q)
      RemoveOldestItem     -> pickOldestItem    >>= maybe (pure ()) Svc.removeItem
      AddPayment i a       -> () <$ Svc.addPayment (mkPayment i a)
      RemoveOldestPayment  -> pickOldestPayment >>= maybe (pure ()) Svc.removePayment
      Finalize             -> () <$ Svc.finalizeTx txUUID
      Void reason          -> () <$ Svc.voidTx txUUID reason

    pickOldestItem :: Eff TestEffs (Maybe UUID)
    pickOldestItem = do
      mTx <- getTransactionById txUUID
      pure $ case mTx of
        Just tx | (it:_) <- transactionItems tx -> Just (transactionItemId it)
        _                                       -> Nothing

    pickOldestPayment :: Eff TestEffs (Maybe UUID)
    pickOldestPayment = do
      mTx <- getTransactionById txUUID
      pure $ case mTx of
        Just tx | (p:_) <- transactionPayments tx -> Just (paymentId p)
        _                                         -> Nothing


-- --------------------------------------------------------------------------
-- Threading state and updating the model
-- --------------------------------------------------------------------------

-- | Update the model from the observed outcome, not the command, so a
-- rejected command leaves the model untouched. This keeps the model
-- in lockstep with the interpreter even when the random sequence
-- includes illegal commands.
applyModel
  :: Cmd
  -> Either ServerError ()
  -> Maybe TransactionStatus
  -> Model
  -> Model
applyModel cmd result observedStatus m = case result of
  Left _    -> m
  Right ()  ->
    let m' = m { mStatus = maybe (mStatus m) id observedStatus }
    in case cmd of
         AddItem i q          -> m' { mItems    = mItems m' ++ [(itemUUID i, q)] }
         RemoveOldestItem     -> m' { mItems    = drop 1 (mItems m') }
         AddPayment i _       -> m' { mPayments = mPayments m' ++ [paymentUUID i] }
         RemoveOldestPayment  -> m' { mPayments = drop 1 (mPayments m') }
         Finalize             -> m'
         Void _               -> m'

runSequence :: [Cmd] -> IO (Either ServerError [StepObservation])
runSequence = go initialStore initialModel []
  where
    go _store _model acc []      = pure (Right (reverse acc))
    go store  model  acc (c:cs)  = do
      r <- runStep store (oneCommand c)
      case r of
        Left err -> pure (Left err)
        Right ((cmdResult, avail, status), store') -> do
          let model' = applyModel c cmdResult status model
              step   = StepObservation
                         { stepCmd    = c
                         , stepResult = cmdResult
                         , stepAvail  = avail
                         , stepStatus = status
                         , stepModel  = model'
                         }
          go store' model' (step : acc) cs


-- --------------------------------------------------------------------------
-- Invariants
-- --------------------------------------------------------------------------

-- | Expected active-reserved quantity for skuUUID given the model.
--
-- Created/InProgress: items hold "Reserved" entries.
-- Completed:          finalize marks entries Completed, active drops to 0.
-- Voided/Refunded:    interpreter behavior is not documented in the
--                     chase bundle for the pure interpreter, so we
--                     return Nothing and skip this check in those
--                     states. Tighten once you confirm the behavior.
expectedReserved :: Model -> Maybe Int
expectedReserved m = case mStatus m of
  Created    -> Just (sum (map snd (mItems m)))
  InProgress -> Just (sum (map snd (mItems m)))
  Completed  -> Just 0
  Voided     -> Nothing
  Refunded   -> Nothing

checkStep :: StepObservation -> PropertyT IO ()
checkStep StepObservation { stepCmd, stepResult, stepAvail, stepStatus, stepModel } = do
  -- (1) No 5xx.
  case stepResult of
    Right _  -> pure ()
    Left err
      | errHTTPCode err >= 400 && errHTTPCode err < 500 -> pure ()
      | otherwise -> do
          footnote $ "Command " <> show stepCmd
                  <> " returned HTTP " <> show (errHTTPCode err)
          failure

  -- (2) Reservation invariant (skipped for Voided/Refunded).
  case (expectedReserved stepModel, stepAvail) of
    (Just expected, Just (_, reserved)) -> reserved === expected
    (Just _,        Nothing)            -> do
      footnote "getInventoryAvailability returned Nothing after step"
      failure
    (Nothing, _) -> pure ()

  -- (3) Status invariant.
  case stepStatus of
    Just s  -> s === mStatus stepModel
    Nothing -> do
      footnote "getTransactionById returned Nothing after step"
      failure


-- --------------------------------------------------------------------------
-- Property and spec
-- --------------------------------------------------------------------------

prop_lifecycleInvariants :: Property
prop_lifecycleInvariants = withTests 500 . property $ do
  cmds    <- forAll genCmds
  outcome <- evalIO (runSequence cmds)
  case outcome of
    Left err -> do
      footnote $ "Internal interpreter error: HTTP " <> show (errHTTPCode err)
      failure
    Right steps -> for_ steps checkStep

spec :: Spec
spec = describe "Props.TxLifecycle" $ do
  it "reservation, status, and no-5xx invariants hold across command sequences" $
    hedgehog prop_lifecycleInvariants
```

Two notes:

The `repack` pattern mirrors your existing `fst . fst . fst . fst` chain but preserves the final TxStore so commands can be sequenced. If the effectful version in your flake disagrees with the `catchError` arity I used (`\_ e -> ...` assumes the CallStack-carrying signature), swap it for `tryError` or drop the leading argument; the rest is unchanged.

`expectedReserved` returns `Nothing` for Voided and Refunded because the pure interpreter behavior in those states isn't pinned down in the chase bundle. The check is skipped rather than guessed. Once you confirm whether the pure `runTransactionDbPure` releases or retains reservations on void (the IO interpreter keeps them; the service layer cancels stock pulls but the chase doesn't say the inventory reservation is released), tighten the model and you'll get coverage of those branches too. If you tighten and the test fails on a real-shift sequence, you've found the bug class this module was written to catch.

Next: authorization matrix is the cheapest of the remaining three and the highest signal for a regulated-substance POS. Say the word and I'll write it.