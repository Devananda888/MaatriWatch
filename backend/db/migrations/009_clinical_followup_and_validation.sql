-- Phase 9: clinician-reviewed follow-up, activity context, messaging and
-- prototype validation records.
--
-- This phase deliberately separates patient-reported information from
-- clinician-confirmed information. It supports care coordination; it does not
-- diagnose GDM, thyroid disease, depression, pre-eclampsia, or any condition.

CREATE TABLE patient_clinical_profiles (
    patient_id UUID PRIMARY KEY REFERENCES patients(id) ON DELETE CASCADE,
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    pregnancy_stage TEXT NOT NULL DEFAULT 'not_recorded'
        CHECK (pregnancy_stage IN ('not_recorded', 'first_trimester', 'second_trimester',
            'third_trimester', 'postpartum')),
    patient_reported_history JSONB NOT NULL DEFAULT '{}'::jsonb,
    clinician_confirmed_history JSONB NOT NULL DEFAULT '{}'::jsonb,
    current_medications JSONB NOT NULL DEFAULT '[]'::jsonb,
    activity_clearance TEXT NOT NULL DEFAULT 'not_recorded'
        CHECK (activity_clearance IN ('not_recorded', 'cleared_by_clinician', 'restricted_by_clinician')),
    last_patient_update_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES app_users(id),
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER patient_clinical_profiles_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON patient_clinical_profiles
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();

-- Small reports are stored with their clinical metadata in Postgres for this
-- prototype. A production deployment should move the blob to an approved,
-- encrypted object store while retaining this audit metadata and access model.
CREATE TABLE patient_report_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    uploaded_by UUID NOT NULL REFERENCES app_users(id),
    document_type TEXT NOT NULL CHECK (document_type IN ('lab_report', 'medical_report')),
    original_filename TEXT NOT NULL,
    media_type TEXT NOT NULL CHECK (media_type IN ('application/pdf', 'image/jpeg', 'image/png')),
    byte_size INTEGER NOT NULL CHECK (byte_size > 0 AND byte_size <= 4000000),
    sha256 TEXT NOT NULL CHECK (char_length(sha256) = 64),
    content BYTEA NOT NULL,
    patient_confirmed_text TEXT,
    extraction_status TEXT NOT NULL DEFAULT 'not_requested'
        CHECK (extraction_status IN ('not_requested', 'patient_text_submitted', 'needs_confirmation', 'unsupported')),
    review_status TEXT NOT NULL DEFAULT 'pending_clinician_review'
        CHECK (review_status IN ('pending_clinician_review', 'reviewed')),
    reviewed_by UUID REFERENCES app_users(id),
    reviewed_at TIMESTAMPTZ,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX patient_report_documents_patient_idx
    ON patient_report_documents(patient_id, uploaded_at DESC);
CREATE TRIGGER patient_report_documents_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON patient_report_documents
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();

-- Messages are hospital-scoped asynchronous care messages. They are not an
-- emergency channel, do not reveal private clinician telephone numbers, and
-- are retained as part of the care record.
CREATE TABLE care_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    sender_user_id UUID NOT NULL REFERENCES app_users(id),
    sender_role TEXT NOT NULL CHECK (sender_role IN ('patient', 'clinician')),
    body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
    status TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'responded', 'closed')),
    in_reply_to UUID REFERENCES care_messages(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at TIMESTAMPTZ
);
CREATE INDEX care_messages_patient_idx
    ON care_messages(patient_id, created_at DESC);
CREATE TRIGGER care_messages_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON care_messages
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();

-- Activity is either patient-reported or created by a future validated
-- wearable classifier. Do not treat raw accelerometer data as a step count.
CREATE TABLE patient_activity_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    activity_type TEXT NOT NULL CHECK (activity_type IN ('walking', 'other')),
    session_part TEXT CHECK (session_part IN ('morning', 'evening', 'other')),
    minutes SMALLINT NOT NULL CHECK (minutes BETWEEN 1 AND 180),
    source TEXT NOT NULL CHECK (source IN ('patient_reported', 'wearable_classifier')),
    classifier_confidence NUMERIC(4,3),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    note TEXT CHECK (note IS NULL OR char_length(note) <= 500)
);
CREATE INDEX patient_activity_entries_patient_idx
    ON patient_activity_entries(patient_id, recorded_at DESC);
CREATE TRIGGER patient_activity_entries_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON patient_activity_entries
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();

-- Clinician-approved support material. Generic app content is informational;
-- only guidance entered here is labelled as personalised.
CREATE TABLE patient_guidance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    category TEXT NOT NULL CHECK (category IN ('gdm_support', 'thyroid_followup', 'activity', 'wellbeing')),
    title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 160),
    body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 4000),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'superseded', 'withdrawn')),
    created_by UUID NOT NULL REFERENCES app_users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX patient_guidance_patient_idx
    ON patient_guidance(patient_id, status, created_at DESC);
CREATE TRIGGER patient_guidance_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON patient_guidance
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();

-- A transparent prototype-validation log. It records paired observations with
-- the reference device named by the clinician; it does not declare a device
-- clinically validated or compute a diagnosis.
CREATE TABLE wearable_validation_observations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    recorded_by UUID NOT NULL REFERENCES app_users(id),
    metric TEXT NOT NULL CHECK (metric IN ('heart_rate_bpm', 'spo2_percent', 'skin_adjacent_temperature_c')),
    wearable_value NUMERIC(9,3) NOT NULL,
    reference_value NUMERIC(9,3) NOT NULL,
    reference_device_label TEXT NOT NULL CHECK (char_length(reference_device_label) BETWEEN 1 AND 160),
    observation_time TIMESTAMPTZ NOT NULL,
    absolute_error NUMERIC(9,3) NOT NULL,
    percent_error NUMERIC(9,3),
    note TEXT CHECK (note IS NULL OR char_length(note) <= 1000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX wearable_validation_observations_patient_idx
    ON wearable_validation_observations(patient_id, metric, observation_time DESC);
CREATE TRIGGER wearable_validation_observations_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON wearable_validation_observations
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();

ALTER TABLE care_plan_tasks
    ADD COLUMN IF NOT EXISTS task_type TEXT NOT NULL DEFAULT 'general'
        CHECK (task_type IN ('general', 'walking', 'appointment', 'lab_followup', 'wellbeing')),
    ADD COLUMN IF NOT EXISTS target_minutes SMALLINT
        CHECK (target_minutes IS NULL OR target_minutes BETWEEN 1 AND 180);

ALTER TABLE patient_lab_results
    ADD COLUMN IF NOT EXISTS review_note TEXT
        CHECK (review_note IS NULL OR char_length(review_note) <= 2000);

COMMENT ON TABLE patient_clinical_profiles IS
    'Patient-reported and clinician-confirmed history are deliberately separated. Only confirmed information may personalise clinical workflow.';
COMMENT ON TABLE patient_report_documents IS
    'Sensitive report attachment. Values extracted from a report must be confirmed by the patient and reviewed by a clinician.';
COMMENT ON TABLE care_messages IS
    'Asynchronous care messaging, not an emergency or real-time monitoring channel.';
COMMENT ON TABLE wearable_validation_observations IS
    'Prototype paired-observation log; not evidence that a device is clinically validated.';
