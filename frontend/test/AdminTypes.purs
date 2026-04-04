module Test.AdminTypes where

import Prelude

import Data.Array (length)
import Data.Maybe (Maybe(..), isJust)
import Data.String (Pattern(..), contains)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Admin
  ( AdminAction(..)
  , AdminSnapshot
  , AvailabilitySummary
  , BroadcasterStats
  , DbStats
  , DomainEventPage
  , DomainEventRow
  , InventorySummary
  , LogEvent
  , LogPage
  , SessionInfo
  )
import Types.UUID (UUID(..))
import Yoga.JSON (readJSON_, writeJSON)

-- A complete AdminSnapshot with all nested types represented
snapshotJson :: String
snapshotJson =
  """{"snapshotTime":"2024-06-15T10:30:00Z","snapshotEnvironment":"development","snapshotUptimeSeconds":3600,"snapshotActiveSessions":[{"siSessionId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","siUserId":"d3a1f4f0-c518-4db3-aa43-e80b428d6304","siRole":"Admin","siCreatedAt":"2024-06-15T09:00:00Z","siLastSeen":"2024-06-15T10:30:00Z"}],"snapshotOpenRegisters":[{"registerId":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","registerName":"Register 1","registerLocationId":"cccccccc-cccc-cccc-cccc-cccccccccccc","registerIsOpen":true,"registerCurrentDrawerAmount":50000,"registerExpectedDrawerAmount":50000}],"snapshotInventorySummary":{"invItemCount":25,"invTotalValue":500000,"invLowStockCount":3,"invTotalReserved":10},"snapshotAvailabilitySummary":{"avInStockCount":22,"avOutOfStockCount":3,"avTotalItems":25},"snapshotDbStats":{"dbPoolSize":10,"dbPoolIdle":8,"dbPoolInUse":2,"dbQueryCount":1500.0,"dbErrorCount":0.0},"snapshotBroadcasterStats":{"bcLogDepth":100,"bcDomainDepth":50,"bcStockDepth":10,"bcAvailabilityDepth":25,"bcAvailabilitySeq":1234.0}}"""

spec :: Spec Unit
spec = describe "Types.Admin" do

  describe "AdminAction WriteForeign" do
    it "RevokeSession — tag present" $
      let json = writeJSON (RevokeSession (UUID "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
      in contains (Pattern "RevokeSession") json `shouldEqual` true

    it "RevokeSession — UUID present" $
      let json = writeJSON (RevokeSession (UUID "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
      in contains (Pattern "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") json `shouldEqual` true

    it "ForceCloseRegister — tag present" $
      let json = writeJSON (ForceCloseRegister (UUID "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") "overcrowded")
      in contains (Pattern "ForceCloseRegister") json `shouldEqual` true

    it "ForceCloseRegister — reason present" $
      let json = writeJSON (ForceCloseRegister (UUID "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") "overcrowded")
      in contains (Pattern "overcrowded") json `shouldEqual` true

    it "ClearRateLimitForIp — tag present" $
      let json = writeJSON (ClearRateLimitForIp "192.168.1.1")
      in contains (Pattern "ClearRateLimitForIp") json `shouldEqual` true

    it "ClearRateLimitForIp — IP present" $
      let json = writeJSON (ClearRateLimitForIp "192.168.1.1")
      in contains (Pattern "192.168.1.1") json `shouldEqual` true

    it "SetLowStockThreshold — tag present" $
      let json = writeJSON (SetLowStockThreshold 5)
      in contains (Pattern "SetLowStockThreshold") json `shouldEqual` true

    it "SetLowStockThreshold — value present" $
      let json = writeJSON (SetLowStockThreshold 5)
      in contains (Pattern "5") json `shouldEqual` true

    it "TriggerSnapshotExport — tag present" $
      let json = writeJSON TriggerSnapshotExport
      in contains (Pattern "TriggerSnapshotExport") json `shouldEqual` true

  describe "LogEvent JSON" do
    let noTraceJson =
          """{"leTimestamp":"2024-06-15T10:30:00Z","leComponent":"API","leSeverity":"Info","leMessage":"Server started","leTraceId":null}"""
    let withTraceJson =
          """{"leTimestamp":"2024-06-15T10:30:00Z","leComponent":"Auth","leSeverity":"Error","leMessage":"Login failed","leTraceId":"trace-abc-123"}"""

    it "parses without traceId" $
      (readJSON_ noTraceJson :: Maybe LogEvent) `shouldSatisfy` isJust

    it "preserves leComponent" $
      case readJSON_ noTraceJson :: Maybe LogEvent of
        Just e  -> e.leComponent `shouldEqual` "API"
        Nothing -> false `shouldEqual` true

    it "preserves leSeverity" $
      case readJSON_ noTraceJson :: Maybe LogEvent of
        Just e  -> e.leSeverity `shouldEqual` "Info"
        Nothing -> false `shouldEqual` true

    it "preserves leMessage" $
      case readJSON_ noTraceJson :: Maybe LogEvent of
        Just e  -> e.leMessage `shouldEqual` "Server started"
        Nothing -> false `shouldEqual` true

    it "null traceId → Nothing" $
      case readJSON_ noTraceJson :: Maybe LogEvent of
        Just e  -> e.leTraceId `shouldEqual` Nothing
        Nothing -> false `shouldEqual` true

    it "parses with traceId" $
      (readJSON_ withTraceJson :: Maybe LogEvent) `shouldSatisfy` isJust

    it "preserves traceId value" $
      case readJSON_ withTraceJson :: Maybe LogEvent of
        Just e  -> e.leTraceId `shouldEqual` Just "trace-abc-123"
        Nothing -> false `shouldEqual` true

    it "preserves severity from Error log" $
      case readJSON_ withTraceJson :: Maybe LogEvent of
        Just e  -> e.leSeverity `shouldEqual` "Error"
        Nothing -> false `shouldEqual` true

  describe "LogPage JSON" do
    let json =
          """{"lpEntries":[{"leTimestamp":"2024-06-15T10:30:00Z","leComponent":"API","leSeverity":"Info","leMessage":"Start","leTraceId":null}],"lpNextCursor":42.0,"lpTotal":100}"""

    it "parses LogPage" $
      (readJSON_ json :: Maybe LogPage) `shouldSatisfy` isJust

    it "preserves lpTotal" $
      case readJSON_ json :: Maybe LogPage of
        Just p  -> p.lpTotal `shouldEqual` 100
        Nothing -> false `shouldEqual` true

    it "preserves lpNextCursor" $
      case readJSON_ json :: Maybe LogPage of
        Just p  -> p.lpNextCursor `shouldEqual` Just 42.0
        Nothing -> false `shouldEqual` true

    it "parses entries array" $
      case readJSON_ json :: Maybe LogPage of
        Just p  -> (length p.lpEntries) `shouldEqual` 1
        Nothing -> false `shouldEqual` true

  describe "BroadcasterStats JSON" do
    let json =
          """{"bcLogDepth":10,"bcDomainDepth":5,"bcStockDepth":3,"bcAvailabilityDepth":8,"bcAvailabilitySeq":42.0}"""

    it "parses" $
      (readJSON_ json :: Maybe BroadcasterStats) `shouldSatisfy` isJust

    it "preserves bcLogDepth" $
      case readJSON_ json :: Maybe BroadcasterStats of
        Just s  -> s.bcLogDepth `shouldEqual` 10
        Nothing -> false `shouldEqual` true

    it "preserves bcDomainDepth" $
      case readJSON_ json :: Maybe BroadcasterStats of
        Just s  -> s.bcDomainDepth `shouldEqual` 5
        Nothing -> false `shouldEqual` true

    it "preserves bcStockDepth" $
      case readJSON_ json :: Maybe BroadcasterStats of
        Just s  -> s.bcStockDepth `shouldEqual` 3
        Nothing -> false `shouldEqual` true

    it "preserves bcAvailabilitySeq" $
      case readJSON_ json :: Maybe BroadcasterStats of
        Just s  -> s.bcAvailabilitySeq `shouldEqual` 42.0
        Nothing -> false `shouldEqual` true

    it "zero-depth stats parse" $
      let zeroJson = """{"bcLogDepth":0,"bcDomainDepth":0,"bcStockDepth":0,"bcAvailabilityDepth":0,"bcAvailabilitySeq":0.0}"""
      in (readJSON_ zeroJson :: Maybe BroadcasterStats) `shouldSatisfy` isJust

  describe "DbStats JSON" do
    let json =
          """{"dbPoolSize":10,"dbPoolIdle":8,"dbPoolInUse":2,"dbQueryCount":1500.0,"dbErrorCount":3.0}"""

    it "parses" $
      (readJSON_ json :: Maybe DbStats) `shouldSatisfy` isJust

    it "preserves dbPoolSize" $
      case readJSON_ json :: Maybe DbStats of
        Just s  -> s.dbPoolSize `shouldEqual` 10
        Nothing -> false `shouldEqual` true

    it "preserves dbPoolIdle" $
      case readJSON_ json :: Maybe DbStats of
        Just s  -> s.dbPoolIdle `shouldEqual` 8
        Nothing -> false `shouldEqual` true

    it "preserves dbPoolInUse" $
      case readJSON_ json :: Maybe DbStats of
        Just s  -> s.dbPoolInUse `shouldEqual` 2
        Nothing -> false `shouldEqual` true

    it "preserves dbQueryCount" $
      case readJSON_ json :: Maybe DbStats of
        Just s  -> s.dbQueryCount `shouldEqual` 1500.0
        Nothing -> false `shouldEqual` true

    it "preserves dbErrorCount" $
      case readJSON_ json :: Maybe DbStats of
        Just s  -> s.dbErrorCount `shouldEqual` 3.0
        Nothing -> false `shouldEqual` true

  describe "InventorySummary JSON" do
    let json =
          """{"invItemCount":25,"invTotalValue":500000,"invLowStockCount":3,"invTotalReserved":10}"""

    it "parses" $
      (readJSON_ json :: Maybe InventorySummary) `shouldSatisfy` isJust

    it "preserves invItemCount" $
      case readJSON_ json :: Maybe InventorySummary of
        Just s  -> s.invItemCount `shouldEqual` 25
        Nothing -> false `shouldEqual` true

    it "preserves invLowStockCount" $
      case readJSON_ json :: Maybe InventorySummary of
        Just s  -> s.invLowStockCount `shouldEqual` 3
        Nothing -> false `shouldEqual` true

    it "preserves invTotalReserved" $
      case readJSON_ json :: Maybe InventorySummary of
        Just s  -> s.invTotalReserved `shouldEqual` 10
        Nothing -> false `shouldEqual` true

  describe "AvailabilitySummary JSON" do
    let json =
          """{"avInStockCount":22,"avOutOfStockCount":3,"avTotalItems":25}"""

    it "parses" $
      (readJSON_ json :: Maybe AvailabilitySummary) `shouldSatisfy` isJust

    it "preserves avInStockCount" $
      case readJSON_ json :: Maybe AvailabilitySummary of
        Just s  -> s.avInStockCount `shouldEqual` 22
        Nothing -> false `shouldEqual` true

    it "preserves avOutOfStockCount" $
      case readJSON_ json :: Maybe AvailabilitySummary of
        Just s  -> s.avOutOfStockCount `shouldEqual` 3
        Nothing -> false `shouldEqual` true

    it "in + out = total" $
      case readJSON_ json :: Maybe AvailabilitySummary of
        Just s  -> (s.avInStockCount + s.avOutOfStockCount) `shouldEqual` s.avTotalItems
        Nothing -> false `shouldEqual` true

  describe "SessionInfo JSON" do
    let json =
          """{"siSessionId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","siUserId":"d3a1f4f0-c518-4db3-aa43-e80b428d6304","siRole":"Admin","siCreatedAt":"2024-06-15T09:00:00Z","siLastSeen":"2024-06-15T10:30:00Z"}"""

    it "parses" $
      (readJSON_ json :: Maybe SessionInfo) `shouldSatisfy` isJust

    it "preserves siUserId" $
      case readJSON_ json :: Maybe SessionInfo of
        Just s  -> s.siUserId `shouldEqual` UUID "d3a1f4f0-c518-4db3-aa43-e80b428d6304"
        Nothing -> false `shouldEqual` true

    it "preserves siSessionId" $
      case readJSON_ json :: Maybe SessionInfo of
        Just s  -> s.siSessionId `shouldEqual` UUID "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        Nothing -> false `shouldEqual` true

  describe "DomainEventRow JSON" do
    let json =
          """{"derSeq":42.0,"derId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","derType":"InventoryUpdated","derAggregateId":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","derTraceId":null,"derActorId":"cccccccc-cccc-cccc-cccc-cccccccccccc","derOccurredAt":"2024-06-15T10:30:00Z"}"""

    it "parses DomainEventRow" $
      (readJSON_ json :: Maybe DomainEventRow) `shouldSatisfy` isJust

    it "preserves derType" $
      case readJSON_ json :: Maybe DomainEventRow of
        Just r  -> r.derType `shouldEqual` "InventoryUpdated"
        Nothing -> false `shouldEqual` true

    it "preserves derSeq" $
      case readJSON_ json :: Maybe DomainEventRow of
        Just r  -> r.derSeq `shouldEqual` 42.0
        Nothing -> false `shouldEqual` true

    it "null derTraceId → Nothing" $
      case readJSON_ json :: Maybe DomainEventRow of
        Just r  -> r.derTraceId `shouldEqual` Nothing
        Nothing -> false `shouldEqual` true

    it "non-null derActorId → Just UUID" $
      case readJSON_ json :: Maybe DomainEventRow of
        Just r  -> r.derActorId `shouldEqual` Just (UUID "cccccccc-cccc-cccc-cccc-cccccccccccc")
        Nothing -> false `shouldEqual` true

  describe "DomainEventPage JSON" do
    let json =
          """{"depEvents":[{"derSeq":1.0,"derId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","derType":"InventoryUpdated","derAggregateId":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","derTraceId":null,"derActorId":null,"derOccurredAt":"2024-06-15T10:30:00Z"}],"depNextCursor":1.0,"depTotal":50}"""

    it "parses DomainEventPage" $
      (readJSON_ json :: Maybe DomainEventPage) `shouldSatisfy` isJust

    it "preserves depTotal" $
      case readJSON_ json :: Maybe DomainEventPage of
        Just p  -> p.depTotal `shouldEqual` 50
        Nothing -> false `shouldEqual` true

    it "preserves depNextCursor" $
      case readJSON_ json :: Maybe DomainEventPage of
        Just p  -> p.depNextCursor `shouldEqual` Just 1.0
        Nothing -> false `shouldEqual` true

    it "parses events array" $
      case readJSON_ json :: Maybe DomainEventPage of
        Just p  -> (length p.depEvents) `shouldEqual` 1
        Nothing -> false `shouldEqual` true

  describe "AdminSnapshot JSON" do
    it "parses complete snapshot" $
      (readJSON_ snapshotJson :: Maybe AdminSnapshot) `shouldSatisfy` isJust

    it "preserves snapshotEnvironment" $
      case readJSON_ snapshotJson :: Maybe AdminSnapshot of
        Just s  -> s.snapshotEnvironment `shouldEqual` "development"
        Nothing -> false `shouldEqual` true

    it "preserves snapshotUptimeSeconds" $
      case readJSON_ snapshotJson :: Maybe AdminSnapshot of
        Just s  -> s.snapshotUptimeSeconds `shouldEqual` 3600
        Nothing -> false `shouldEqual` true

    it "has one active session" $
      case readJSON_ snapshotJson :: Maybe AdminSnapshot of
        Just s  -> (length s.snapshotActiveSessions) `shouldEqual` 1
        Nothing -> false `shouldEqual` true

    it "has one open register" $
      case readJSON_ snapshotJson :: Maybe AdminSnapshot of
        Just s  -> (length s.snapshotOpenRegisters) `shouldEqual` 1
        Nothing -> false `shouldEqual` true

    it "inventory summary is embedded" $
      case readJSON_ snapshotJson :: Maybe AdminSnapshot of
        Just s  -> s.snapshotInventorySummary.invItemCount `shouldEqual` 25
        Nothing -> false `shouldEqual` true

    it "broadcaster stats are embedded" $
      case readJSON_ snapshotJson :: Maybe AdminSnapshot of
        Just s  -> s.snapshotBroadcasterStats.bcLogDepth `shouldEqual` 100
        Nothing -> false `shouldEqual` true

    it "db stats are embedded" $
      case readJSON_ snapshotJson :: Maybe AdminSnapshot of
        Just s  -> s.snapshotDbStats.dbPoolSize `shouldEqual` 10
        Nothing -> false `shouldEqual` true

    it "availability summary is embedded" $
      case readJSON_ snapshotJson :: Maybe AdminSnapshot of
        Just s  -> s.snapshotAvailabilitySummary.avTotalItems `shouldEqual` 25
        Nothing -> false `shouldEqual` true