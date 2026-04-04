{-# LANGUAGE OverloadedStrings #-}

module Server.Middleware.Tracing (
  tracingMiddleware,
  getTraceId,
  traceIdKey,
) where

import qualified Data.Text.Encoding as TE
import qualified Data.Vault.Lazy as Vault
import Network.Wai (
  Middleware,
  Request,
  mapResponseHeaders,
  requestHeaders,
  vault,
 )
import System.IO.Unsafe (unsafePerformIO)

import Types.Trace (TraceId, newTraceId, parseTraceId, traceIdToText)

traceIdKey :: Vault.Key TraceId
traceIdKey = unsafePerformIO Vault.newKey
{-# NOINLINE traceIdKey #-}

tracingMiddleware :: Middleware
tracingMiddleware app req respond = do
  traceId <- case lookup "X-Trace-Id" (requestHeaders req) of
    Just raw -> maybe newTraceId pure (parseTraceId (TE.decodeUtf8 raw))
    Nothing -> newTraceId
  let req' = req {vault = Vault.insert traceIdKey traceId (vault req)}
  app req' $ \response ->
    respond $
      mapResponseHeaders
        (("X-Trace-Id", TE.encodeUtf8 (traceIdToText traceId)) :)
        response

getTraceId :: Request -> Maybe TraceId
getTraceId = Vault.lookup traceIdKey . vault
