{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module DB.Stock
  ( createStockTables
  , insertPullRequest
  , getPullRequest
  , updatePullStatus
  , getPendingPulls
  , getPullsByTransaction
  , insertPullMessage
  , getPullMessages
  , cancelPullsForTransaction
  ) where

import           Data.Functor.Contravariant      ((>$<))
import           Data.Text                       (Text)
import           Data.Time                       (UTCTime, getCurrentTime)
import           Data.UUID                       (UUID)
import qualified Hasql.Decoders                 as Decoders
import qualified Hasql.Encoders                 as Encoders
import qualified Hasql.Session                  as Session
import qualified Hasql.Statement                as Statement

import           DB.Database                     (DBPool, ddl, runSession)
import           State.StockPullMachine          (PullVertex (..))
import           Types.Location                  (LocationId (..), locationIdToUUID)
import           Types.Stock

createStockTables :: DBPool -> IO ()
createStockTables pool = runSession pool $ do
  Session.statement () $ ddl
    "CREATE TABLE IF NOT EXISTS stock_pull_requests (\
    \  id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),\
    \  transaction_id   UUID         NOT NULL,\
    \  item_sku         UUID         NOT NULL,\
    \  item_name        TEXT         NOT NULL,\
    \  quantity_needed  INT          NOT NULL CHECK (quantity_needed > 0),\
    \  status           TEXT         NOT NULL DEFAULT 'PullPending',\
    \  cashier_id       UUID,\
    \  register_id      UUID,\
    \  location_id      UUID         NOT NULL,\
    \  created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),\
    \  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),\
    \  fulfilled_at     TIMESTAMPTZ\
    \)"
  Session.statement () $ ddl
    "CREATE TABLE IF NOT EXISTS stock_pull_messages (\
    \  id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),\
    \  pull_request_id UUID         NOT NULL REFERENCES stock_pull_requests(id),\
    \  from_role       TEXT         NOT NULL,\
    \  sender_id       UUID         NOT NULL,\
    \  message         TEXT         NOT NULL,\
    \  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()\
    \)"
  Session.statement () $ ddl
    "CREATE INDEX IF NOT EXISTS idx_pull_location_status \
    \ON stock_pull_requests (location_id, status, created_at)"
  Session.statement () $ ddl
    "CREATE INDEX IF NOT EXISTS idx_pull_transaction \
    \ON stock_pull_requests (transaction_id)"
  Session.statement () $ ddl
    "CREATE INDEX IF NOT EXISTS idx_pull_messages \
    \ON stock_pull_messages (pull_request_id, created_at)"

vertexToText :: PullVertex -> Text
vertexToText PullPending   = "PullPending"
vertexToText PullAccepted  = "PullAccepted"
vertexToText PullPulling   = "PullPulling"
vertexToText PullFulfilled = "PullFulfilled"
vertexToText PullCancelled = "PullCancelled"
vertexToText PullIssue     = "PullIssue"

textToVertex :: Text -> PullVertex
textToVertex "PullPending"   = PullPending
textToVertex "PullAccepted"  = PullAccepted
textToVertex "PullPulling"   = PullPulling
textToVertex "PullFulfilled" = PullFulfilled
textToVertex "PullCancelled" = PullCancelled
textToVertex "PullIssue"     = PullIssue
textToVertex _               = PullPending

decodePullRequest :: Decoders.Row PullRequest
decodePullRequest =
  PullRequest
    <$> Decoders.column (Decoders.nonNullable Decoders.uuid)
    <*> Decoders.column (Decoders.nonNullable Decoders.uuid)
    <*> Decoders.column (Decoders.nonNullable Decoders.uuid)
    <*> Decoders.column (Decoders.nonNullable Decoders.text)
    <*> (fromIntegral <$> Decoders.column (Decoders.nonNullable Decoders.int4))
    <*> (textToVertex <$> Decoders.column (Decoders.nonNullable Decoders.text))
    <*> Decoders.column (Decoders.nullable Decoders.uuid)
    <*> Decoders.column (Decoders.nullable Decoders.uuid)
    <*> (LocationId <$> Decoders.column (Decoders.nonNullable Decoders.uuid))
    <*> Decoders.column (Decoders.nonNullable Decoders.timestamptz)
    <*> Decoders.column (Decoders.nonNullable Decoders.timestamptz)
    <*> Decoders.column (Decoders.nullable Decoders.timestamptz)

insertPullRequest :: DBPool -> PullRequest -> IO ()
insertPullRequest pool pr = runSession pool $
  Session.statement
    ( prId pr, prTransactionId pr, prItemSku pr, prItemName pr
    , fromIntegral (prQuantityNeeded pr) :: Int
    , vertexToText (prStatus pr)
    , prCashierId pr, prRegisterId pr
    , locationIdToUUID (prLocationId pr)
    , prCreatedAt pr, prUpdatedAt pr, prFulfilledAt pr
    )
    insertStmt
  where
    insertStmt :: Statement.Statement
      (UUID, UUID, UUID, Text, Int, Text, Maybe UUID, Maybe UUID, UUID, UTCTime, UTCTime, Maybe UTCTime) ()
    insertStmt = Statement.Statement
      "INSERT INTO stock_pull_requests \
      \(id, transaction_id, item_sku, item_name, quantity_needed, status, \
      \ cashier_id, register_id, location_id, created_at, updated_at, fulfilled_at) \
      \VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)"
      ( ((\(a,_,_,_,_,_,_,_,_,_,_,_) -> a) >$< Encoders.param (Encoders.nonNullable Encoders.uuid))
     <> ((\(_,b,_,_,_,_,_,_,_,_,_,_) -> b) >$< Encoders.param (Encoders.nonNullable Encoders.uuid))
     <> ((\(_,_,c,_,_,_,_,_,_,_,_,_) -> c) >$< Encoders.param (Encoders.nonNullable Encoders.uuid))
     <> ((\(_,_,_,d,_,_,_,_,_,_,_,_) -> d) >$< Encoders.param (Encoders.nonNullable Encoders.text))
     <> ((\(_,_,_,_,e,_,_,_,_,_,_,_) -> fromIntegral e) >$< Encoders.param (Encoders.nonNullable Encoders.int4))
     <> ((\(_,_,_,_,_,f,_,_,_,_,_,_) -> f) >$< Encoders.param (Encoders.nonNullable Encoders.text))
     <> ((\(_,_,_,_,_,_,g,_,_,_,_,_) -> g) >$< Encoders.param (Encoders.nullable Encoders.uuid))
     <> ((\(_,_,_,_,_,_,_,h,_,_,_,_) -> h) >$< Encoders.param (Encoders.nullable Encoders.uuid))
     <> ((\(_,_,_,_,_,_,_,_,i,_,_,_) -> i) >$< Encoders.param (Encoders.nonNullable Encoders.uuid))
     <> ((\(_,_,_,_,_,_,_,_,_,j,_,_) -> j) >$< Encoders.param (Encoders.nonNullable Encoders.timestamptz))
     <> ((\(_,_,_,_,_,_,_,_,_,_,k,_) -> k) >$< Encoders.param (Encoders.nonNullable Encoders.timestamptz))
     <> ((\(_,_,_,_,_,_,_,_,_,_,_,l) -> l) >$< Encoders.param (Encoders.nullable Encoders.timestamptz))
      )
      Decoders.noResult
      False

getPullRequest :: DBPool -> UUID -> IO (Maybe PullRequest)
getPullRequest pool pullId = do
  rows <- runSession pool $
    Session.statement pullId $
      Statement.Statement
        "SELECT id, transaction_id, item_sku, item_name, quantity_needed, status, \
        \cashier_id, register_id, location_id, created_at, updated_at, fulfilled_at \
        \FROM stock_pull_requests WHERE id = $1"
        (Encoders.param (Encoders.nonNullable Encoders.uuid))
        (Decoders.rowList decodePullRequest)
        False
  case rows of
    [r] -> pure (Just r)
    _   -> pure Nothing

updatePullStatus :: DBPool -> UUID -> PullVertex -> Maybe Text -> IO ()
updatePullStatus pool pullId newStatus mNote = do
  now <- getCurrentTime
  runSession pool $
    Session.statement (vertexToText newStatus, now, mNote, pullId) $
      Statement.Statement
        "UPDATE stock_pull_requests SET status = $1, updated_at = $2 WHERE id = $4"
        ( ((\(a,_,_,_) -> a) >$< Encoders.param (Encoders.nonNullable Encoders.text))
       <> ((\(_,b,_,_) -> b) >$< Encoders.param (Encoders.nonNullable Encoders.timestamptz))
       <> ((\(_,_,c,_) -> c) >$< Encoders.param (Encoders.nullable Encoders.text))
       <> ((\(_,_,_,d) -> d) >$< Encoders.param (Encoders.nonNullable Encoders.uuid))
        )
        Decoders.noResult
        False

getPendingPulls :: DBPool -> LocationId -> IO [PullRequest]
getPendingPulls pool locId =
  runSession pool $
    Session.statement (locationIdToUUID locId) $
      Statement.Statement
        "SELECT id, transaction_id, item_sku, item_name, quantity_needed, status, \
        \cashier_id, register_id, location_id, created_at, updated_at, fulfilled_at \
        \FROM stock_pull_requests \
        \WHERE location_id = $1 \
        \  AND status NOT IN ('PullFulfilled', 'PullCancelled') \
        \ORDER BY created_at ASC"
        (Encoders.param (Encoders.nonNullable Encoders.uuid))
        (Decoders.rowList decodePullRequest)
        False

getPullsByTransaction :: DBPool -> UUID -> IO [PullRequest]
getPullsByTransaction pool txId =
  runSession pool $
    Session.statement txId $
      Statement.Statement
        "SELECT id, transaction_id, item_sku, item_name, quantity_needed, status, \
        \cashier_id, register_id, location_id, created_at, updated_at, fulfilled_at \
        \FROM stock_pull_requests WHERE transaction_id = $1 ORDER BY created_at ASC"
        (Encoders.param (Encoders.nonNullable Encoders.uuid))
        (Decoders.rowList decodePullRequest)
        False

decodePullMessage :: Decoders.Row PullMessage
decodePullMessage =
  PullMessage
    <$> Decoders.column (Decoders.nonNullable Decoders.uuid)
    <*> Decoders.column (Decoders.nonNullable Decoders.uuid)
    <*> Decoders.column (Decoders.nonNullable Decoders.text)
    <*> Decoders.column (Decoders.nonNullable Decoders.uuid)
    <*> Decoders.column (Decoders.nonNullable Decoders.text)
    <*> Decoders.column (Decoders.nonNullable Decoders.timestamptz)

insertPullMessage :: DBPool -> UUID -> PullMessage -> IO ()
insertPullMessage pool pullId msg = runSession pool $
  Session.statement
    (pmId msg, pullId, pmFromRole msg, pmSenderId msg, pmMessage msg, pmCreatedAt msg) $
    Statement.Statement
      "INSERT INTO stock_pull_messages (id, pull_request_id, from_role, sender_id, message, created_at) \
      \VALUES ($1,$2,$3,$4,$5,$6)"
      ( ((\(a,_,_,_,_,_) -> a) >$< Encoders.param (Encoders.nonNullable Encoders.uuid))
     <> ((\(_,b,_,_,_,_) -> b) >$< Encoders.param (Encoders.nonNullable Encoders.uuid))
     <> ((\(_,_,c,_,_,_) -> c) >$< Encoders.param (Encoders.nonNullable Encoders.text))
     <> ((\(_,_,_,d,_,_) -> d) >$< Encoders.param (Encoders.nonNullable Encoders.uuid))
     <> ((\(_,_,_,_,e,_) -> e) >$< Encoders.param (Encoders.nonNullable Encoders.text))
     <> ((\(_,_,_,_,_,f) -> f) >$< Encoders.param (Encoders.nonNullable Encoders.timestamptz))
      )
      Decoders.noResult
      False

getPullMessages :: DBPool -> UUID -> IO [PullMessage]
getPullMessages pool pullId =
  runSession pool $
    Session.statement pullId $
      Statement.Statement
        "SELECT id, pull_request_id, from_role, sender_id, message, created_at \
        \FROM stock_pull_messages WHERE pull_request_id = $1 ORDER BY created_at ASC"
        (Encoders.param (Encoders.nonNullable Encoders.uuid))
        (Decoders.rowList decodePullMessage)
        False

cancelPullsForTransaction :: DBPool -> UUID -> Text -> IO ()
cancelPullsForTransaction pool txId _reason = do
  now <- getCurrentTime
  runSession pool $
    Session.statement (vertexToText PullCancelled, now, txId) $
      Statement.Statement
        "UPDATE stock_pull_requests \
        \SET status = $1, updated_at = $2 \
        \WHERE transaction_id = $3 \
        \  AND status NOT IN ('PullFulfilled', 'PullCancelled')"
        ( ((\(a,_,_) -> a) >$< Encoders.param (Encoders.nonNullable Encoders.text))
       <> ((\(_,b,_) -> b) >$< Encoders.param (Encoders.nonNullable Encoders.timestamptz))
       <> ((\(_,_,c) -> c) >$< Encoders.param (Encoders.nonNullable Encoders.uuid))
        )
        Decoders.noResult
        False