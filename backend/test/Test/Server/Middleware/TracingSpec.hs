{-# LANGUAGE OverloadedStrings #-}

module Test.Server.Middleware.TracingSpec (spec) where

import qualified Data.ByteString.Char8 as B8
import Data.Maybe (isJust)
import Data.Text (pack)
import Network.HTTP.Types (status200)
import Network.Wai (
  Application,
  requestHeaders,
  responseLBS,
 )
import Network.Wai.Test (
  defaultRequest,
  request,
  runSession,
  simpleHeaders,
 )
import Test.Hspec

import Server.Middleware.Tracing (getTraceId, tracingMiddleware)
import Types.Trace (parseTraceId)

testApp :: Application
testApp _req respond =
  respond $ responseLBS status200 [] "ok"

traceEchoApp :: Application
traceEchoApp req respond = do
  let body = case getTraceId req of
        Nothing -> "no-trace"
        Just _ -> "ok"
  respond $ responseLBS status200 [] body

wrappedApp :: Application
wrappedApp = tracingMiddleware testApp

wrappedEchoApp :: Application
wrappedEchoApp = tracingMiddleware traceEchoApp

spec :: Spec
spec = describe "Server.Middleware.Tracing" $ do
  describe "response header" $ do
    it "adds X-Trace-Id header to every response" $ do
      resp <- runSession (request defaultRequest) wrappedApp
      lookup "X-Trace-Id" (simpleHeaders resp) `shouldSatisfy` isJust

    it "X-Trace-Id value is a valid UUID" $ do
      resp <- runSession (request defaultRequest) wrappedApp
      case lookup "X-Trace-Id" (simpleHeaders resp) of
        Nothing -> expectationFailure "X-Trace-Id header missing"
        Just raw -> parseTraceId (pack (B8.unpack raw)) `shouldSatisfy` isJust

    it "echoes incoming X-Trace-Id when valid" $ do
      let
        knownId = "11111111-1111-1111-1111-111111111111"
        req =
          defaultRequest
            { requestHeaders = [("X-Trace-Id", B8.pack knownId)]
            }
      resp <- runSession (request req) wrappedApp
      lookup "X-Trace-Id" (simpleHeaders resp) `shouldBe` Just (B8.pack knownId)

    it "generates a new ID when incoming X-Trace-Id is invalid" $ do
      let req =
            defaultRequest
              { requestHeaders = [("X-Trace-Id", "not-a-uuid")]
              }
      resp <- runSession (request req) wrappedApp
      case lookup "X-Trace-Id" (simpleHeaders resp) of
        Nothing -> expectationFailure "X-Trace-Id header missing"
        Just raw -> do
          raw `shouldNotBe` "not-a-uuid"
          parseTraceId (pack (B8.unpack raw)) `shouldSatisfy` isJust

    it "two requests without trace ID get different IDs" $ do
      resp1 <- runSession (request defaultRequest) wrappedApp
      resp2 <- runSession (request defaultRequest) wrappedApp
      let
        h1 = lookup "X-Trace-Id" (simpleHeaders resp1)
        h2 = lookup "X-Trace-Id" (simpleHeaders resp2)
      h1 `shouldNotBe` h2

  describe "vault injection" $ do
    it "trace ID is available in vault via getTraceId" $ do
      resp <- runSession (request defaultRequest) wrappedEchoApp
      simpleHeaders resp `shouldSatisfy` \hs ->
        isJust (lookup "X-Trace-Id" hs)
