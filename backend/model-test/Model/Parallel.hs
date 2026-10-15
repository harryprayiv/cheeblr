{-# LANGUAGE ScopedTypeVariables #-}

-- Several puppets at once.
--
-- Each puppet is a cashier's device: it has its own registers and sales
-- and runs its own command sequence against its own copy of the model.
-- All puppets sell the same three menu items, so stock is the one thing
-- they contend for.
--
-- A puppet checks its own commands as the sequential test does, with one
-- allowance: an add that its model accepts may be refused by the backend
-- as insufficient inventory, because another puppet may hold or have sold
-- the units. A puppet's model never counts other puppets' units, so the
-- opposite (the model refuses, the backend accepts) is never allowed.
--
-- When every puppet has finished, the backend's stock is compared with
-- what all the models together say it must be, and every sale and
-- register is read back once more.
module Model.Parallel
  ( prop_puppetsAgree
  ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (SomeException, try)
import Control.Monad (forM, forM_, unless)
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import Data.String (fromString)
import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

import Model.Exec
import Model.Gen
import Model.Observe
import Model.Property (answersWithSale, commandName, registerOf, saleOf)
import Model.Step
import Model.Types

-- A command sequence for one puppet, generated against a model that
-- assumes every command is accepted as the model says. Commands that a
-- shrunk sequence leaves without their prerequisites are skipped when
-- the puppet runs (see runPuppet).
genScript :: Rules -> Int -> Gen [Cmd]
genScript rules size = do
  len <- Gen.int (Range.linear 1 size)
  go (initialModel rules) len
  where
    go :: Model Concrete -> Int -> Gen [Cmd]
    go _ 0 = pure []
    go model n = do
      cmd  <- genCmd rules model
      rest <- go (snd (step rules model cmd)) (n - 1)
      pure (cmd : rest)

actorOf :: Cmd -> Maybe Actor
actorOf cmd = case cmd of
  CreateRegister a      -> Just a
  OpenRegister a _ _    -> Just a
  CloseRegister a _ _   -> Just a
  StartSale a _         -> Just a
  AddItem a _ _ _       -> Just a
  RemoveItem a _ _      -> Just a
  AddPayment a _ _ _ _  -> Just a
  RemovePayment a _ _ _ -> Just a
  Clear a _             -> Just a
  Finalize a _          -> Just a
  Void a _              -> Just a
  Refund a _            -> Just a
  Audit                 -> Nothing

-- One puppet's verdict on one answer: the model afterwards, a label for
-- the coverage table, and the first thing that was wrong, if anything.
judge :: Rules -> Model Concrete -> Cmd -> Observed -> (Model Concrete, String, Maybe String)
judge rules model cmd observed
  | obsStatus observed == 401 && actorOf cmd /= Just Anonymous && actorOf cmd /= Nothing =
      (model, name <> " 401", Just "a signed-in session was refused (401)")
  | contended =
      (model, name <> " contended", firstWrong model)
  | obsStatus observed /= expected =
      ( model
      , name <> " " <> show (obsStatus observed)
      , Just ("HTTP status " <> show (obsStatus observed) <> ", the model expected " <> show expected)
      )
  | otherwise =
      (next, name <> " " <> show expected, firstWrong next)
  where
    name             = commandName cmd
    (expected, next) = step rules model cmd
    accepted         = expected == 200
    contended =
      case cmd of
        AddItem {} ->
          expected == 200
            && obsStatus observed == 400
            && "Insufficient inventory" `isInfixOf` obsBody observed
        _ -> False

    -- The sale and the register the command named, read back, against
    -- the model given. For a contended add that is the model before the
    -- command: the sale must be as it was.
    firstWrong after =
      case concat [bodySale after, readSale after, readRegister after, variance, streams] of
        []          -> Nothing
        (wrong : _) -> Just wrong

    differ what backend model' =
      [ what <> "\n  backend: " <> show backend <> "\n  model:   " <> show model'
      | backend /= model'
      ]

    bodySale after =
      case saleOf model cmd of
        Just slot | accepted && not contended && answersWithSale cmd ->
          differ "the sale in the response body" (obsBodySale observed)
            (saleView rules <$> Map.lookup slot (modelSales after))
        _ -> []

    readSale after =
      case saleOf model cmd of
        Just slot ->
          differ "the sale, read back after the command" (obsSale observed)
            (saleView rules <$> Map.lookup slot (modelSales after))
        Nothing -> []

    readRegister after =
      case registerOf model cmd of
        Just slot ->
          differ "the register, read back after the command" (obsRegister observed)
            (registerView <$> Map.lookup slot (modelRegisters after))
        Nothing -> []

    streams =
      case obsStream observed of
        Just report ->
          differ "events missing from the streams after the command" (srMissing report) []
            ++ differ "stream frames that did not decode, or streams that closed" (srBad report) []
        Nothing -> []

    variance =
      case cmd of
        CloseRegister _ reg counted | accepted ->
          differ "the variance answered at close" (obsVariance observed)
            (fmap (\r -> registerExpected r - counted) (Map.lookup reg (modelRegisters model)))
        _ -> []

data Puppet = Puppet
  { puppetRun    :: Run
  , puppetModel  :: Model Concrete
  , puppetLabels :: [String]
  , puppetFault  :: Maybe String
    -- ^ the first wrong answer, with the command that got it
  }

runPuppet :: Rules -> Run -> [Cmd] -> IO Puppet
runPuppet rules run = go (initialModel rules) []
  where
    go model labels [] = pure (Puppet run model (reverse labels) Nothing)
    go model labels (cmd : rest)
      | not (wellFormed model cmd) = go model labels rest
      | otherwise = do
          result <- try (executeWith False run cmd)
          case result of
            Left (e :: SomeException) ->
              pure (Puppet run model (reverse labels) (Just (show cmd <> ": " <> show e)))
            Right observed ->
              case judge rules model cmd observed of
                (next, label', Nothing) -> go next (label' : labels) rest
                (_, label', Just wrong) ->
                  pure
                    ( Puppet run model (reverse (label' : labels))
                        (Just (show cmd <> "\n" <> wrong <> "\n  response body: " <> obsBody observed))
                    )

-- Runs one puppet per script at the same time and waits for all of them.
runPuppets :: Rules -> Run -> [[Cmd]] -> IO [Puppet]
runPuppets rules base scripts = do
  slots <- forM scripts $ \script -> do
    run  <- forkRun base
    done <- newEmptyMVar
    _    <- forkIO (runPuppet rules run script >>= putMVar done)
    pure done
  mapM takeMVar slots

-- tests is the number of rounds, puppets how many run at once in a
-- round, size the most commands in one puppet's sequence.
prop_puppetsAgree :: Shared -> Int -> Int -> Int -> Property
prop_puppetsAgree shared tests puppets size =
  withTests (fromIntegral tests) . property $ do
    let rules = sharedRules shared
    scripts <- forAll (Gen.list (Range.singleton puppets) (genScript rules size))
    base    <- evalIO (newRun shared)
    results <- evalIO (runPuppets rules base scripts)

    forM_ (zip [0 :: Int ..] results) $ \(index, puppet) -> do
      forM_ (puppetLabels puppet) (label . fromString)
      forM_ (puppetFault puppet) $ \fault -> do
        annotate ("puppet " <> show index <> " got a wrong answer:\n" <> fault)
        failure

    -- Stock after all puppets have stopped. Each model holds the stock as
    -- its own sales left it; the sum of what every puppet took is what
    -- the backend must be short by.
    let models   = map puppetModel results
        initial  = rulesStock rules
        expected =
          Map.mapWithKey
            ( \sku start ->
                StockView
                  { stockOnHand   = start - sum [start - Map.findWithDefault start sku (modelOnHand m) | m <- models]
                  , stockReserved = sum [maybe 0 stockReserved (Map.lookup sku (stockView m)) | m <- models]
                  }
            )
            initial
    stock <- evalIO (readStock base)
    annotate "stock on hand and reserved after every puppet stopped (backend, then the models together)"
    stock === expected
    forM_ (Map.toList stock) $ \(sku, view) -> do
      annotate ("item " <> show sku <> " holds more reserved units than it has on hand: " <> show view)
      unless (stockReserved view <= stockOnHand view) failure

    -- Every sale and register of every puppet, read back once more.
    forM_ (zip [0 :: Int ..] results) $ \(index, puppet) -> do
      audit <- evalIO (executeWith False (puppetRun puppet) Audit)
      annotate ("puppet " <> show index <> ": every sale, read back at the end (backend, then model)")
      obsAllSales audit === Just (Map.map (saleView rules) (modelSales (puppetModel puppet)))
      annotate ("puppet " <> show index <> ": every register, read back at the end (backend, then model)")
      obsAllRegisters audit === Just (Map.map registerView (modelRegisters (puppetModel puppet)))

    evalIO (endRun base)