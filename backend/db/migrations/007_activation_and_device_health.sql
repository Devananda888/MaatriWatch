-- Phase 7: hospital-controlled patient activation and non-clinical device health.
--
-- Invitation records deliberately contain no activation URL: Firebase action
-- links are bearer secrets and are returned only once to an authorised care
-- team member.  Postgres retains the auditable lifecycle, not the secret.

CREATE TABLE patient_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    user_id UUID NOT NULL REFERENCES app_users(id),
    issued_by UUID NOT NULL REFERENCES app_users(id),
    status TEXT NOT NULL DEFAULT 'issued'
        CHECK (status IN ('issued', 'activated', 'revoked', 'expired')),
    issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '14 days'),
    activation_link_issued_at TIMESTAMPTZ,
    reissued_at TIMESTAMPTZ,
    activated_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX patient_invitations_one_open_per_patient
    ON patient_invitations(patient_id)
    WHERE status = 'issued';
CREATE INDEX patient_invitations_hospital_status_idx
    ON patient_invitations(hospital_id, status, issued_at DESC);

CREATE OR REPLACE FUNCTION enforce_patient_invitation_hospital_match()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM patients p
        WHERE p.id = NEW.patient_id AND p.hospital_id = NEW.hospital_id
    ) THEN
        RAISE EXCEPTION 'Patient invitation must belong to the patient hospital';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER patient_invitations_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON patient_invitations
FOR EACH ROW EXECUTE FUNCTION enforce_patient_invitation_hospital_match();

CREATE OR REPLACE FUNCTION set_patient_invitation_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER patient_invitations_set_updated_at
BEFORE UPDATE ON patient_invitations
FOR EACH ROW EXECUTE FUNCTION set_patient_invitation_updated_at();

-- These fields describe hardware/connectivity only.  They must never be used
-- to create or elevate a clinical alert.
ALTER TABLE devices
    ADD COLUMN IF NOT EXISTS last_observed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_battery_percent SMALLINT
        CHECK (last_battery_percent BETWEEN 0 AND 100),
    ADD COLUMN IF NOT EXISTS last_sensor_status TEXT
        CHECK (last_sensor_status IN ('ok', 'contact_lost', 'sensor_error', 'unavailable', 'unknown')),
    ADD COLUMN IF NOT EXISTS last_contact_detected BOOLEAN,
    ADD COLUMN IF NOT EXISTS last_signal_quality NUMERIC(5,4)
        CHECK (last_signal_quality BETWEEN 0 AND 1);

CREATE INDEX devices_health_last_seen_idx
    ON devices(hospital_id, last_seen_at DESC);

-- A PPG wearable and a generic external device are not valid blood-pressure
-- sources. Persist only a validated cuff result or a clinician-entered result.
UPDATE vital_readings
   SET systolic_bp = NULL, diastolic_bp = NULL, blood_pressure_source = NULL
 WHERE blood_pressure_source = 'external_validated_device';

ALTER TABLE vital_readings
    DROP CONSTRAINT IF EXISTS vital_readings_blood_pressure_source_check,
    ADD CONSTRAINT vital_readings_bp_source_validated_only
        CHECK (blood_pressure_source IN ('validated_cuff', 'clinician_entered'));

COMMENT ON COLUMN devices.last_sensor_status IS
    'Hardware/measurement availability state only. It is separate from clinical alerts.';
