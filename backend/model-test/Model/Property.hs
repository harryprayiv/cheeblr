{-# LANGUAGE KindSignatures #-}

-- The property: any generated sequence of commands is answered by the
-- backend the way the model says, and the state read back after every
-- command is the model's state.
module Model.Property
  ( prop_backendMatchesModel
  , saleOf
  , registerOf
  , answersWithSale
  , commandName
  ) where

import Control.Exception (throwIO)
import Control.Monad (forM_, when)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Kind (Type)
import Data.String (fromString)
import qualified Data.Map.Strict as Map
import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

import Model.Exec
import Model.Gen
import Model.Step
import Model.Types

-- A command as Hedgehog's input type. It holds no backend ids, so the
-- two instances Hedgehog asks for have nothing to do.
newtype Step (v :: Type -> Type) = Step Cmd
  deriving (Eq, Show)

instance FunctorB Step where
  bmap _ (Step cmd) = Step cmd

instance TraversableB Step where
  btraverse _ (Step cmd) = pure (Step cmd)

-- The run is read from a reference because it does not exist yet when
-- the commands are generated: see prop_backendMatchesModel.
command :: Rules -> IORef (Maybe Run) -> Command Gen (PropertyT IO) Model
command rules runRef =
  Command
    (\model -> Just (Step <$> genCmd rules model))
    ( \(Step cmd) -> evalIO $ do
        current <- readIORef runRef
        case current of
          Just run -> execute run cmd
          Nothing  -> throwIO (userError "model test: a command ran before its run was set up")
    )
    [ Require (\model (Step cmd) -> wellFormed model cmd)
    , Update (\model (Step cmd) _ -> snd (step rules model cmd))
    , Ensure (\before after (Step cmd) observed -> verify rules before after cmd observed)
    ]

-- The sale slot and the register slot a command names.
saleOf :: Model v -> Cmd -> Maybe Int
saleOf before cmd = case cmd of
  StartSale {}             -> Just (Map.size (modelSales before))
  AddItem _ sale _ _       -> Just sale
  RemoveItem _ sale _      -> Just sale
  AddPayment _ sale _ _ _  -> Just sale
  RemovePayment _ sale _ _ -> Just sale
  Clear _ sale             -> Just sale
  Finalize _ sale          -> Just sale
  Void _ sale              -> Just sale
  Refund _ sale            -> Just sale
  _                        -> Nothing

registerOf :: Model v -> Cmd -> Maybe Int
registerOf before cmd = case cmd of
  CreateRegister {}     -> Just (Map.size (modelRegisters before))
  OpenRegister _ reg _  -> Just reg
  CloseRegister _ reg _ -> Just reg
  _                     -> Nothing

commandName :: Cmd -> String
commandName = takeWhile (/= ' ') . show

answersWithSale :: Cmd -> Bool
answersWithSale cmd = case cmd of
  Refund {} -> False
  _         -> True

-- One comparison between the backend and the model. Nothing is written
-- to the report unless it fails; then the report names the check and the
-- command, and shows the difference with the backend's value on the "-"
-- lines and the model's on the "+" lines.
same :: (Eq a, Show a) => Cmd -> Observed -> String -> a -> a -> Test ()
same cmd observed what backend model =
  when (backend /= model) $ do
    annotate ("failed check:  " <> what)
    annotate ("command:       " <> show cmd)
    annotate ("HTTP status:   " <> show (obsStatus observed))
    annotate ("response body: " <> obsBody observed)
    backend === model

verify :: Rules -> Model Concrete -> Model Concrete -> Cmd -> Observed -> Test ()
verify rules before after cmd observed = do
  let (expected, _) = step rules before cmd
      accepted      = expected == 200
      expectedSale slot     = saleView rules <$> Map.lookup slot (modelSales after)
      expectedRegister slot = registerView <$> Map.lookup slot (modelRegisters after)
      expect :: (Eq a, Show a) => String -> a -> a -> Test ()
      expect = same cmd observed

  -- For the coverage table printed after a passing run: which commands
  -- were sent and how the model expected them to be answered.
  label (fromString (commandName cmd <> " " <> show expected))

  expect "the HTTP status of the answer" (obsStatus observed) expected

  -- The sale the command named: in the response body when the command was
  -- accepted, and read back afterwards whether it was accepted or not. A
  -- refused command must leave the sale as it was.
  forM_ (saleOf before cmd) $ \slot -> do
    when (accepted && answersWithSale cmd) $
      expect "the sale in the response body" (obsBodySale observed) (expectedSale slot)
    expect "the sale, read back after the command" (obsSale observed) (expectedSale slot)

  forM_ (registerOf before cmd) $ \slot ->
    expect "the register, read back after the command" (obsRegister observed) (expectedRegister slot)

  case cmd of
    CloseRegister _ reg counted
      | accepted ->
          expect
            "the variance answered at close"
            (obsVariance observed)
            (fmap (\register -> registerExpected register - counted) (Map.lookup reg (modelRegisters before)))
    _ -> pure ()

  -- Stock after every command.
  expect "stock on hand and reserved, per menu item" (obsStock observed) (stockView after)

  -- Audit: every sale and register of the sequence.
  forM_ (obsAllSales observed) $ \sales ->
    expect "audit: every sale of the sequence" sales (Map.map (saleView rules) (modelSales after))
  forM_ (obsAllRegisters observed) $ \registers ->
    expect "audit: every register of the sequence" registers (Map.map registerView (modelRegisters after))

-- tests is the number of sequences, size the most commands in one.
--
-- Hedgehog runs everything after forAll again for every shrink attempt,
-- and nothing before it. The run (new menu items, empty slot lists) is
-- therefore set up after forAll, so that every attempt starts clean. The
-- menu items of an attempt are removed only when it passes.
prop_backendMatchesModel :: Shared -> Int -> Int -> Property
prop_backendMatchesModel shared tests size =
  withTests (fromIntegral tests) . property $ do
    let rules = sharedRules shared
    runRef <- evalIO (newIORef Nothing)
    actions <-
      forAll $
        Gen.sequential (Range.linear 1 size) (initialModel rules) [command rules runRef]
    run <- evalIO (newRun shared)
    evalIO (writeIORef runRef (Just run))
    executeSequential (initialModel rules) actions
    evalIO (endRun run)