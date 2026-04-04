module Test.Stock where

import Prelude

import Data.Array (length) as Array
import Data.Maybe (Maybe(..))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Stock (PullAction(..), PullVertex(..), PullRequest, PullMessage, actionLabel, statusClass, validActions)
import Yoga.JSON (readJSON_)

spec :: Spec Unit
spec = describe "Types.Stock" do

  describe "PullVertex Show" do
    it "PullPending"   $ show PullPending   `shouldEqual` "PullPending"
    it "PullAccepted"  $ show PullAccepted  `shouldEqual` "PullAccepted"
    it "PullPulling"   $ show PullPulling   `shouldEqual` "PullPulling"
    it "PullFulfilled" $ show PullFulfilled `shouldEqual` "PullFulfilled"
    it "PullCancelled" $ show PullCancelled `shouldEqual` "PullCancelled"
    it "PullIssue"     $ show PullIssue     `shouldEqual` "PullIssue"

  describe "PullVertex Eq" do
    it "reflexive"  $ (PullPending == PullPending)   `shouldEqual` true
    it "distinct"   $ (PullPending == PullAccepted)  `shouldEqual` false

  describe "PullVertex Ord" do
    it "PullPending < PullAccepted"    $ (PullPending < PullAccepted)    `shouldEqual` true
    it "PullFulfilled > PullPulling"   $ (PullFulfilled > PullPulling)   `shouldEqual` true
    it "equal is not less-than"        $ (PullPending < PullPending)     `shouldEqual` false

  describe "validActions" do
    it "PullPending → Accept, Cancel" $
      map actionLabel (validActions "PullPending")
        `shouldEqual` [ "Accept", "Cancel" ]
    it "PullAccepted → Start, Cancel" $
      map actionLabel (validActions "PullAccepted")
        `shouldEqual` [ "Start Pull", "Cancel" ]
    it "PullPulling → Fulfill, ReportIssue" $
      map actionLabel (validActions "PullPulling")
        `shouldEqual` [ "Mark Fulfilled", "Report Issue" ]
    it "PullIssue → Retry, Cancel" $
      map actionLabel (validActions "PullIssue")
        `shouldEqual` [ "Retry", "Cancel" ]
    it "PullFulfilled → empty" $
      Array.length (validActions "PullFulfilled") `shouldEqual` 0
    it "PullCancelled → empty" $
      Array.length (validActions "PullCancelled") `shouldEqual` 0
    it "unknown status → empty" $
      Array.length (validActions "Bogus") `shouldEqual` 0

  describe "actionLabel" do
    it "ActionAccept"      $ actionLabel ActionAccept      `shouldEqual` "Accept"
    it "ActionStart"       $ actionLabel ActionStart       `shouldEqual` "Start Pull"
    it "ActionFulfill"     $ actionLabel ActionFulfill     `shouldEqual` "Mark Fulfilled"
    it "ActionReportIssue" $ actionLabel ActionReportIssue `shouldEqual` "Report Issue"
    it "ActionRetry"       $ actionLabel ActionRetry       `shouldEqual` "Retry"
    it "ActionCancel"      $ actionLabel ActionCancel      `shouldEqual` "Cancel"

  describe "statusClass" do
    it "PullPending"   $ statusClass "PullPending"   `shouldEqual` "status-pending"
    it "PullAccepted"  $ statusClass "PullAccepted"  `shouldEqual` "status-accepted"
    it "PullPulling"   $ statusClass "PullPulling"   `shouldEqual` "status-pulling"
    it "PullFulfilled" $ statusClass "PullFulfilled" `shouldEqual` "status-fulfilled"
    it "PullCancelled" $ statusClass "PullCancelled" `shouldEqual` "status-cancelled"
    it "PullIssue"     $ statusClass "PullIssue"     `shouldEqual` "status-issue"
    it "unknown → empty" $ statusClass "Unknown"     `shouldEqual` ""

  describe "PullRequest JSON parsing" do
    let json =
          """{"prId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","prTransactionId":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","prItemSku":"cccccccc-cccc-cccc-cccc-cccccccccccc","prItemName":"OG Kush","prQuantityNeeded":2,"prStatus":"PullPending","prCashierId":null,"prRegisterId":null,"prLocationId":"dddddddd-dddd-dddd-dddd-dddddddddddd","prCreatedAt":"2024-06-15T10:30:00Z","prUpdatedAt":"2024-06-15T10:30:00Z","prFulfilledAt":null}"""

    it "parses PullRequest" $
      (readJSON_ json :: Maybe PullRequest) `shouldSatisfy` case _ of
        Just _  -> true
        Nothing -> false

    it "preserves prItemName" $
      case readJSON_ json :: Maybe PullRequest of
        Just r  -> r.prItemName `shouldEqual` "OG Kush"
        Nothing -> false `shouldEqual` true

    it "preserves prQuantityNeeded" $
      case readJSON_ json :: Maybe PullRequest of
        Just r  -> r.prQuantityNeeded `shouldEqual` 2
        Nothing -> false `shouldEqual` true

    it "preserves prStatus" $
      case readJSON_ json :: Maybe PullRequest of
        Just r  -> r.prStatus `shouldEqual` "PullPending"
        Nothing -> false `shouldEqual` true

    it "null prCashierId → Nothing" $
      case readJSON_ json :: Maybe PullRequest of
        Just r  -> r.prCashierId `shouldEqual` Nothing
        Nothing -> false `shouldEqual` true

    it "null prFulfilledAt → Nothing" $
      case readJSON_ json :: Maybe PullRequest of
        Just r  -> r.prFulfilledAt `shouldEqual` Nothing
        Nothing -> false `shouldEqual` true

  describe "PullMessage JSON parsing" do
    let json =
          """{"pmId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","pmPullRequestId":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","pmFromRole":"Cashier","pmSenderId":"cccccccc-cccc-cccc-cccc-cccccccccccc","pmMessage":"On my way","pmCreatedAt":"2024-06-15T10:30:00Z"}"""

    it "parses PullMessage" $
      (readJSON_ json :: Maybe PullMessage) `shouldSatisfy` case _ of
        Just _  -> true
        Nothing -> false

    it "preserves pmFromRole" $
      case readJSON_ json :: Maybe PullMessage of
        Just m  -> m.pmFromRole `shouldEqual` "Cashier"
        Nothing -> false `shouldEqual` true

    it "preserves pmMessage" $
      case readJSON_ json :: Maybe PullMessage of
        Just m  -> m.pmMessage `shouldEqual` "On my way"
        Nothing -> false `shouldEqual` true