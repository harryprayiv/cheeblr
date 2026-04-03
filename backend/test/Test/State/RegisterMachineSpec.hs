{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.State.RegisterMachineSpec (spec) where

import Data.UUID (UUID)
import Test.Hspec

import API.Transaction (Register (..))
import State.RegisterMachine
import Types.Location (LocationId (..))

-- ── fixtures ──────────────────────────────────────────────────────────────────

empUUID :: UUID
empUUID = read "11111111-1111-1111-1111-111111111111"

closedReg :: Register
closedReg =
  Register
    { registerId = read "22222222-2222-2222-2222-222222222222"
    , registerName = "Test Register"
    , registerLocationId = LocationId (read "33333333-3333-3333-3333-333333333333")
    , registerIsOpen = False
    , registerCurrentDrawerAmount = 0
    , registerExpectedDrawerAmount = 0
    , registerOpenedAt = Nothing
    , registerOpenedBy = Nothing
    , registerLastTransactionTime = Nothing
    }

openReg :: Register
openReg =
  closedReg
    { registerIsOpen = True
    , registerCurrentDrawerAmount = 50000
    , registerExpectedDrawerAmount = 50000
    , registerOpenedBy = Just empUUID
    }

-- ── helpers ───────────────────────────────────────────────────────────────────

-- GADTs pragma makes the singleton pattern match sound.
vertexOf :: SomeRegState -> RegVertex
vertexOf (SomeRegState sv _) = case sv of
  SRegClosed -> RegClosed
  SRegOpen -> RegOpen

-- Use a nested case rather than two top-level GADT equations so that
-- GHC does not emit -Wgadt-mono-local-binds even without the pragma.
regOf :: SomeRegState -> Register
regOf (SomeRegState _ st) = case st of
  ClosedState r -> r
  OpenState r -> r

-- ── spec ──────────────────────────────────────────────────────────────────────

spec :: Spec
spec = describe "State.RegisterMachine" $ do
  describe "fromRegister / toSomeRegState" $ do
    it "closed register produces RegClosed vertex" $
      vertexOf (fromRegister closedReg) `shouldBe` RegClosed

    it "open register produces RegOpen vertex" $
      vertexOf (fromRegister openReg) `shouldBe` RegOpen

    it "closed register carry-through" $
      registerIsOpen (regOf (fromRegister closedReg)) `shouldBe` False

    it "open register carry-through" $
      registerIsOpen (regOf (fromRegister openReg)) `shouldBe` True

  describe "OpenRegCmd" $ do
    it "transitions a closed register to RegOpen" $ do
      let (_, next) = runRegCommand (fromRegister closedReg) (OpenRegCmd empUUID 50000)
      vertexOf next `shouldBe` RegOpen

    it "emits RegOpened event" $ do
      let (evt, _) = runRegCommand (fromRegister closedReg) (OpenRegCmd empUUID 50000)
      case evt of
        RegOpened _ -> pure ()
        _ -> expectationFailure $ "Expected RegOpened, got: " ++ show evt

    it "sets registerIsOpen = True in event payload" $ do
      let (evt, _) = runRegCommand (fromRegister closedReg) (OpenRegCmd empUUID 50000)
      case evt of
        RegOpened r -> registerIsOpen r `shouldBe` True
        _ -> expectationFailure $ "Expected RegOpened, got: " ++ show evt

    it "sets currentDrawerAmount to starting cash" $ do
      let (evt, _) = runRegCommand (fromRegister closedReg) (OpenRegCmd empUUID 50000)
      case evt of
        RegOpened r -> registerCurrentDrawerAmount r `shouldBe` 50000
        _ -> expectationFailure $ "Expected RegOpened, got: " ++ show evt

    it "sets expectedDrawerAmount to starting cash" $ do
      let (evt, _) = runRegCommand (fromRegister closedReg) (OpenRegCmd empUUID 50000)
      case evt of
        RegOpened r -> registerExpectedDrawerAmount r `shouldBe` 50000
        _ -> expectationFailure $ "Expected RegOpened, got: " ++ show evt

    it "records openedBy employee" $ do
      let (evt, _) = runRegCommand (fromRegister closedReg) (OpenRegCmd empUUID 50000)
      case evt of
        RegOpened r -> registerOpenedBy r `shouldBe` Just empUUID
        _ -> expectationFailure $ "Expected RegOpened, got: " ++ show evt

    it "rejects OpenRegCmd on an already-open register" $ do
      let (evt, _) = runRegCommand (fromRegister openReg) (OpenRegCmd empUUID 30000)
      case evt of
        InvalidRegCommand _ -> pure ()
        _ -> expectationFailure $ "Expected InvalidRegCommand, got: " ++ show evt

    it "stays at RegOpen after a rejected open command" $ do
      let (_, next) = runRegCommand (fromRegister openReg) (OpenRegCmd empUUID 30000)
      vertexOf next `shouldBe` RegOpen

  describe "CloseRegCmd — variance calculation" $ do
    -- Each test uses a `case` expression so the pattern match is exhaustive.

    it "variance is positive when counted cash is short (48000 vs expected 50000)" $ do
      let (evt, _) = runRegCommand (fromRegister openReg) (CloseRegCmd empUUID 48000)
      case evt of
        RegWasClosed _ variance -> variance `shouldBe` 2000
        _ -> expectationFailure $ "Expected RegWasClosed, got: " ++ show evt

    it "variance is zero when count is exact (50000 vs expected 50000)" $ do
      let (evt, _) = runRegCommand (fromRegister openReg) (CloseRegCmd empUUID 50000)
      case evt of
        RegWasClosed _ variance -> variance `shouldBe` 0
        _ -> expectationFailure $ "Expected RegWasClosed, got: " ++ show evt

    it "variance is negative when counted cash is over (52000 vs expected 50000)" $ do
      let (evt, _) = runRegCommand (fromRegister openReg) (CloseRegCmd empUUID 52000)
      case evt of
        RegWasClosed _ variance -> variance `shouldBe` (-2000)
        _ -> expectationFailure $ "Expected RegWasClosed, got: " ++ show evt

    it "register is marked closed in the event payload" $ do
      let (evt, _) = runRegCommand (fromRegister openReg) (CloseRegCmd empUUID 48000)
      case evt of
        RegWasClosed r _ -> registerIsOpen r `shouldBe` False
        _ -> expectationFailure $ "Expected RegWasClosed, got: " ++ show evt

    it "counted cash is stored in currentDrawerAmount" $ do
      let (evt, _) = runRegCommand (fromRegister openReg) (CloseRegCmd empUUID 48000)
      case evt of
        RegWasClosed r _ -> registerCurrentDrawerAmount r `shouldBe` 48000
        _ -> expectationFailure $ "Expected RegWasClosed, got: " ++ show evt

    it "transitions to RegClosed vertex" $ do
      let (_, next) = runRegCommand (fromRegister openReg) (CloseRegCmd empUUID 50000)
      vertexOf next `shouldBe` RegClosed

    it "rejects CloseRegCmd on an already-closed register" $ do
      let (evt, _) = runRegCommand (fromRegister closedReg) (CloseRegCmd empUUID 0)
      case evt of
        InvalidRegCommand _ -> pure ()
        _ -> expectationFailure $ "Expected InvalidRegCommand, got: " ++ show evt

    it "stays at RegClosed after a rejected close command" $ do
      let (_, next) = runRegCommand (fromRegister closedReg) (CloseRegCmd empUUID 0)
      vertexOf next `shouldBe` RegClosed

  describe "round-trip: open then close" $ do
    it "open → close preserves register id" $ do
      let (openEvt, opened) = runRegCommand (fromRegister closedReg) (OpenRegCmd empUUID 50000)
      case openEvt of
        RegOpened _ -> do
          let (closeEvt, _) = runRegCommand opened (CloseRegCmd empUUID 50000)
          case closeEvt of
            RegWasClosed r _ -> registerId r `shouldBe` registerId closedReg
            _ -> expectationFailure $ "Expected RegWasClosed, got: " ++ show closeEvt
        _ -> expectationFailure $ "Expected RegOpened, got: " ++ show openEvt

    it "open → close yields RegClosed final vertex" $ do
      let (_, opened) = runRegCommand (fromRegister closedReg) (OpenRegCmd empUUID 50000)
      let (_, closed) = runRegCommand opened (CloseRegCmd empUUID 50000)
      vertexOf closed `shouldBe` RegClosed
