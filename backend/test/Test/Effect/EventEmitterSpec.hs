{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.Effect.EventEmitterSpec (spec) where

import Data.IORef (newIORef, readIORef)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Effectful (runEff)
import Test.Hspec

import Effect.EventEmitter
import Types.Auth (UserRole (..))
import Types.Events
import Types.Events.Domain

testUUID :: UUID
testUUID = read "11111111-1111-1111-1111-111111111111"

testTime :: UTCTime
testTime = read "2024-06-15 10:00:00 UTC"

evt1 :: DomainEvent
evt1 =
  SessionEvt $
    SessionCreated
      { sesUserId = testUUID
      , sesRole = Cashier
      , sesTimestamp = testTime
      }

evt2 :: DomainEvent
evt2 =
  SessionEvt $
    SessionExpired
      { sesUserId = testUUID
      , sesTimestamp = testTime
      }

evt3 :: DomainEvent
evt3 =
  SessionEvt $
    SessionRevoked
      { sesUserId = testUUID
      , sesActorId = testUUID
      , sesTimestamp = testTime
      }

spec :: Spec
spec = describe "Effect.EventEmitter" $ do
  describe "runEventEmitterNoop" $ do
    it "discards events without error" $ do
      runEff $ runEventEmitterNoop $ do
        emit evt1
        emit evt2
      pure ()

    it "returns the action value unchanged" $ do
      result <- runEff $ runEventEmitterNoop $ do
        emit evt1
        pure (42 :: Int)
      result `shouldBe` 42

    it "works with zero emissions" $ do
      result <- runEff $ runEventEmitterNoop $ pure ("ok" :: String)
      result `shouldBe` "ok"

  describe "runEventEmitterCollect" $ do
    it "collects nothing when no events emitted" $ do
      ref <- newIORef []
      _ <- runEff $ runEventEmitterCollect ref $ pure ()
      evts <- readIORef ref
      evts `shouldBe` []

    it "collects a single event" $ do
      ref <- newIORef []
      runEff $ runEventEmitterCollect ref $ emit evt1
      evts <- reverse <$> readIORef ref
      length evts `shouldBe` 1

    it "captures events in emission order" $ do
      ref <- newIORef []
      runEff $ runEventEmitterCollect ref $ do
        emit evt1
        emit evt2
        emit evt3
      evts <- reverse <$> readIORef ref
      evts `shouldBe` [evt1, evt2, evt3]

    it "returns the action value alongside collected events" $ do
      ref <- newIORef []
      result <- runEff $ runEventEmitterCollect ref $ do
        emit evt1
        pure (99 :: Int)
      result `shouldBe` 99
      evts <- readIORef ref
      length evts `shouldBe` 1

    it "accumulates across multiple emit calls" $ do
      ref <- newIORef []
      runEff $ runEventEmitterCollect ref $ do
        emit evt1
        emit evt2
        emit evt3
      evts <- readIORef ref
      length evts `shouldBe` 3
