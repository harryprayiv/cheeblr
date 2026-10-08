{-# LANGUAGE OverloadedStrings #-}

-- | The sale tables and the rules the database enforces on them.
module DB.Transaction.Tables (
  createTransactionTables,
  createSaleConstraints,
) where

import Data.ByteString (ByteString)
import qualified Hasql.Session as Session
import qualified Hasql.Statement as Statement

import DB.Database (DBPool, ddl, runSession)

createTransactionTables :: DBPool -> IO ()
createTransactionTables pool = do
  runSession pool $ do
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS transaction (\
        \  id                        UUID PRIMARY KEY,\
        \  status                    TEXT NOT NULL,\
        \  created                   TIMESTAMP WITH TIME ZONE NOT NULL,\
        \  completed                 TIMESTAMP WITH TIME ZONE,\
        \  customer_id               UUID,\
        \  employee_id               UUID NOT NULL,\
        \  register_id               UUID NOT NULL,\
        \  location_id               UUID NOT NULL,\
        \  subtotal                  INTEGER NOT NULL,\
        \  discount_total            INTEGER NOT NULL,\
        \  tax_total                 INTEGER NOT NULL,\
        \  total                     INTEGER NOT NULL,\
        \  transaction_type          TEXT NOT NULL,\
        \  is_voided                 BOOLEAN NOT NULL DEFAULT FALSE,\
        \  void_reason               TEXT,\
        \  is_refunded               BOOLEAN NOT NULL DEFAULT FALSE,\
        \  refund_reason             TEXT,\
        \  reference_transaction_id  UUID,\
        \  notes                     TEXT\
        \)"
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS register (\
        \  id                      UUID PRIMARY KEY,\
        \  name                    TEXT NOT NULL,\
        \  location_id             UUID NOT NULL,\
        \  is_open                 BOOLEAN NOT NULL DEFAULT FALSE,\
        \  current_drawer_amount   INTEGER NOT NULL DEFAULT 0,\
        \  expected_drawer_amount  INTEGER NOT NULL DEFAULT 0,\
        \  opened_at               TIMESTAMP WITH TIME ZONE,\
        \  opened_by               UUID,\
        \  last_transaction_time   TIMESTAMP WITH TIME ZONE\
        \)"
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS inventory_reservation (\
        \  id              UUID PRIMARY KEY,\
        \  item_sku        UUID NOT NULL,\
        \  transaction_id  UUID NOT NULL,\
        \  quantity        INTEGER NOT NULL,\
        \  status          TEXT NOT NULL,\
        \  created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()\
        \)"
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS transaction_item (\
        \  id              UUID PRIMARY KEY,\
        \  transaction_id  UUID NOT NULL REFERENCES transaction(id) ON DELETE CASCADE,\
        \  menu_item_sku   UUID NOT NULL,\
        \  quantity        INTEGER NOT NULL,\
        \  price_per_unit  INTEGER NOT NULL,\
        \  subtotal        INTEGER NOT NULL,\
        \  total           INTEGER NOT NULL\
        \)"
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS transaction_tax (\
        \  id                    UUID PRIMARY KEY,\
        \  transaction_item_id   UUID NOT NULL REFERENCES transaction_item(id) ON DELETE CASCADE,\
        \  category              TEXT NOT NULL,\
        \  rate                  NUMERIC NOT NULL,\
        \  amount                INTEGER NOT NULL,\
        \  description           TEXT NOT NULL\
        \)"
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS discount (\
        \  id                    UUID PRIMARY KEY,\
        \  transaction_item_id   UUID REFERENCES transaction_item(id) ON DELETE CASCADE,\
        \  transaction_id        UUID REFERENCES transaction(id) ON DELETE CASCADE,\
        \  type                  TEXT NOT NULL,\
        \  amount                INTEGER NOT NULL,\
        \  percent               NUMERIC,\
        \  reason                TEXT NOT NULL,\
        \  approved_by           UUID\
        \)"
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS payment_transaction (\
        \  id                 UUID PRIMARY KEY,\
        \  transaction_id     UUID NOT NULL REFERENCES transaction(id) ON DELETE CASCADE,\
        \  method             TEXT NOT NULL,\
        \  amount             INTEGER NOT NULL,\
        \  tendered           INTEGER NOT NULL,\
        \  change_amount      INTEGER NOT NULL,\
        \  reference          TEXT,\
        \  approved           BOOLEAN NOT NULL DEFAULT FALSE,\
        \  authorization_code TEXT\
        \)"
  createSaleConstraints pool

-- | Adds a constraint to a table unless a constraint of that name already
-- exists. PostgreSQL has no ADD CONSTRAINT IF NOT EXISTS, so the check is
-- made against the catalog. The names used here are unique across the
-- database.
addConstraintOnce :: ByteString -> ByteString -> ByteString -> Statement.Statement () ()
addConstraintOnce tableName constraintName definition =
  ddl $
    "DO $$ BEGIN \
    \IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '"
      <> constraintName
      <> "') THEN ALTER TABLE "
      <> tableName
      <> " ADD CONSTRAINT "
      <> constraintName
      <> " "
      <> definition
      <> "; END IF; END $$"

-- | The rules the database enforces on its own, whatever the application
-- does. Each one is a rule the sale commands already keep. A write that
-- breaks one fails and its SQL transaction rolls back.
--
-- This runs at every start and is safe to repeat. It runs after the menu
-- and sale tables exist. It fails, and the backend does not start, when
-- rows already in the database break a rule.
--
-- A line's quantity may be negative because a refund stores negated
-- lines, so the rule for lines is that the quantity is not zero.
--
-- The order of writes in 'DB.Transaction.addTransactionItem' matters to
-- the two unique indexes: it releases the old reservation and deletes the
-- old line before it inserts the new ones.
createSaleConstraints :: DBPool -> IO ()
createSaleConstraints pool =
  runSession pool $ do
    Session.statement () $
      ddl
        "CREATE UNIQUE INDEX IF NOT EXISTS transaction_item_one_line_per_sku \
        \ON transaction_item (transaction_id, menu_item_sku)"
    Session.statement () $
      ddl
        "CREATE UNIQUE INDEX IF NOT EXISTS inventory_reservation_one_live_per_sku \
        \ON inventory_reservation (transaction_id, item_sku) \
        \WHERE status = 'Reserved'"
    Session.statement () $
      addConstraintOnce
        "menu_items"
        "menu_items_quantity_not_negative"
        "CHECK (quantity >= 0)"
    Session.statement () $
      addConstraintOnce
        "transaction_item"
        "transaction_item_quantity_not_zero"
        "CHECK (quantity <> 0)"
    Session.statement () $
      addConstraintOnce
        "inventory_reservation"
        "inventory_reservation_quantity_positive"
        "CHECK (quantity > 0)"
    Session.statement () $
      addConstraintOnce
        "inventory_reservation"
        "inventory_reservation_status_known"
        "CHECK (status IN ('Reserved', 'Released', 'Completed'))"
    Session.statement () $
      addConstraintOnce
        "inventory_reservation"
        "inventory_reservation_transaction_exists"
        "FOREIGN KEY (transaction_id) REFERENCES transaction(id) ON DELETE CASCADE"
    Session.statement () $
      addConstraintOnce
        "transaction"
        "transaction_status_known"
        "CHECK (status IN ('CREATED', 'IN_PROGRESS', 'COMPLETED', 'VOIDED', 'REFUNDED'))"
