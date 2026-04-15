{-# LANGUAGE OverloadedStrings #-}

module Test.Server.CookieSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec

import Server.Cookie (clearSessionCookie, sessionCookie)

spec :: Spec
spec = describe "Server.Cookie" $ do
  describe "sessionCookie" $ do
    it "starts with cheeblr_session=<token>" $ do
      sessionCookie "tok123"
        `shouldSatisfy` T.isPrefixOf "cheeblr_session=tok123"

    it "embeds the token verbatim" $ do
      let token = "abc-XYZ_123"
      sessionCookie token
        `shouldSatisfy` T.isInfixOf ("cheeblr_session=" <> token)

    it "contains HttpOnly" $
      sessionCookie "t" `shouldSatisfy` T.isInfixOf "HttpOnly"

    it "contains Secure" $
      sessionCookie "t" `shouldSatisfy` T.isInfixOf "Secure"

    it "contains SameSite=Strict" $
      sessionCookie "t" `shouldSatisfy` T.isInfixOf "SameSite=Strict"

    it "contains Path=/" $
      sessionCookie "t" `shouldSatisfy` T.isInfixOf "Path=/"

    it "contains Max-Age=28800 (8 hours)" $
      sessionCookie "t" `shouldSatisfy` T.isInfixOf "Max-Age=28800"

    it "different tokens produce different cookie strings" $
      sessionCookie "token1" `shouldNotBe` sessionCookie "token2"

    it "does not contain Max-Age=0 (would evict immediately)" $
      sessionCookie "t" `shouldNotSatisfy` T.isInfixOf "Max-Age=0"

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
      clearSessionCookie `shouldNotBe` sessionCookie "anytoken"

    it "the session value is empty (overwrites with blank)" $
      -- cheeblr_session= with nothing after the = before the first ;
      clearSessionCookie `shouldSatisfy` T.isInfixOf "cheeblr_session=;"
