{-# LANGUAGE OverloadedStrings #-}

module DB.Events
  ( createEventsTables
  , insertDomainEvent
  ) where

import           Data.Aeson                   (encode)
import qualified Data.ByteString              as BS
import qualified Data.ByteString.Lazy         as LBS
import           Data.Functor.Contravariant    ((>$<))
import           Data.Text                    (Text)
import           Data.Time                    (UTCTime, getCurrentTime)
import           Data.UUID                    (UUID)
import           Data.UUID.V4                 (nextRandom)
import qualified Hasql.Decoders               as Decoders
import qualified Hasql.Encoders               as Encoders
import qualified Hasql.Session                as Session
import qualified Hasql.Statement              as Statement

import           DB.Database                  (DBPool, ddl, runSession)
import qualified Types.Events.Domain          as D
import qualified Types.Events.Inventory       as IE
import qualified Types.Events.Register        as RE
import qualified Types.Events.Session         as SE
import qualified Types.Events.Transaction     as TE
import qualified Types.Inventory              as TI
import qualified Types.Transaction            as TT
import           Types.Location               (LocationId, locationIdToUUID)
import           Types.Trace                  (TraceId (..))

createEventsTables :: DBPool -> IO ()
createEventsTables pool = runSession pool $ do
  Session.statement () $ ddl
    "CREATE TABLE IF NOT EXISTS domain_events (\
    \  seq          BIGSERIAL   PRIMARY KEY,\
    \  id           UUID        NOT NULL DEFAULT gen_random_uuid(),\
    \  type         TEXT        NOT NULL,\
    \  aggregate_id UUID        NOT NULL,\
    \  trace_id     UUID,\
    \  actor_id     UUID,\
    \  location_id  UUID,\
    \  payload      JSONB       NOT NULL,\
    \  occurred_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()\
    \)"
  Session.statement () $ ddl
    "CREATE INDEX IF NOT EXISTS idx_domain_events_aggregate \
    \ON domain_events (aggregate_id, seq)"
  Session.statement () $ ddl
    "CREATE INDEX IF NOT EXISTS idx_domain_events_type \
    \ON domain_events (type, seq)"
  Session.statement () $ ddl
    "CREATE INDEX IF NOT EXISTS idx_domain_events_trace \
    \ON domain_events (trace_id) WHERE trace_id IS NOT NULL"
  Session.statement () $ ddl
    "CREATE INDEX IF NOT EXISTS idx_domain_events_location \
    \ON domain_events (location_id, seq) WHERE location_id IS NOT NULL"
  Session.statement () $ ddl
    "CREATE INDEX IF NOT EXISTS idx_domain_events_occurred \
    \ON domain_events (occurred_at)"
  Session.statement () $ ddl
    "DO $$ BEGIN \
    \  IF NOT EXISTS ( \
    \    SELECT 1 FROM pg_rules \
    \    WHERE tablename = 'domain_events' \
    \    AND rulename = 'domain_events_no_update' \
    \  ) THEN \
    \    CREATE RULE domain_events_no_update \
    \    AS ON UPDATE TO domain_events DO INSTEAD NOTHING; \
    \  END IF; \
    \END $$"
  Session.statement () $ ddl
    "DO $$ BEGIN \
    \  IF NOT EXISTS ( \
    \    SELECT 1 FROM pg_rules \
    \    WHERE tablename = 'domain_events' \
    \    AND rulename = 'domain_events_no_delete' \
    \  ) THEN \
    \    CREATE RULE domain_events_no_delete \
    \    AS ON DELETE TO domain_events DO INSTEAD NOTHING; \
    \  END IF; \
    \END $$"

insertDomainEvent
  :: DBPool
  -> Maybe TraceId
  -> Maybe UUID        -- actor
  -> Maybe LocationId  -- location
  -> D.DomainEvent
  -> IO ()
insertDomainEvent pool mTraceId mActorId mLocationId evt = do
  eid <- nextRandom
  now <- getCurrentTime
  let (evtType, aggId) = eventMeta evt
      mTraceUUID       = (\(TraceId u) -> u) <$> mTraceId
      mLocUUID         = locationIdToUUID <$> mLocationId
      payload          = LBS.toStrict (encode evt)
  runSession pool $
    Session.statement
      (eid, evtType, aggId, mTraceUUID, mActorId, mLocUUID, payload, now)
      insertStmt

type Row = (UUID, Text, UUID, Maybe UUID, Maybe UUID, Maybe UUID, BS.ByteString, UTCTime)

insertStmt :: Statement.Statement Row ()
insertStmt = Statement.Statement sql encoder Decoders.noResult False
  where
    sql =
      "INSERT INTO domain_events \
      \  (id, type, aggregate_id, trace_id, actor_id, location_id, payload, occurred_at) \
      \VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8)"
    encoder
      =  ((\(a,_,_,_,_,_,_,_) -> a) >$< Encoders.param (Encoders.nonNullable Encoders.uuid))
      <> ((\(_,b,_,_,_,_,_,_) -> b) >$< Encoders.param (Encoders.nonNullable Encoders.text))
      <> ((\(_,_,c,_,_,_,_,_) -> c) >$< Encoders.param (Encoders.nonNullable Encoders.uuid))
      <> ((\(_,_,_,d,_,_,_,_) -> d) >$< Encoders.param (Encoders.nullable    Encoders.uuid))
      <> ((\(_,_,_,_,e,_,_,_) -> e) >$< Encoders.param (Encoders.nullable    Encoders.uuid))
      <> ((\(_,_,_,_,_,f,_,_) -> f) >$< Encoders.param (Encoders.nullable    Encoders.uuid))
      <> ((\(_,_,_,_,_,_,g,_) -> g) >$< Encoders.param (Encoders.nonNullable Encoders.bytea))
      <> ((\(_,_,_,_,_,_,_,h) -> h) >$< Encoders.param (Encoders.nonNullable Encoders.timestamptz))

eventMeta :: D.DomainEvent -> (Text, UUID)
eventMeta (D.InventoryEvt   ie) = invMeta  ie
eventMeta (D.TransactionEvt te) = txMeta   te
eventMeta (D.RegisterEvt    re) = regMeta  re
eventMeta (D.SessionEvt     se) = sessMeta se

invMeta :: IE.InventoryEvent -> (Text, UUID)
invMeta IE.ItemCreated    { IE.ieItem    = item } = ("inventory.item_created",     TI.sku item)
invMeta IE.ItemUpdated    { IE.ieNewItem = item } = ("inventory.item_updated",     TI.sku item)
invMeta IE.ItemDeleted    { IE.ieSku     = u    } = ("inventory.item_deleted",     u)
invMeta IE.QuantityChanged{ IE.ieItemSku = u    } = ("inventory.quantity_changed", u)

txMeta :: TE.TransactionEvent -> (Text, UUID)
txMeta TE.TransactionCreated      { TE.teTx    = tx } = ("transaction.created",          TT.transactionId tx)
txMeta TE.TransactionItemAdded    { TE.teTxId  = u  } = ("transaction.item_added",       u)
txMeta TE.TransactionItemRemoved  { TE.teTxId  = u  } = ("transaction.item_removed",     u)
txMeta TE.TransactionPaymentAdded { TE.teTxId  = u  } = ("transaction.payment_added",    u)
txMeta TE.TransactionPaymentRemoved{ TE.teTxId = u  } = ("transaction.payment_removed",  u)
txMeta TE.TransactionFinalized    { TE.teTxId  = u  } = ("transaction.finalized",        u)
txMeta TE.TransactionVoided       { TE.teTxId  = u  } = ("transaction.voided",           u)
txMeta TE.TransactionRefunded     { TE.teTxId  = u  } = ("transaction.refunded",         u)

regMeta :: RE.RegisterEvent -> (Text, UUID)
regMeta RE.RegisterOpened{ RE.reRegId = u } = ("register.opened", u)
regMeta RE.RegisterClosed{ RE.reRegId = u } = ("register.closed", u)

sessMeta :: SE.SessionEvent -> (Text, UUID)
sessMeta SE.SessionCreated{ SE.sesUserId = u } = ("session.created", u)
sessMeta SE.SessionExpired{ SE.sesUserId = u } = ("session.expired", u)
sessMeta SE.SessionRevoked{ SE.sesUserId = u } = ("session.revoked", u)