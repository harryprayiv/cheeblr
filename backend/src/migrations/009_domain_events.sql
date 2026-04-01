CREATE TABLE domain_events (
    seq          BIGSERIAL    PRIMARY KEY,
    id           UUID         NOT NULL DEFAULT gen_random_uuid(),
    type         TEXT         NOT NULL,
    aggregate_id UUID         NOT NULL,
    trace_id     UUID,
    actor_id     UUID,
    location_id  UUID,
    payload      JSONB        NOT NULL,
    occurred_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_domain_events_aggregate ON domain_events (aggregate_id, seq);
CREATE INDEX idx_domain_events_type      ON domain_events (type, seq);
CREATE INDEX idx_domain_events_trace     ON domain_events (trace_id) WHERE trace_id IS NOT NULL;
CREATE INDEX idx_domain_events_location  ON domain_events (location_id, seq) WHERE location_id IS NOT NULL;
CREATE INDEX idx_domain_events_occurred  ON domain_events (occurred_at);

CREATE RULE domain_events_no_update AS ON UPDATE TO domain_events DO INSTEAD NOTHING;
CREATE RULE domain_events_no_delete AS ON DELETE TO domain_events DO INSTEAD NOTHING;