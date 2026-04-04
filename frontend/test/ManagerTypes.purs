module Test.ManagerTypes where

import Prelude

import Data.Maybe (Maybe(..), isJust)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Manager (DailyReportResult, ManagerAlertRaw)
import Yoga.JSON (readJSON_)

spec :: Spec Unit
spec = describe "Types.Manager JSON" do

  describe "DailyReportResult" do
    let json =
          """{"dailyReportCash":10000,"dailyReportCard":25000,"dailyReportOther":500,"dailyReportTotal":35500,"dailyReportTransactions":15}"""

    it "parses" $
      (readJSON_ json :: Maybe DailyReportResult) `shouldSatisfy` isJust

    it "preserves dailyReportCash" $
      case readJSON_ json :: Maybe DailyReportResult of
        Just r  -> r.dailyReportCash `shouldEqual` 10000
        Nothing -> false `shouldEqual` true

    it "preserves dailyReportCard" $
      case readJSON_ json :: Maybe DailyReportResult of
        Just r  -> r.dailyReportCard `shouldEqual` 25000
        Nothing -> false `shouldEqual` true

    it "preserves dailyReportOther" $
      case readJSON_ json :: Maybe DailyReportResult of
        Just r  -> r.dailyReportOther `shouldEqual` 500
        Nothing -> false `shouldEqual` true

    it "preserves dailyReportTotal" $
      case readJSON_ json :: Maybe DailyReportResult of
        Just r  -> r.dailyReportTotal `shouldEqual` 35500
        Nothing -> false `shouldEqual` true

    it "preserves dailyReportTransactions" $
      case readJSON_ json :: Maybe DailyReportResult of
        Just r  -> r.dailyReportTransactions `shouldEqual` 15
        Nothing -> false `shouldEqual` true

    it "zero-value report parses" $
      let zeroJson =
            """{"dailyReportCash":0,"dailyReportCard":0,"dailyReportOther":0,"dailyReportTotal":0,"dailyReportTransactions":0}"""
      in (readJSON_ zeroJson :: Maybe DailyReportResult) `shouldSatisfy` isJust

    it "zero-transaction day has zero totals" $
      let zeroJson =
            """{"dailyReportCash":0,"dailyReportCard":0,"dailyReportOther":0,"dailyReportTotal":0,"dailyReportTransactions":0}"""
      in case readJSON_ zeroJson :: Maybe DailyReportResult of
        Just r  -> r.dailyReportTransactions `shouldEqual` 0
        Nothing -> false `shouldEqual` true

  describe "ManagerAlertRaw — LowInventoryAlert" do
    let json =
          """{"tag":"LowInventoryAlert","id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"OG Kush","quantity":2,"elapsed":null,"variance":null}"""

    it "parses" $
      (readJSON_ json :: Maybe ManagerAlertRaw) `shouldSatisfy` isJust

    it "preserves tag" $
      case readJSON_ json :: Maybe ManagerAlertRaw of
        Just a  -> a.tag `shouldEqual` "LowInventoryAlert"
        Nothing -> false `shouldEqual` true

    it "preserves name" $
      case readJSON_ json :: Maybe ManagerAlertRaw of
        Just a  -> a.name `shouldEqual` Just "OG Kush"
        Nothing -> false `shouldEqual` true

    it "preserves quantity" $
      case readJSON_ json :: Maybe ManagerAlertRaw of
        Just a  -> a.quantity `shouldEqual` Just 2
        Nothing -> false `shouldEqual` true

    it "elapsed is Nothing" $
      case readJSON_ json :: Maybe ManagerAlertRaw of
        Just a  -> a.elapsed `shouldEqual` Nothing
        Nothing -> false `shouldEqual` true

    it "variance is Nothing" $
      case readJSON_ json :: Maybe ManagerAlertRaw of
        Just a  -> a.variance `shouldEqual` Nothing
        Nothing -> false `shouldEqual` true

  describe "ManagerAlertRaw — StaleTransactionAlert" do
    let json =
          """{"tag":"StaleTransactionAlert","id":null,"name":null,"quantity":null,"elapsed":120,"variance":null}"""

    it "parses" $
      (readJSON_ json :: Maybe ManagerAlertRaw) `shouldSatisfy` isJust

    it "preserves tag" $
      case readJSON_ json :: Maybe ManagerAlertRaw of
        Just a  -> a.tag `shouldEqual` "StaleTransactionAlert"
        Nothing -> false `shouldEqual` true

    it "preserves elapsed" $
      case readJSON_ json :: Maybe ManagerAlertRaw of
        Just a  -> a.elapsed `shouldEqual` Just 120
        Nothing -> false `shouldEqual` true

    it "name is Nothing" $
      case readJSON_ json :: Maybe ManagerAlertRaw of
        Just a  -> a.name `shouldEqual` Nothing
        Nothing -> false `shouldEqual` true

    it "variance is Nothing" $
      case readJSON_ json :: Maybe ManagerAlertRaw of
        Just a  -> a.variance `shouldEqual` Nothing
        Nothing -> false `shouldEqual` true

  describe "ManagerAlertRaw — RegisterVarianceAlert" do
    let json =
          """{"tag":"RegisterVarianceAlert","id":null,"name":null,"quantity":null,"elapsed":null,"variance":500}"""

    it "parses" $
      (readJSON_ json :: Maybe ManagerAlertRaw) `shouldSatisfy` isJust

    it "preserves tag" $
      case readJSON_ json :: Maybe ManagerAlertRaw of
        Just a  -> a.tag `shouldEqual` "RegisterVarianceAlert"
        Nothing -> false `shouldEqual` true

    it "preserves variance" $
      case readJSON_ json :: Maybe ManagerAlertRaw of
        Just a  -> a.variance `shouldEqual` Just 500
        Nothing -> false `shouldEqual` true

    it "elapsed is Nothing" $
      case readJSON_ json :: Maybe ManagerAlertRaw of
        Just a  -> a.elapsed `shouldEqual` Nothing
        Nothing -> false `shouldEqual` true

  describe "ManagerAlertRaw — all nullable fields can be Nothing" do
    let allNullJson =
          """{"tag":"UnknownAlert","id":null,"name":null,"quantity":null,"elapsed":null,"variance":null}"""

    it "parses with all nulls" $
      (readJSON_ allNullJson :: Maybe ManagerAlertRaw) `shouldSatisfy` isJust

    it "all optional fields are Nothing" $
      case readJSON_ allNullJson :: Maybe ManagerAlertRaw of
        Just a  -> do
          a.id       `shouldEqual` Nothing
          a.name     `shouldEqual` Nothing
          a.quantity `shouldEqual` Nothing
          a.elapsed  `shouldEqual` Nothing
          a.variance `shouldEqual` Nothing
        Nothing -> false `shouldEqual` true
