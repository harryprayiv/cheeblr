{-# LANGUAGE OverloadedStrings #-}

module Server.Cookie (
  sessionCookie,
  clearSessionCookie,
) where

import Data.Text (Text)

-- HttpOnly   – JS cannot read the token
-- Secure     – HTTPS only
-- SameSite=Strict – not sent on cross-site navigation (correct for a POS)
-- Max-Age=28800  – 8 hours, matches session TTL
sessionCookie :: Text -> Text
sessionCookie token =
  "cheeblr_session="
    <> token
    <> "; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=28800"

-- Zero Max-Age evicts the cookie from the browser immediately on logout.
clearSessionCookie :: Text
clearSessionCookie =
  "cheeblr_session=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0"
