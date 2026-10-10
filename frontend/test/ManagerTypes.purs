module Test.ManagerTypes where

import Prelude

import Data.Maybe (Maybe(..), isJust)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Manager (DailyReportResult)
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
