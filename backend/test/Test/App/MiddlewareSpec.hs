{-# LANGUAGE OverloadedStrings #-}

module Test.App.MiddlewareSpec (spec) where

import qualified Data.ByteString.Char8 as B8
import Data.Maybe (isJust, isNothing)
import Network.HTTP.Types (status200)
import Network.Wai (
  Application,
  Request (requestHeaders),
  responseLBS,
 )
import Network.Wai.Test (
  defaultRequest,
  request,
  runSession,
  simpleBody,
  simpleHeaders,
  simpleStatus,
 )
import Test.Hspec

import App (cookieAuthMiddleware, extractCookieToken)

-- | Echoes the Authorization header value back in the response body.
-- Returns "no-auth" if the header is absent.
authEchoApp :: Application
authEchoApp req respond = do
  let body = case lookup "Authorization" (requestHeaders req) of
        Nothing  -> "no-auth"
        Just val -> val
  respond $ responseLBS status200 [] (B8.fromStrict body)

-- | The pool argument is undefined here intentionally. The no-cookie path
-- never evaluates it (Haskell lazy evaluation). Full rotation logic
-- requires a real DB and belongs in integration tests.
noCookieMiddleware :: Application -> Application
noCookieMiddleware = cookieAuthMiddleware undefined 900

spec :: Spec
spec = describe "App middleware helpers" $ do

  describe "extractCookieToken (pure)" $ do
    it "returns Nothing when no Cookie header is present" $
      extractCookieToken defaultRequest `shouldBe` Nothing

    it "returns Nothing when Cookie has no cheeblr_session key" $ do
      let req = defaultRequest
            { requestHeaders = [("Cookie", "other_cookie=value")] }
      extractCookieToken req `shouldBe` Nothing

    it "returns Nothing for completely unrelated cookies" $ do
      let req = defaultRequest
            { requestHeaders = [("Cookie", "session_id=abc; csrf=xyz")] }
      extractCookieToken req `shouldBe` Nothing

    it "extracts the token when cheeblr_session is the only cookie" $ do
      let req = defaultRequest
            { requestHeaders = [("Cookie", "cheeblr_session=mytoken123")] }
      extractCookieToken req `shouldBe` Just "mytoken123"

    it "extracts token when it is the first of multiple cookies" $ do
      let req = defaultRequest
            { requestHeaders =
                [("Cookie", "cheeblr_session=abc456; other=xyz")]
            }
      extractCookieToken req `shouldBe` Just "abc456"

    it "extracts token when it is the last of multiple cookies" $ do
      let req = defaultRequest
            { requestHeaders =
                [("Cookie", "other=xyz; cheeblr_session=def789")]
            }
      extractCookieToken req `shouldBe` Just "def789"

    it "extracts token when surrounded by other cookies" $ do
      let req = defaultRequest
            { requestHeaders =
                [("Cookie", "a=1; cheeblr_session=tok42; b=2")]
            }
      extractCookieToken req `shouldBe` Just "tok42"

    it "handles opaque base64url token strings" $ do
      let token = "aB3-xY9_zK2"
          req   = defaultRequest
            { requestHeaders = [("Cookie", "cheeblr_session=" <> token)] }
      extractCookieToken req `shouldBe` Just "aB3-xY9_zK2"

    it "returns Just for an empty token value (parseCookies returns empty BS)" $ do
      let req = defaultRequest
            { requestHeaders = [("Cookie", "cheeblr_session=")] }
      extractCookieToken req `shouldSatisfy` isJust

  describe "cookieAuthMiddleware — no-cookie path" $ do
    -- The pool argument is never evaluated on requests with no cookie.

    it "passes requests through unchanged when no Cookie header present" $ do
      resp <- runSession
        (request defaultRequest)
        (noCookieMiddleware authEchoApp)
      simpleBody resp `shouldBe` "no-auth"

    it "returns 200 when no cookie present" $ do
      resp <- runSession
        (request defaultRequest)
        (noCookieMiddleware authEchoApp)
      simpleStatus resp `shouldBe` status200

    it "does not inject Authorization header when no cookie present" $ do
      resp <- runSession
        (request defaultRequest)
        (noCookieMiddleware authEchoApp)
      simpleBody resp `shouldBe` "no-auth"

    it "does not add Set-Cookie to response when no request cookie" $ do
      resp <- runSession
        (request defaultRequest)
        (noCookieMiddleware authEchoApp)
      lookup "Set-Cookie" (simpleHeaders resp) `shouldBe` Nothing

    it "passes through existing Authorization header when no cookie present" $ do
      let req = defaultRequest
            { requestHeaders = [("Authorization", "Bearer existingtoken")] }
      resp <- runSession
        (request req)
        (noCookieMiddleware authEchoApp)
      -- The existing header is passed through; the app sees it
      simpleBody resp `shouldBe` "Bearer existingtoken"

    it "passes through non-cheeblr cookies without injecting auth" $ do
      let req = defaultRequest
            { requestHeaders = [("Cookie", "other_cookie=value")] }
      resp <- runSession
        (request req)
        (noCookieMiddleware authEchoApp)
      simpleBody resp `shouldBe` "no-auth"