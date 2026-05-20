{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Session token primitives.
--
-- 'SessionToken' is the raw secret transmitted via cookie or
-- Authorization header. It is never persisted; the database stores only
-- its 'SessionTokenHash'. The two are distinct newtypes so the type
-- system prevents mixing raw secrets with stored hashes.
--
-- Wire format and hash format are preserved exactly from the previous
-- 'DB.Auth' implementation: 32 random bytes, transported as base64url
-- without padding, hashed as SHA-256 hex over the raw bytes. Existing
-- session rows remain valid across this refactor.
module Types.Primitives.Token
  ( -- * Raw session token
    SessionToken
  , generateSessionToken
  , mkSessionToken
  , revealSessionToken
    -- * Stored hash
  , SessionTokenHash
  , hashSessionToken
  , sessionTokenHashText
  , unsafeSessionTokenHash
  ) where

import           Crypto.Hash              (Digest, SHA256, hash)
import           Data.ByteArray           (convert)
import qualified Data.ByteArray.Encoding  as BAE
import           Data.ByteString          (ByteString)
import qualified Data.ByteString          as BS
import qualified Data.ByteString.Base64.URL as B64U
import           Data.Text                (Text)
import qualified Data.Text                as T
import qualified Data.Text.Encoding       as TE
import           System.Entropy           (getEntropy)

-- | A session token's raw secret value.
--
-- The internal representation is the 32 random bytes from the kernel
-- CSPRNG. The base64url-without-padding text seen on the wire is a
-- transport encoding produced by 'revealSessionToken' and consumed by
-- 'mkSessionToken'.
--
-- The 'Show' instance redacts the value to prevent accidental leakage
-- via logging. To get the wire text out, use 'revealSessionToken'
-- explicitly.
newtype SessionToken = SessionToken ByteString
  deriving stock (Eq)

instance Show SessionToken where
  show _ = "SessionToken <redacted>"

-- | Generate a fresh session token: 32 bytes from the kernel CSPRNG.
generateSessionToken :: IO SessionToken
generateSessionToken = SessionToken <$> getEntropy 32

-- | Parse a session token from a cookie or Authorization header value.
--
-- Returns 'Nothing' for any input that is not a valid base64url
-- encoding of exactly 32 bytes. This short-circuits malformed tokens
-- before reaching the database, and rejects junk that happens to be
-- the right length but isn't a real token.
--
-- Accepts both padded (44-char) and unpadded (43-char) base64url
-- input; the canonical wire form is unpadded.
mkSessionToken :: Text -> Maybe SessionToken
mkSessionToken t =
  case B64U.decode (TE.encodeUtf8 (rePad t)) of
    Right bs | BS.length bs == 32 -> Just (SessionToken bs)
    _                             -> Nothing

-- | Extract the wire-format text of a session token.
--
-- This is the only way out of the newtype back to plain 'Text'. The
-- function is deliberately named so that occurrences are obvious in
-- code review: every call site is somewhere a raw secret is leaving
-- the type system.
revealSessionToken :: SessionToken -> Text
revealSessionToken (SessionToken bs) = stripPad (TE.decodeUtf8 (B64U.encode bs))

-- | SHA-256 hash of a session token's raw bytes, hex-encoded.
--
-- This is the form persisted in the database; raw tokens never are.
-- 'SessionTokenHash' is a distinct newtype from 'SessionToken' so the
-- type system prevents mixing the two (e.g. comparing a raw token
-- against a stored hash, or writing a raw token into the hash column).
newtype SessionTokenHash = SessionTokenHash Text
  deriving stock (Eq)
  deriving newtype (Ord)

instance Show SessionTokenHash where
  show (SessionTokenHash h) =
    "SessionTokenHash " <> T.unpack (T.take 8 h) <> "..."

-- | Hash a session token for database storage and lookup.
hashSessionToken :: SessionToken -> SessionTokenHash
hashSessionToken (SessionToken bs) =
  let digest :: Digest SHA256
      digest  = hash bs
      hex     = TE.decodeUtf8
                  (BAE.convertToBase BAE.Base16 (convert digest :: ByteString))
  in SessionTokenHash hex

-- | The hex text of a session token hash, for use in SQL.
sessionTokenHashText :: SessionTokenHash -> Text
sessionTokenHashText (SessionTokenHash h) = h

-- | Construct a hash from existing hex text, for row decoding paths
-- where the hash already exists in the database. Does not validate
-- that the input is actually a SHA-256 hex digest; use only at the
-- DB boundary.
unsafeSessionTokenHash :: Text -> SessionTokenHash
unsafeSessionTokenHash = SessionTokenHash

-- internal helpers

stripPad :: Text -> Text
stripPad = T.dropWhileEnd (== '=')

rePad :: Text -> Text
rePad t = case T.length t `mod` 4 of
  0 -> t
  n -> t <> T.replicate (4 - n) "="