{-# LANGUAGE OverloadedStrings #-}

module Test.App.MiddlewareSpec (spec) where

import qualified Data.ByteString.Char8 as B8
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
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
import Types.Primitives.Token (
  SessionToken,
  mkSessionToken,
  revealSessionToken,
 )

-- | A known-good session token used as a fixture across these tests.
-- 43-character base64url-no-padding encoding of 32 zero bytes; matches
-- the wire format produced by 'generateSessionToken' for an all-zero
-- payload. 'error' on parse failure is intentional — it signals that
-- the canonical encoding logic in 'Types.Primitives.Token' is broken.
sampleToken :: SessionToken
sampleToken =
  fromMaybe (error "sampleToken: hardcoded test token failed to parse") $
    mkSessionToken "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

sampleTokenText :: Text
sampleTokenText = revealSessionToken sampleToken

sampleTokenBS :: B8.ByteString
sampleTokenBS = TE.encodeUtf8 sampleTokenText

-- | Echoes the Authorization header value back in the response body.
-- Returns "no-auth" if the header is absent.
authEchoApp :: Application
authEchoApp req respond = do
  let body = case lookup "Authorization" (requestHeaders req) of
        Nothing  -> "no-auth"
        Just val -> val
  respond $ responseLBS status200 [] (B8.fromStrict body)

-- | The pool argument is undefined here intentionally. The no-cookie path
-- (including paths where 'extractCookieToken' short-circuits to Nothing
-- on a malformed cookie) never evaluates it. Full rotation logic
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
            { requestHeaders =
                [("Cookie", "cheeblr_session=" <> sampleTokenBS)] }
      extractCookieToken req `shouldBe` Just sampleToken

    it "extracts token when it is the first of multiple cookies" $ do
      let req = defaultRequest
            { requestHeaders =
                [ ( "Cookie"
                  , "cheeblr_session=" <> sampleTokenBS <> "; other=xyz"
                  )
                ]
            }
      extractCookieToken req `shouldBe` Just sampleToken

    it "extracts token when it is the last of multiple cookies" $ do
      let req = defaultRequest
            { requestHeaders =
                [ ( "Cookie"
                  , "other=xyz; cheeblr_session=" <> sampleTokenBS
                  )
                ]
            }
      extractCookieToken req `shouldBe` Just sampleToken

    it "extracts token when surrounded by other cookies" $ do
      let req = defaultRequest
            { requestHeaders =
                [ ( "Cookie"
                  , "a=1; cheeblr_session=" <> sampleTokenBS <> "; b=2"
                  )
                ]
            }
      extractCookieToken req `shouldBe` Just sampleToken

    it "returns Nothing for a malformed (too short) token value" $ do
      let req = defaultRequest
            { requestHeaders = [("Cookie", "cheeblr_session=mytoken123")] }
      extractCookieToken req `shouldBe` Nothing

    it "returns Nothing for an empty token value" $ do
      let req = defaultRequest
            { requestHeaders = [("Cookie", "cheeblr_session=")] }
      extractCookieToken req `shouldBe` Nothing

    it "returns Nothing for a token with the right length but an invalid character" $ do
      -- 43 chars but contains '*' which is not in the base64url alphabet.
      let badToken = B8.replicate 42 'A' <> "*"
          req = defaultRequest
            { requestHeaders = [("Cookie", "cheeblr_session=" <> badToken)] }
      extractCookieToken req `shouldBe` Nothing

  describe "cookieAuthMiddleware — no-cookie path" $ do
    -- The pool argument is never evaluated on requests where
    -- 'extractCookieToken' returns Nothing.

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
      -- The existing header is passed through; the app sees it.
      simpleBody resp `shouldBe` "Bearer existingtoken"

    it "passes through non-cheeblr cookies without injecting auth" $ do
      let req = defaultRequest
            { requestHeaders = [("Cookie", "other_cookie=value")] }
      resp <- runSession
        (request req)
        (noCookieMiddleware authEchoApp)
      simpleBody resp `shouldBe` "no-auth"

    it "treats a malformed cheeblr_session cookie as no cookie" $ do
      -- 'extractCookieToken' returns Nothing for a malformed token,
      -- so the middleware takes the no-cookie branch and the pool
      -- is never evaluated.
      let req = defaultRequest
            { requestHeaders = [("Cookie", "cheeblr_session=junk")] }
      resp <- runSession
        (request req)
        (noCookieMiddleware authEchoApp)
      simpleBody resp `shouldBe` "no-auth"

    it "does not add Set-Cookie when the request cookie is malformed" $ do
      let req = defaultRequest
            { requestHeaders = [("Cookie", "cheeblr_session=junk")] }
      resp <- runSession
        (request req)
        (noCookieMiddleware authEchoApp)
      lookup "Set-Cookie" (simpleHeaders resp) `shouldBe` Nothing