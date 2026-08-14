-- MaatriWatch Phase 3: clinician-dashboard state transitions and query support.
-- Apply after 002_ingestion_alerting.sql.

ALTER TABLE alerts
    ADD COLUMN escalated_by UUID REFERENCES app_users(id),
    ADD COLUMN escalated_at TIMESTAMPTZ,
    ADD COLUMN escalation_note TEXT,
    ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Alert updates originate from either telemetry (new evidence) or a clinician
-- workflow.  The timestamp lets the RTDB projection safely replace older data.
CREATE OR REPLACE FUNCTION set_alert_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER alerts_set_updated_at
BEFORE UPDATE ON alerts
FOR EACH ROW EXECUTE FUNCTION set_alert_updated_at();

CREATE INDEX alerts_hospital_active_updated_idx
    ON alerts(hospital_id, updated_at DESC)
    WHERE status IN ('open', 'acknowledged', 'escalated');
CREATE INDEX alerts_hospital_patient_updated_idx
    ON alerts(hospital_id, patient_id, updated_at DESC);
CREATE INDEX devices_assigned_patient_idx
    ON devices(assigned_patient_id, last_seen_at DESC)
    WHERE status = 'assigned';

-- Keep clinical notes inside the same hospital tenant even if a future job
-- bypasses Flask's route-level checks.
CREATE OR REPLACE FUNCTION enforce_clinical_note_hospital_match()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM patients p
        WHERE p.id = NEW.patient_id AND p.hospital_id = NEW.hospital_id
    ) THEN
        RAISE EXCEPTION 'Clinical note patient must belong to note hospital';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER clinical_notes_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON clinical_notes
FOR EACH ROW EXECUTE FUNCTION enforce_clinical_note_hospital_match();
