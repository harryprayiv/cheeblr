module Test.WebUtils where

import Prelude

import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Utils.SSE (SSEStatus(..))
import Utils.WebSocket (toWsUrl)

spec :: Spec Unit
spec = describe "Web Utilities" do

  describe "toWsUrl" do
    it "converts https to wss" $
      toWsUrl "https://localhost:8080"
        `shouldEqual` "wss://localhost:8080"

    it "converts http to ws" $
      toWsUrl "http://localhost:8080"
        `shouldEqual` "ws://localhost:8080"

    it "leaves non-http scheme unchanged" $
      toWsUrl "ftp://example.com"
        `shouldEqual` "ftp://example.com"

    it "converts https with path and query params" $
      toWsUrl "https://example.com/api/stream?authorization=Bearer+abc"
        `shouldEqual` "wss://example.com/api/stream?authorization=Bearer+abc"

    it "converts http with IP and port" $
      toWsUrl "http://192.168.8.248:8080/stock/queue/stream"
        `shouldEqual` "ws://192.168.8.248:8080/stock/queue/stream"

    it "converts https with IP and port" $
      toWsUrl "https://192.168.8.248:8080"
        `shouldEqual` "wss://192.168.8.248:8080"

    it "plain string without scheme left unchanged" $
      toWsUrl "localhost:8080"
        `shouldEqual` "localhost:8080"

    it "wss already-websocket scheme left unchanged" $
      toWsUrl "wss://example.com"
        `shouldEqual` "wss://example.com"

    it "converts the actual backend URL format used in cheeblr" $
      toWsUrl "https://localhost:8080"
        `shouldEqual` "wss://localhost:8080"

  describe "SSEStatus Show" do
    it "SSEConnecting"   $ show SSEConnecting   `shouldEqual` "Connecting"
    it "SSEConnected"    $ show SSEConnected     `shouldEqual` "Connected"
    it "SSEReconnecting" $ show SSEReconnecting  `shouldEqual` "Reconnecting"
    it "SSEClosed"       $ show SSEClosed        `shouldEqual` "Closed"

  describe "SSEStatus Eq" do
    it "reflexive: SSEConnecting == SSEConnecting" $
      (SSEConnecting == SSEConnecting) `shouldEqual` true
    it "reflexive: SSEConnected == SSEConnected" $
      (SSEConnected == SSEConnected) `shouldEqual` true
    it "SSEConnected /= SSEClosed" $
      (SSEConnected == SSEClosed) `shouldEqual` false
    it "SSEConnected /= SSEConnecting" $
      (SSEConnected == SSEConnecting) `shouldEqual` false
    it "SSEReconnecting /= SSEConnected" $
      (SSEReconnecting == SSEConnected) `shouldEqual` false
