{-# LANGUAGE OverloadedStrings #-}

-- | Set-Cookie header construction for the session cookie.
--
-- The cookie name is @cheeblr_session@. Attributes are fixed:
-- HttpOnly, Secure, SameSite=Strict, Path=/, Max-Age=28800 (8 hours,
-- matching the hardcoded session TTL in 'DB.Auth.createSession').
--
-- If the session TTL is ever made configurable, the Max-Age value
-- here must be threaded from the same source.
module Server.Cookie
  ( sessionCookie
  , clearSessionCookie
  ) where

import           Data.Text                (Text)
import qualified Data.Text                as T

import           Types.Primitives.Token   (SessionToken, revealSessionToken)

-- | Construct the Set-Cookie value that installs a session cookie
-- carrying the given token.
sessionCookie :: SessionToken -> Text
sessionCookie tok =
  T.concat
    [ "cheeblr_session="
    , revealSessionToken tok
    , "; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=28800"
    ]

-- | Set-Cookie value that immediately expires the session cookie.
clearSessionCookie :: Text
clearSessionCookie =
  "cheeblr_session=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0"