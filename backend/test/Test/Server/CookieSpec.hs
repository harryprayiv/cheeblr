{-# LANGUAGE OverloadedStrings #-}

module Test.Server.CookieSpec (spec) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec

import Server.Cookie (clearSessionCookie, sessionCookie)
import Types.Primitives.Token (
  SessionToken,
  mkSessionToken,
  revealSessionToken,
 )

-- | Two distinct valid session tokens for use across tests.
--
-- Each input string is a 43-character base64url-no-padding encoding of
-- 32 bytes (the canonical wire format produced by 'generateSessionToken').
-- 'sampleToken1' decodes to 32 zero bytes; 'sampleToken2' decodes to a
-- byte sequence beginning 0x04 followed by 31 zero bytes — same length,
-- different content, so cookie strings built from them must differ.
--
-- 'error' on parse failure is intentional: these are compile-time
-- constants and a failure here means the canonical encoding logic in
-- 'Types.Primitives.Token' is wrong, which the test suite should
-- surface immediately.
sampleToken1, sampleToken2 :: SessionToken
sampleToken1 =
  fromMaybe (error "sampleToken1: hardcoded test token failed to parse") $
    mkSessionToken "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
sampleToken2 =
  fromMaybe (error "sampleToken2: hardcoded test token failed to parse") $
    mkSessionToken "BAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

sampleTokenText1 :: Text
sampleTokenText1 = revealSessionToken sampleToken1

spec :: Spec
spec = describe "Server.Cookie" $ do

  describe "sessionCookie" $ do
    it "starts with cheeblr_session=<wire-text>" $
      sessionCookie sampleToken1
        `shouldSatisfy` T.isPrefixOf ("cheeblr_session=" <> sampleTokenText1)

    it "embeds the token's wire text verbatim" $
      sessionCookie sampleToken1
        `shouldSatisfy` T.isInfixOf ("cheeblr_session=" <> sampleTokenText1)

    it "contains HttpOnly" $
      sessionCookie sampleToken1 `shouldSatisfy` T.isInfixOf "HttpOnly"

    it "contains Secure" $
      sessionCookie sampleToken1 `shouldSatisfy` T.isInfixOf "Secure"

    it "contains SameSite=Strict" $
      sessionCookie sampleToken1 `shouldSatisfy` T.isInfixOf "SameSite=Strict"

    it "contains Path=/" $
      sessionCookie sampleToken1 `shouldSatisfy` T.isInfixOf "Path=/"

    it "contains Max-Age=28800 (8 hours)" $
      sessionCookie sampleToken1 `shouldSatisfy` T.isInfixOf "Max-Age=28800"

    it "different tokens produce different cookie strings" $
      sessionCookie sampleToken1 `shouldNotBe` sessionCookie sampleToken2

    it "does not contain Max-Age=0 (would evict immediately)" $
      sessionCookie sampleToken1 `shouldNotSatisfy` T.isInfixOf "Max-Age=0"

  describe "clearSessionCookie" $ do
    it "starts with cheeblr_session=" $
      clearSessionCookie `shouldSatisfy` T.isPrefixOf "cheeblr_session="

    it "has Max-Age=0 to evict the cookie immediately" $
      clearSessionCookie `shouldSatisfy` T.isInfixOf "Max-Age=0"

    it "contains HttpOnly" $
      clearSessionCookie `shouldSatisfy` T.isInfixOf "HttpOnly"

    it "contains Secure" $
      clearSessionCookie `shouldSatisfy` T.isInfixOf "Secure"

    it "contains SameSite=Strict" $
      clearSessionCookie `shouldSatisfy` T.isInfixOf "SameSite=Strict"

    it "does not contain Max-Age=28800" $
      clearSessionCookie `shouldNotSatisfy` T.isInfixOf "Max-Age=28800"

    it "is distinct from a session cookie for any token" $
      clearSessionCookie `shouldNotBe` sessionCookie sampleToken1

    it "the session value is empty (overwrites with blank)" $
      clearSessionCookie `shouldSatisfy` T.isInfixOf "cheeblr_session=;"