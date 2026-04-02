{-# LANGUAGE OverloadedStrings #-}

module Test.Infrastructure.AvailabilityRelaySpec (spec) where

import Control.Concurrent.STM
import qualified Data.Map.Strict as Map
import Data.Maybe      (isJust)
import Data.Time       (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.UUID       (UUID)
import qualified Data.Vector as V
import Test.Hspec

import Infrastructure.AvailabilityRelay  (updateAvailability)
import Infrastructure.AvailabilityState
import Types.Auth                        (UserRole (..))
import Types.Events.Domain              (DomainEvent (..))
import Types.Events.Inventory           (InventoryEvent (..))
import Types.Events.Register            (RegisterEvent (..))
import Types.Events.Session             (SessionEvent (..))
import Types.Events.Transaction         (TransactionEvent (..))
import Types.Inventory
import Types.Public.AvailableItem
import Types.Transaction

testTime :: UTCTime
testTime = UTCTime (fromGregorian 2024 1 1) 0

testSku :: UUID
testSku = read "00000000-0000-0000-0000-000000000001"

testLocId :: PublicLocationId
testLocId = PublicLocationId (read "00000000-0000-0000-0000-000000000002")

testActorId :: UUID
testActorId = read "00000000-0000-0000-0000-000000000003"

txUUID :: UUID
txUUID = read "00000000-0000-0000-0000-000000000004"

itemUUID :: UUID
itemUUID = read "00000000-0000-0000-0000-000000000005"

regUUID :: UUID
regUUID = read "00000000-0000-0000-0000-000000000006"

userUUID :: UUID
userUUID = read "00000000-0000-0000-0000-000000000007"

testItemQty :: Int
testItemQty = 10

testMenuItem :: MenuItem
testMenuItem = MenuItem
  { sort           = 1
  , sku            = testSku
  , brand          = "Test Brand"
  , name           = "Test Item"
  , price          = 1000
  , measure_unit   = "g"
  , per_package    = "3.5"
  , quantity       = testItemQty
  , category       = Flower
  , subcategory    = "Indoor"
  , description    = "Test"
  , tags           = V.fromList []
  , effects        = V.fromList []
  , strain_lineage = StrainLineage
      { thc              = "25%"
      , cbg              = "1%"
      , strain           = "Test"
      , creator          = "Test"
      , species          = Hybrid
      , dominant_terpene = "Myrcene"
      , terpenes         = V.fromList []
      , lineage          = V.fromList []
      , leafly_url       = "https://leafly.com/test"
      , img              = "https://example.com/img.jpg"
      }
  }

testTxItem :: TransactionItem
testTxItem = TransactionItem
  { transactionItemId            = itemUUID
  , transactionItemTransactionId = txUUID
  , transactionItemMenuItemSku   = testSku
  , transactionItemQuantity      = 3
  , transactionItemPricePerUnit  = 1000
  , transactionItemDiscounts     = []
  , transactionItemTaxes         = []
  , transactionItemSubtotal      = 3000
  , transactionItemTotal         = 3000
  }

mkStVar :: IO (TVar AvailabilityState)
mkStVar = newTVarIO $ AvailabilityState
  { asItems       = Map.singleton testSku testMenuItem
  , asReserved    = Map.empty
  , asPublicLocId = testLocId
  , asLocName     = "Test"
  }

spec :: Spec
spec = describe "updateAvailability" $ do

  it "ItemCreated event produces AvailabilityUpdate" $ do
    stVar <- mkStVar
    let newSku  = read "00000000-0000-0000-0000-000000000099" :: UUID
        newItem = testMenuItem { sku = newSku }
        evt     = InventoryEvt ItemCreated
          { ieItem      = newItem
          , ieTimestamp = testTime
          , ieActorId   = testActorId
          }
    mUpd <- atomically $ updateAvailability stVar evt testTime
    mUpd `shouldSatisfy` isJust

  it "ItemUpdated event produces AvailabilityUpdate" $ do
    stVar <- mkStVar
    let evt = InventoryEvt ItemUpdated
          { ieOldItem   = testMenuItem
          , ieNewItem   = testMenuItem { price = 1200 }
          , ieTimestamp = testTime
          , ieActorId   = testActorId
          }
    mUpd <- atomically $ updateAvailability stVar evt testTime
    mUpd `shouldSatisfy` isJust

  it "ItemDeleted event produces no update" $ do
    stVar <- mkStVar
    let evt = InventoryEvt ItemDeleted
          { ieSku       = testSku
          , ieItemName  = "Test Item"
          , ieTimestamp = testTime
          , ieActorId   = testActorId
          }
    mUpd <- atomically $ updateAvailability stVar evt testTime
    mUpd `shouldBe` Nothing

  it "ItemDeleted removes sku from state" $ do
    stVar <- mkStVar
    let evt = InventoryEvt ItemDeleted
          { ieSku       = testSku
          , ieItemName  = "Test Item"
          , ieTimestamp = testTime
          , ieActorId   = testActorId
          }
    _ <- atomically $ updateAvailability stVar evt testTime
    st <- readTVarIO stVar
    Map.lookup testSku (asItems st) `shouldBe` Nothing

  it "TransactionItemAdded decreases availableQty" $ do
    stVar <- mkStVar
    let evt = TransactionEvt TransactionItemAdded
          { teTxId      = txUUID
          , teItem      = testTxItem
          , teTimestamp = testTime
          }
    _ <- atomically $ updateAvailability stVar evt testTime
    st <- readTVarIO stVar
    availableQty st testSku
      `shouldBe` (testItemQty - transactionItemQuantity testTxItem)

  it "TransactionItemAdded produces AvailabilityUpdate" $ do
    stVar <- mkStVar
    let evt = TransactionEvt TransactionItemAdded
          { teTxId      = txUUID
          , teItem      = testTxItem
          , teTimestamp = testTime
          }
    mUpd <- atomically $ updateAvailability stVar evt testTime
    mUpd `shouldSatisfy` isJust

  it "TransactionItemRemoved restores availableQty" $ do
    stVar <- mkStVar
    let addEvt = TransactionEvt TransactionItemAdded
          { teTxId      = txUUID
          , teItem      = testTxItem
          , teTimestamp = testTime
          }
        remEvt = TransactionEvt TransactionItemRemoved
          { teTxId      = txUUID
          , teItemId    = itemUUID
          , teItemSku   = testSku
          , teQty       = transactionItemQuantity testTxItem
          , teTimestamp = testTime
          }
    _ <- atomically $ updateAvailability stVar addEvt testTime
    _ <- atomically $ updateAvailability stVar remEvt testTime
    st <- readTVarIO stVar
    availableQty st testSku `shouldBe` testItemQty

  it "SessionEvt produces no update" $ do
    stVar <- mkStVar
    let evt = SessionEvt SessionCreated
          { sesUserId    = userUUID
          , sesRole      = Cashier
          , sesTimestamp = testTime
          }
    mUpd <- atomically $ updateAvailability stVar evt testTime
    mUpd `shouldBe` Nothing

  it "RegisterEvt produces no update" $ do
    stVar <- mkStVar
    let evt = RegisterEvt RegisterOpened
          { reRegId        = regUUID
          , reEmpId        = testActorId
          , reStartingCash = 50000
          , reTimestamp    = testTime
          }
    mUpd <- atomically $ updateAvailability stVar evt testTime
    mUpd `shouldBe` Nothing