-- Which commands make sense in a given model state, and how to generate
-- them.
--
-- The generator aims at sequences that get somewhere: most commands are
-- sent by the actor who is allowed to send them, on sales that are still
-- open. A share of every kind is sent by the wrong actor, on a finished
-- sale, or with a bad quantity or amount, so that refusals are checked as
-- often as acceptances.
module Model.Gen
  ( wellFormed
  , genCmd
  , maxRegisters
  , maxSales
  ) where

import qualified Data.Map.Strict as Map
import Hedgehog (Gen)
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

import Model.Step (isOpenStatus, salePaid, saleTotals)
import Model.Types

maxRegisters :: Int
maxRegisters = 3

maxSales :: Int
maxSales = 6

-- Whether a command refers only to things the model has. Hedgehog drops a
-- command that fails this when it removes earlier commands while
-- shrinking.
wellFormed :: Model v -> Cmd -> Bool
wellFormed model cmd = case cmd of
  CreateRegister _          -> Map.size (modelRegisters model) < maxRegisters
  OpenRegister _ reg _      -> hasRegister reg
  CloseRegister _ reg _     -> hasRegister reg
  StartSale _ reg           -> hasRegister reg && Map.size (modelSales model) < maxSales
  AddItem _ sale sku _      -> hasSale sale && Map.member sku (modelOnHand model)
  RemoveItem _ sale sku     -> maybe False (Map.member sku . saleLines) (lookupSale sale)
  AddPayment _ sale _ _ _   -> hasSale sale
  RemovePayment _ sale m a  -> maybe False (elem (m, a) . salePayments) (lookupSale sale)
  Clear _ sale              -> hasSale sale
  Finalize _ sale           -> hasSale sale
  Void _ sale               -> hasSale sale
  Refund _ sale             -> hasSale sale
  Audit                     -> True
  where
    hasRegister reg = Map.member reg (modelRegisters model)
    hasSale sale    = Map.member sale (modelSales model)
    lookupSale sale = Map.lookup sale (modelSales model)

anyActor :: Gen Actor
anyActor = Gen.element [minBound .. maxBound]

-- Usually the given actor, sometimes the admin, sometimes anyone.
mostly :: Actor -> Gen Actor
mostly actor = Gen.frequency [(7, pure actor), (1, pure Admin), (2, anyActor)]

staff :: Gen Actor
staff =
  Gen.frequency
    [ (4, pure CashierA)
    , (3, pure CashierB)
    , (2, pure Admin)
    , (1, pure Customer)
    , (1, pure Anonymous)
    ]

cashAmount :: Gen Int
cashAmount = Gen.element [0, 5000, 10000, 20000]

genCmd :: Rules -> Model v -> Gen Cmd
genCmd rules model =
  Gen.frequency $
    concat
      [ always
      , registerCmds
      , startCmds
      , saleCmds
      , lineCmds
      , paymentCmds
      , payableCmds
      , readyCmds
      , completedCmds
      ]
  where
    registers = Map.keys (modelRegisters model)
    sales     = Map.toList (modelSales model)
    skus      = Map.keys (modelOnHand model)

    remainingOf sale = total - salePaid sale
      where
        (_, _, total) = saleTotals rules sale

    inProgress = [entry | entry@(_, sale) <- sales, saleStatus sale == InProgress]

    -- Sales that still owe money, sales that can be completed, and sales
    -- that were completed. The three lists below steer sequences through
    -- a whole sale, which random choice alone seldom does.
    payable   = [entry | entry@(_, sale) <- inProgress, remainingOf sale > 0]
    ready     =
      [ entry
      | entry@(_, sale) <- inProgress
      , not (Map.null (saleLines sale))
      , remainingOf sale <= 0
      ]
    completed = [entry | entry@(_, sale) <- sales, saleStatus sale == Completed]

    always =
      [(1, pure Audit)]
        ++ [ (if null registers then 10 else 1, CreateRegister <$> mostly Admin)
           | length registers < maxRegisters
           ]

    registerCmds
      | null registers = []
      | otherwise =
          [ (2, OpenRegister <$> staff <*> Gen.element registers <*> cashAmount)
          , (1, CloseRegister <$> staff <*> Gen.element registers <*> cashAmount)
          ]

    startCmds
      | null registers || length sales >= maxSales = []
      | otherwise =
          [(if null sales then 10 else 3, StartSale <$> staff <*> Gen.element registers)]

    -- A sale to act on: usually an open one, sometimes any.
    pickSale = case filter (isOpenStatus . saleStatus . snd) sales of
      []       -> Gen.element sales
      openOnes -> Gen.frequency [(5, Gen.element openOnes), (1, Gen.element sales)]

    saleCmds
      | null sales = []
      | otherwise =
          [ (10, addItem)
          , (1, onPicked Clear)
          , (2, onPicked Finalize)
          , (1, voidOrRefund Void)
          , (1, voidOrRefund Refund)
          , (2, anyPayment)
          ]

    onPicked make = do
      (ix, sale) <- pickSale
      actor <- mostly (saleOwner sale)
      pure (make actor ix)

    voidOrRefund make = do
      (ix, _) <- Gen.element sales
      actor <- Gen.frequency [(6, pure Admin), (2, anyActor)]
      pure (make actor ix)

    addItem = do
      (ix, sale) <- pickSale
      actor <- mostly (saleOwner sale)
      sku <- Gen.element skus
      quantity <-
        Gen.frequency
          [ (6, pure 1)
          , (2, Gen.int (Range.linear 2 4))
          , (1, pure 0)
          , (1, pure (-1))
          ]
      pure (AddItem actor ix sku quantity)

    lineCmds =
      case [(ix, sale, sku) | (ix, sale) <- sales, sku <- Map.keys (saleLines sale)] of
        []    -> []
        lines' ->
          [ ( 2
            , do
                (ix, sale, sku) <- Gen.element lines'
                actor <- mostly (saleOwner sale)
                pure (RemoveItem actor ix sku)
            )
          ]

    -- A payment on any sale, with amounts that are refused as often as
    -- accepted.
    anyPayment = do
      (ix, sale) <- pickSale
      actor <- mostly (saleOwner sale)
      method <- Gen.element [minBound .. maxBound]
      (amount, tendered) <-
        Gen.element
          [ (100, Nothing)
          , (100, Just 2000)
          , (0, Nothing)
          , (-500, Nothing)
          , (500, Just 400)
          ]
      pure (AddPayment actor ix method amount tendered)

    paymentCmds =
      case [(ix, sale, payment) | (ix, sale) <- sales, payment <- salePayments sale] of
        []       -> []
        payments ->
          [ ( 2
            , do
                (ix, sale, (method, amount)) <- Gen.element payments
                actor <- mostly (saleOwner sale)
                pure (RemovePayment actor ix method amount)
            )
          ]

    -- Pay what a sale owes: all of it, all of it with change due, or half.
    payableCmds
      | null payable = []
      | otherwise =
          [ ( 8
            , do
                (ix, sale) <- Gen.element payable
                actor <- mostly (saleOwner sale)
                method <- Gen.element [minBound .. maxBound]
                let remaining = remainingOf sale
                (amount, tendered) <-
                  Gen.frequency $
                    [ (6, pure (remaining, Nothing))
                    , (2, pure (remaining, Just (remaining + 500)))
                    ]
                      ++ [(3, pure (remaining `div` 2, Nothing)) | remaining > 1]
                pure (AddPayment actor ix method amount tendered)
            )
          ]

    readyCmds
      | null ready = []
      | otherwise =
          [ ( 8
            , do
                (ix, sale) <- Gen.element ready
                actor <- mostly (saleOwner sale)
                pure (Finalize actor ix)
            )
          ]

    completedCmds
      | null completed = []
      | otherwise =
          [ (3, onCompleted Refund)
          , (2, onCompleted Void)
          ]

    onCompleted make = do
      (ix, _) <- Gen.element completed
      actor <- Gen.frequency [(6, pure Admin), (1, anyActor)]
      pure (make actor ix)
