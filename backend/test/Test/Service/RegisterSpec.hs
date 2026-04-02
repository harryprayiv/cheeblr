{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE NamedFieldPuns     #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE TypeApplications   #-}

module Test.Service.RegisterSpec (spec) where

import Control.Monad              (void)
import Data.IORef                  (newIORef, readIORef)
import qualified Data.Map.Strict  as Map
import Data.Time                   (UTCTime)
import Data.UUID                   (UUID)
import Effectful                   (Eff, IOE, runEff)
import Effectful.Error.Static      (Error, runErrorNoCallStack)
import Servant                     (ServerError (..))
import Test.Hspec
import Types.Location (LocationId (..))

import API.Transaction
  ( CloseRegisterRequest (..)
  , CloseRegisterResult (..)
  , OpenRegisterRequest (..)
  , Register (..)
  )
import Effect.Clock                (Clock, runClockPure)
import Effect.EventEmitter
import Effect.RegisterDb
import qualified Service.Register as Svc
import Types.Events.Domain
import Types.Events.Register

regUUID, empUUID, locUUID :: UUID
regUUID = read "11111111-1111-1111-1111-111111111111"
empUUID = read "22222222-2222-2222-2222-222222222222"
locUUID = read "33333333-3333-3333-3333-333333333333"

testTime :: UTCTime
testTime = read "2024-06-15 10:00:00 UTC"

closedReg :: Register
closedReg = Register
  { registerId                   = regUUID
  , registerName                 = "Test Register"
  , registerLocationId = LocationId locUUID
  , registerIsOpen               = False
  , registerCurrentDrawerAmount  = 0
  , registerExpectedDrawerAmount = 0
  , registerOpenedAt             = Nothing
  , registerOpenedBy             = Nothing
  , registerLastTransactionTime  = Nothing
  }

openReg :: Register
openReg = closedReg
  { registerIsOpen               = True
  , registerCurrentDrawerAmount  = 50000
  , registerExpectedDrawerAmount = 50000
  , registerOpenedBy             = Just empUUID
  }

openReq :: OpenRegisterRequest
openReq = OpenRegisterRequest
  { openRegisterEmployeeId   = empUUID
  , openRegisterStartingCash = 50000
  }

closeReq :: CloseRegisterRequest
closeReq = CloseRegisterRequest
  { closeRegisterEmployeeId  = empUUID
  , closeRegisterCountedCash = 48000
  }

storeWith :: Register -> RegStore
storeWith reg = RegStore (Map.singleton regUUID reg)

-- Effect stack matches service function constraints:
-- RegisterDb, EventEmitter, Clock, Error ServerError, IOE
type TestEffs =
  '[ RegisterDb
   , Clock
   , EventEmitter
   , Error ServerError
   , IOE
   ]

runTest :: RegStore -> Eff TestEffs a -> IO (Either ServerError a)
runTest store action =
  fmap (fmap fst) $
  runEff
  . runErrorNoCallStack @ServerError
  . runEventEmitterNoop
  . runClockPure testTime
  . runRegisterDbPure store
  $ action

runTestWithEvents
  :: RegStore
  -> Eff TestEffs a
  -> IO (Either ServerError a, [DomainEvent])
runTestWithEvents store action = do
  ref <- newIORef []
  result <-
    fmap (fmap fst) $
    runEff
    . runErrorNoCallStack @ServerError
    . runEventEmitterCollect ref
    . runClockPure testTime
    . runRegisterDbPure store
    $ action
  evts <- reverse <$> readIORef ref
  pure (result, evts)

shouldSucceed :: IO (Either ServerError a) -> IO a
shouldSucceed io = do
  result <- io
  case result of
    Left err -> do
      expectationFailure $ "Expected success but got HTTP " <> show (errHTTPCode err)
      error "unreachable"
    Right a -> pure a

shouldFailWith :: Int -> IO (Either ServerError a) -> IO ()
shouldFailWith code io = do
  result <- io
  case result of
    Left err -> errHTTPCode err `shouldBe` code
    Right _  -> expectationFailure $ "Expected HTTP " <> show code <> " but got success"

spec :: Spec
spec = describe "Service.Register (pure interpreter)" $ do

  describe "openRegister — state machine guards" $ do
    it "succeeds on a closed register" $ do
      reg <- shouldSucceed $ runTest (storeWith closedReg) (Svc.openRegister regUUID openReq)
      registerIsOpen reg `shouldBe` True

    it "sets currentDrawerAmount to starting cash" $ do
      reg <- shouldSucceed $ runTest (storeWith closedReg) (Svc.openRegister regUUID openReq)
      registerCurrentDrawerAmount reg `shouldBe` 50000

    it "sets expectedDrawerAmount to starting cash" $ do
      reg <- shouldSucceed $ runTest (storeWith closedReg) (Svc.openRegister regUUID openReq)
      registerExpectedDrawerAmount reg `shouldBe` 50000

    it "records openedBy employee" $ do
      reg <- shouldSucceed $ runTest (storeWith closedReg) (Svc.openRegister regUUID openReq)
      registerOpenedBy reg `shouldBe` Just empUUID

    it "rejects opening an already-open register with 409" $
      shouldFailWith 409 $ runTest (storeWith openReg) (Svc.openRegister regUUID openReq)

    it "returns 404 for a non-existent register" $
      shouldFailWith 404 $ runTest emptyRegStore (Svc.openRegister regUUID openReq)

  describe "closeRegister — state machine guards" $ do
    it "succeeds on an open register" $ do
      result <- shouldSucceed $ runTest (storeWith openReg) (Svc.closeRegister regUUID closeReq)
      registerIsOpen (closeRegisterResultRegister result) `shouldBe` False

    it "calculates positive variance when counted cash is short" $ do
      result <- shouldSucceed $ runTest (storeWith openReg) (Svc.closeRegister regUUID closeReq)
      closeRegisterResultVariance result `shouldBe` 2000

    it "calculates zero variance when count is exact" $ do
      let exactReq = closeReq { closeRegisterCountedCash = 50000 }
      result <- shouldSucceed $ runTest (storeWith openReg) (Svc.closeRegister regUUID exactReq)
      closeRegisterResultVariance result `shouldBe` 0

    it "calculates negative variance when count is over" $ do
      let overReq = closeReq { closeRegisterCountedCash = 52000 }
      result <- shouldSucceed $ runTest (storeWith openReg) (Svc.closeRegister regUUID overReq)
      closeRegisterResultVariance result `shouldBe` (-2000)

    it "stores counted cash in currentDrawerAmount" $ do
      result <- shouldSucceed $ runTest (storeWith openReg) (Svc.closeRegister regUUID closeReq)
      registerCurrentDrawerAmount (closeRegisterResultRegister result) `shouldBe` 48000

    it "rejects closing an already-closed register with 409" $
      shouldFailWith 409 $ runTest (storeWith closedReg) (Svc.closeRegister regUUID closeReq)

    it "returns 404 for a non-existent register" $
      shouldFailWith 404 $ runTest emptyRegStore (Svc.closeRegister regUUID closeReq)

  describe "round-trip: open then close" $ do
    it "open then close yields closed register" $ do
      let action = do
            _ <- Svc.openRegister regUUID openReq
            Svc.closeRegister regUUID closeReq
      result <- shouldSucceed $ runTest (storeWith closedReg) action
      registerIsOpen (closeRegisterResultRegister result) `shouldBe` False

    it "cannot open a second time after open" $ do
      let action = do
            _ <- Svc.openRegister regUUID openReq
            Svc.openRegister regUUID openReq
      shouldFailWith 409 $ runTest (storeWith closedReg) action

    it "cannot close twice" $ do
      let action = do
            _ <- Svc.openRegister regUUID openReq
            _ <- Svc.closeRegister regUUID closeReq
            Svc.closeRegister regUUID closeReq
      shouldFailWith 409 $ runTest (storeWith closedReg) action

    it "open then close then open again succeeds" $ do
      let action = do
            _ <- Svc.openRegister regUUID openReq
            _ <- Svc.closeRegister regUUID closeReq
            Svc.openRegister regUUID openReq
      reg <- shouldSucceed $ runTest (storeWith closedReg) action
      registerIsOpen reg `shouldBe` True
      void $ pure reg

  describe "event emission" $ do

    it "openRegister emits RegisterOpened on success" $ do
      (result, evts) <- runTestWithEvents (storeWith closedReg) (Svc.openRegister regUUID openReq)
      result `shouldSatisfy` either (const False) (const True)
      case evts of
        [RegisterEvt (RegisterOpened { reRegId, reEmpId, reStartingCash })] -> do
          reRegId        `shouldBe` regUUID
          reEmpId        `shouldBe` empUUID
          reStartingCash `shouldBe` 50000
        _ -> expectationFailure $ "Expected [RegisterOpened], got: " <> show (length evts) <> " events"

    it "openRegister emits no events on rejection (already open)" $ do
      (_, evts) <- runTestWithEvents (storeWith openReg) (Svc.openRegister regUUID openReq)
      evts `shouldBe` []

    it "openRegister emits no events when register not found" $ do
      (_, evts) <- runTestWithEvents emptyRegStore (Svc.openRegister regUUID openReq)
      evts `shouldBe` []

    it "closeRegister emits RegisterClosed on success" $ do
      (result, evts) <- runTestWithEvents (storeWith openReg) (Svc.closeRegister regUUID closeReq)
      result `shouldSatisfy` either (const False) (const True)
      case evts of
        [RegisterEvt (RegisterClosed { reRegId, reVariance })] -> do
          reRegId    `shouldBe` regUUID
          reVariance `shouldBe` 2000
        _ -> expectationFailure $ "Expected [RegisterClosed], got: " <> show (length evts) <> " events"

    it "closeRegister emits no events on rejection (already closed)" $ do
      (_, evts) <- runTestWithEvents (storeWith closedReg) (Svc.closeRegister regUUID closeReq)
      evts `shouldBe` []

    it "open then close emits two events in order" $ do
      (_, evts) <- runTestWithEvents (storeWith closedReg) $ do
        _ <- Svc.openRegister regUUID openReq
        Svc.closeRegister regUUID closeReq
      case evts of
        [RegisterEvt (RegisterOpened {}), RegisterEvt (RegisterClosed {})] -> pure ()
        _ -> expectationFailure $ "Expected [RegisterOpened, RegisterClosed], got: " <> show (length evts) <> " events"