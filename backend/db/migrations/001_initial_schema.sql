-- MaatriWatch Phase 1. Apply once to a fresh Postgres / Supabase project.
-- Firebase Authentication remains the identity provider; firebase_uid is its stable subject.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE user_role AS ENUM ('patient', 'asha_worker', 'clinician', 'hospital_admin', 'super_admin');
CREATE TYPE device_status AS ENUM ('inventory', 'assigned', 'maintenance', 'retired');
CREATE TYPE alert_severity AS ENUM ('info', 'warning', 'critical');
CREATE TYPE alert_status AS ENUM ('open', 'acknowledged', 'resolved', 'escalated');

CREATE TABLE hospitals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    code TEXT NOT NULL UNIQUE,
    address TEXT,
    district TEXT,
    state TEXT,
    contact_phone TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE app_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid TEXT NOT NULL UNIQUE,
    email TEXT UNIQUE,
    phone_e164 TEXT UNIQUE,
    display_name TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One user may belong to multiple hospitals. A person can also have more than one role.
CREATE TABLE hospital_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    user_id UUID NOT NULL REFERENCES app_users(id),
    role user_role NOT NULL CHECK (role <> 'super_admin'),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (hospital_id, user_id, role)
);
CREATE INDEX hospital_memberships_user_idx ON hospital_memberships(user_id, hospital_id) WHERE is_active;

CREATE TABLE user_global_roles (
    user_id UUID NOT NULL REFERENCES app_users(id),
    role user_role NOT NULL CHECK (role = 'super_admin'),
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role)
);

CREATE TABLE patients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    user_id UUID UNIQUE REFERENCES app_users(id),
    medical_record_number TEXT NOT NULL,
    full_name TEXT NOT NULL,
    date_of_birth DATE,
    preferred_language TEXT NOT NULL DEFAULT 'en',
    delivery_date DATE,
    emergency_contact_name TEXT,
    emergency_contact_phone TEXT,
    consented_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (hospital_id, medical_record_number)
);
CREATE INDEX patients_hospital_idx ON patients(hospital_id, is_active);

CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    serial_number TEXT NOT NULL UNIQUE,
    api_key_hash TEXT NOT NULL,
    status device_status NOT NULL DEFAULT 'inventory',
    assigned_patient_id UUID REFERENCES patients(id),
    firmware_version TEXT,
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((status = 'assigned') = (assigned_patient_id IS NOT NULL))
);
CREATE INDEX devices_hospital_status_idx ON devices(hospital_id, status);

CREATE TABLE vital_readings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    device_id UUID NOT NULL REFERENCES devices(id),
    captured_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    heart_rate_bpm SMALLINT CHECK (heart_rate_bpm BETWEEN 20 AND 260),
    spo2_percent NUMERIC(5,2) CHECK (spo2_percent BETWEEN 0 AND 100),
    temperature_c NUMERIC(4,2) CHECK (temperature_c BETWEEN 25 AND 45),
    systolic_bp SMALLINT CHECK (systolic_bp BETWEEN 50 AND 260),
    diastolic_bp SMALLINT CHECK (diastolic_bp BETWEEN 30 AND 180),
    battery_percent SMALLINT CHECK (battery_percent BETWEEN 0 AND 100),
    raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX vital_readings_patient_time_idx ON vital_readings(patient_id, captured_at DESC);
CREATE INDEX vital_readings_hospital_time_idx ON vital_readings(hospital_id, captured_at DESC);

CREATE TABLE alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    vital_reading_id UUID REFERENCES vital_readings(id),
    severity alert_severity NOT NULL,
    status alert_status NOT NULL DEFAULT 'open',
    alert_type TEXT NOT NULL,
    message TEXT NOT NULL,
    triggered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    acknowledged_by UUID REFERENCES app_users(id),
    acknowledged_at TIMESTAMPTZ,
    resolved_by UUID REFERENCES app_users(id),
    resolved_at TIMESTAMPTZ,
    resolution_note TEXT
);
CREATE INDEX alerts_queue_idx ON alerts(hospital_id, status, severity, triggered_at DESC);

CREATE TABLE screenings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    screening_type TEXT NOT NULL,
    language_code TEXT NOT NULL,
    score NUMERIC(7,2),
    risk_level TEXT,
    responses JSONB NOT NULL DEFAULT '{}'::jsonb,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    source TEXT NOT NULL DEFAULT 'whatsapp',
    reviewed_by UUID REFERENCES app_users(id),
    reviewed_at TIMESTAMPTZ
);
CREATE INDEX screenings_patient_time_idx ON screenings(patient_id, submitted_at DESC);

CREATE TABLE clinical_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    author_user_id UUID NOT NULL REFERENCES app_users(id),
    note TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX clinical_notes_patient_time_idx ON clinical_notes(patient_id, created_at DESC);

CREATE TABLE audit_log (
    id BIGSERIAL PRIMARY KEY,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    actor_user_id UUID REFERENCES app_users(id),
    hospital_id UUID REFERENCES hospitals(id),
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    request_id UUID,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    ip_address INET
);
CREATE INDEX audit_log_hospital_time_idx ON audit_log(hospital_id, occurred_at DESC);
CREATE INDEX audit_log_entity_idx ON audit_log(entity_type, entity_id, occurred_at DESC);

-- Guard the hospital tenant boundary even if a future internal job bypasses Flask.
CREATE OR REPLACE FUNCTION enforce_device_patient_hospital_match()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.assigned_patient_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM patients p WHERE p.id = NEW.assigned_patient_id AND p.hospital_id = NEW.hospital_id
    ) THEN
        RAISE EXCEPTION 'A device may only be assigned to a patient in its hospital';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER devices_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, assigned_patient_id ON devices
FOR EACH ROW EXECUTE FUNCTION enforce_device_patient_hospital_match();

CREATE OR REPLACE FUNCTION enforce_reading_hospital_match()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM patients p WHERE p.id = NEW.patient_id AND p.hospital_id = NEW.hospital_id) THEN
        RAISE EXCEPTION 'Reading patient must belong to reading hospital';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM devices d WHERE d.id = NEW.device_id AND d.hospital_id = NEW.hospital_id) THEN
        RAISE EXCEPTION 'Reading device must belong to reading hospital';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER vital_readings_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, patient_id, device_id ON vital_readings
FOR EACH ROW EXECUTE FUNCTION enforce_reading_hospital_match();
