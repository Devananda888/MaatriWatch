-- MaatriWatch Phase 2: replay-safe telemetry, alert episodes, and Firebase outbox.
-- Apply after 001_initial_schema.sql.

ALTER TABLE vital_readings
    ADD COLUMN source_event_id TEXT,
    ADD COLUMN source_sequence INTEGER CHECK (source_sequence >= 0),
    ADD COLUMN payload_fingerprint CHAR(64),
    ADD COLUMN blood_loss_ml NUMERIC(8,2) CHECK (blood_loss_ml BETWEEN 0 AND 10000),
    ADD COLUMN bleeding_reported BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN motion JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE vital_readings
    ADD CONSTRAINT vital_readings_source_event_id_length
    CHECK (source_event_id IS NULL OR char_length(source_event_id) BETWEEN 1 AND 128);

-- Existing Phase 1 rows may not have a device event ID. New ingestion always
-- supplies one; the partial index preserves migration compatibility.
CREATE UNIQUE INDEX vital_readings_device_source_event_unique
    ON vital_readings(device_id, source_event_id)
    WHERE source_event_id IS NOT NULL;
CREATE INDEX vital_readings_device_captured_idx
    ON vital_readings(device_id, captured_at DESC);

ALTER TABLE alerts
    ADD COLUMN rule_id TEXT,
    ADD COLUMN rule_version TEXT,
    ADD COLUMN dedupe_key TEXT,
    ADD COLUMN evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN last_seen_at TIMESTAMPTZ,
    ADD COLUMN occurrence_count INTEGER NOT NULL DEFAULT 1 CHECK (occurrence_count > 0);

-- There can be only one unresolved episode of a rule for a patient. Repeated
-- five-second breaches update last_seen_at/occurrence_count instead of paging
-- a clinician repeatedly. Resolved alerts intentionally do not block a new episode.
CREATE UNIQUE INDEX alerts_active_episode_unique
    ON alerts(hospital_id, patient_id, dedupe_key)
    WHERE dedupe_key IS NOT NULL AND status IN ('open', 'acknowledged', 'escalated');
CREATE INDEX alerts_patient_active_idx
    ON alerts(patient_id, status, severity, last_seen_at DESC);

-- Preserve every reading that contributed to an alert episode. This makes an
-- idempotent retry return the same alert IDs even after a later reading updates
-- alerts.vital_reading_id to the newest evidence.
CREATE TABLE alert_observations (
    alert_id UUID NOT NULL REFERENCES alerts(id),
    vital_reading_id UUID NOT NULL REFERENCES vital_readings(id),
    rule_version TEXT NOT NULL,
    evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
    observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (alert_id, vital_reading_id)
);
CREATE INDEX alert_observations_reading_idx ON alert_observations(vital_reading_id);

CREATE TABLE realtime_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic TEXT NOT NULL CHECK (topic IN ('live_vitals', 'live_alert')),
    payload JSONB NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE,
    delivery_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (delivery_status IN ('pending', 'processing', 'delivered')),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    locked_at TIMESTAMPTZ,
    locked_by TEXT,
    delivered_at TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX realtime_outbox_pending_idx
    ON realtime_outbox(delivery_status, available_at, created_at)
    WHERE delivery_status <> 'delivered';

-- Strengthen Phase 1's tenant check: a reading must use the device's current
-- assignment, not merely any device at the same hospital.
CREATE OR REPLACE FUNCTION enforce_reading_hospital_match()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM patients p
        WHERE p.id = NEW.patient_id AND p.hospital_id = NEW.hospital_id AND p.is_active = true
    ) THEN
        RAISE EXCEPTION 'Reading patient must be active and belong to reading hospital';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM devices d
        WHERE d.id = NEW.device_id
          AND d.hospital_id = NEW.hospital_id
          AND d.status = 'assigned'
          AND d.assigned_patient_id = NEW.patient_id
    ) THEN
        RAISE EXCEPTION 'Reading device must be assigned to its reading patient';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION enforce_alert_hospital_match()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM patients p WHERE p.id = NEW.patient_id AND p.hospital_id = NEW.hospital_id
    ) THEN
        RAISE EXCEPTION 'Alert patient must belong to alert hospital';
    END IF;
    IF NEW.vital_reading_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM vital_readings vr
        WHERE vr.id = NEW.vital_reading_id
          AND vr.patient_id = NEW.patient_id
          AND vr.hospital_id = NEW.hospital_id
    ) THEN
        RAISE EXCEPTION 'Alert reading must belong to the alert patient and hospital';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER alerts_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, patient_id, vital_reading_id ON alerts
FOR EACH ROW EXECUTE FUNCTION enforce_alert_hospital_match();
