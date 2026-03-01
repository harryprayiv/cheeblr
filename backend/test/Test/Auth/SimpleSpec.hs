{-# LANGUAGE OverloadedStrings #-}

module Test.Auth.SimpleSpec (spec) where

import Test.Hspec
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import Types.Auth
import Auth.Simple

spec :: Spec
spec = describe "Auth.Simple" $ do

  -- ──────────────────────────────────────────────
  -- devUsers map
  -- ──────────────────────────────────────────────
  describe "devUsers" $ do
    it "has 4 users" $
      Map.size devUsers `shouldBe` 4

    it "contains customer-1" $
      Map.lookup "customer-1" devUsers `shouldSatisfy` isJust

    it "contains cashier-1" $
      Map.lookup "cashier-1" devUsers `shouldSatisfy` isJust

    it "contains manager-1" $
      Map.lookup "manager-1" devUsers `shouldSatisfy` isJust

    it "contains admin-1" $
      Map.lookup "admin-1" devUsers `shouldSatisfy` isJust

    it "customer-1 has Customer role" $
      case Map.lookup "customer-1" devUsers of
        Just u  -> auRole u `shouldBe` Customer
        Nothing -> expectationFailure "customer-1 not found"

    it "cashier-1 has Cashier role" $
      case Map.lookup "cashier-1" devUsers of
        Just u  -> auRole u `shouldBe` Cashier
        Nothing -> expectationFailure "cashier-1 not found"

    it "manager-1 has Manager role" $
      case Map.lookup "manager-1" devUsers of
        Just u  -> auRole u `shouldBe` Manager
        Nothing -> expectationFailure "manager-1 not found"

    it "admin-1 has Admin role" $
      case Map.lookup "admin-1" devUsers of
        Just u  -> auRole u `shouldBe` Admin
        Nothing -> expectationFailure "admin-1 not found"

    it "cashier-1 has a locationId" $ do
      case Map.lookup "cashier-1" devUsers of
        Just u  -> auLocationId u `shouldSatisfy` isJust
        Nothing -> expectationFailure "cashier-1 not found"

    it "customer-1 has no locationId" $ do
      case Map.lookup "customer-1" devUsers of
        Just u  -> auLocationId u `shouldBe` Nothing
        Nothing -> expectationFailure "customer-1 not found"

    it "admin-1 has no locationId" $ do
      case Map.lookup "admin-1" devUsers of
        Just u  -> auLocationId u `shouldBe` Nothing
        Nothing -> expectationFailure "admin-1 not found"

    it "all users have emails" $
      mapM_ (\u -> auEmail u `shouldSatisfy` isJust) (Map.elems devUsers)

  -- ──────────────────────────────────────────────
  -- lookupUser
  -- ──────────────────────────────────────────────
  describe "lookupUser" $ do
    it "returns default (cashier) for Nothing" $ do
      let user = lookupUser Nothing
      auRole user `shouldBe` Cashier

    it "finds admin by key" $ do
      let user = lookupUser (Just "admin-1")
      auRole user `shouldBe` Admin

    it "finds customer by key" $ do
      let user = lookupUser (Just "customer-1")
      auRole user `shouldBe` Customer

    it "finds manager by key" $ do
      let user = lookupUser (Just "manager-1")
      auRole user `shouldBe` Manager

    it "finds cashier by key" $ do
      let user = lookupUser (Just "cashier-1")
      auRole user `shouldBe` Cashier

    it "finds admin by UUID" $ do
      let user = lookupUser (Just "d3a1f4f0-c518-4db3-aa43-e80b428d6304")
      auRole user `shouldBe` Admin

    it "finds customer by UUID" $ do
      let user = lookupUser (Just "8244082f-a6bc-4d6c-9427-64a0ecdc10db")
      auRole user `shouldBe` Customer

    it "finds cashier by UUID" $ do
      let user = lookupUser (Just "0a6f2deb-892b-4411-8025-08c1a4d61229")
      auRole user `shouldBe` Cashier

    it "finds manager by UUID" $ do
      let user = lookupUser (Just "8b75ea4a-00a4-4a2a-a5d5-a1bab8883802")
      auRole user `shouldBe` Manager

    it "returns default for unknown key" $ do
      let user = lookupUser (Just "unknown-user")
      auRole user `shouldBe` Cashier  -- default is cashier

    it "returns default for unknown UUID" $ do
      let user = lookupUser (Just "00000000-0000-0000-0000-000000000000")
      auRole user `shouldBe` Cashier

    it "is case-insensitive for key lookup" $ do
      let user = lookupUser (Just "ADMIN-1")
      -- devUsers uses lowercase keys, but lookupUser does T.toLower
      auRole user `shouldBe` Admin

  -- ──────────────────────────────────────────────
  -- getDevUser
  -- ──────────────────────────────────────────────
  describe "getDevUser" $ do
    it "finds admin-1" $
      getDevUser "admin-1" `shouldSatisfy` isJust

    it "finds customer-1" $
      getDevUser "customer-1" `shouldSatisfy` isJust

    it "finds cashier-1" $
      getDevUser "cashier-1" `shouldSatisfy` isJust

    it "finds manager-1" $
      getDevUser "manager-1" `shouldSatisfy` isJust

    it "returns Nothing for unknown" $
      getDevUser "unknown" `shouldBe` Nothing

    it "returns Nothing for UUID (key lookup only)" $
      getDevUser "d3a1f4f0-c518-4db3-aa43-e80b428d6304" `shouldBe` Nothing

    it "preserves username" $ do
      case getDevUser "admin-1" of
        Just u  -> auUserName u `shouldBe` "Test Admin"
        Nothing -> expectationFailure "admin-1 not found"

    it "preserves email" $ do
      case getDevUser "cashier-1" of
        Just u  -> auEmail u `shouldBe` Just "cashier@example.com"
        Nothing -> expectationFailure "cashier-1 not found"

  -- ──────────────────────────────────────────────
  -- requireAuth (tests in Handler monad)
  -- ──────────────────────────────────────────────
  -- Note: requireAuth runs in Servant's Handler monad, so full testing
  -- requires either runHandler or an integration test. Here we test the
  -- underlying logic via hasCapability/requireCapability which it delegates to.
  describe "requireAuth logic (via requireCapability)" $ do
    it "admin passes any capability check" $ do
      let admin = lookupUser (Just "admin-1")
      let caps = capabilitiesForRole (auRole admin)
      capCanManageUsers caps `shouldBe` True

    it "customer fails create item check" $ do
      let cust = lookupUser (Just "customer-1")
      let caps = capabilitiesForRole (auRole cust)
      capCanCreateItem caps `shouldBe` False

    it "cashier passes process transaction check" $ do
      let cashier = lookupUser (Just "cashier-1")
      let caps = capabilitiesForRole (auRole cashier)
      capCanProcessTransaction caps `shouldBe` True

    it "cashier fails void transaction check" $ do
      let cashier = lookupUser (Just "cashier-1")
      let caps = capabilitiesForRole (auRole cashier)
      capCanVoidTransaction caps `shouldBe` False

    it "manager passes delete item check" $ do
      let mgr = lookupUser (Just "manager-1")
      let caps = capabilitiesForRole (auRole mgr)
      capCanDeleteItem caps `shouldBe` True

    it "manager fails manage users check" $ do
      let mgr = lookupUser (Just "manager-1")
      let caps = capabilitiesForRole (auRole mgr)
      capCanManageUsers caps `shouldBe` False
