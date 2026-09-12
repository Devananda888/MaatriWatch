-- Phase 8: patient-confirmed laboratory follow-up and safety-first wellbeing.
--
-- These records are deliberately not diagnoses.  Laboratory values stay
-- pending clinician review and the five-item wellbeing check-in is a support
-- touchpoint, not a shortened EPDS or an automated depression assessment.

ALTER TABLE patients
    ADD COLUMN IF NOT EXISTS lab_onboarding_seen_at TIMESTAMPTZ;

CREATE TABLE patient_lab_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    category TEXT NOT NULL CHECK (category IN ('gestational_diabetes', 'thyroid')),
    test_type TEXT NOT NULL CHECK (test_type IN ('75g_ogtt', 'thyroid_function')),
    result_values JSONB NOT NULL,
    result_units JSONB NOT NULL,
    reported_on DATE,
    trimester SMALLINT CHECK (trimester IN (1, 2, 3)),
    extraction_method TEXT NOT NULL CHECK (extraction_method IN ('patient_confirmed')),
    review_status TEXT NOT NULL DEFAULT 'pending_clinician_review'
        CHECK (review_status IN ('pending_clinician_review', 'reviewed')),
    reference_status TEXT NOT NULL DEFAULT 'not_interpreted'
        CHECK (reference_status IN ('not_interpreted', 'needs_clinician_review')),
    reviewed_by UUID REFERENCES app_users(id),
    reviewed_at TIMESTAMPTZ,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX patient_lab_results_patient_idx
    ON patient_lab_results(patient_id, submitted_at DESC);

CREATE TABLE wellbeing_checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    checkin_type TEXT NOT NULL DEFAULT 'support_checkin'
        CHECK (checkin_type = 'support_checkin'),
    responses JSONB NOT NULL,
    immediate_safety_concern BOOLEAN NOT NULL DEFAULT false,
    guardian_notification_consent BOOLEAN NOT NULL DEFAULT false,
    guardian_notification_status TEXT NOT NULL DEFAULT 'not_requested'
        CHECK (guardian_notification_status IN ('not_requested', 'not_configured', 'sent', 'failed')),
    clinician_review_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (clinician_review_status IN ('pending', 'reviewed')),
    reviewed_by UUID REFERENCES app_users(id),
    reviewed_at TIMESTAMPTZ,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX wellbeing_checkins_patient_idx
    ON wellbeing_checkins(patient_id, submitted_at DESC);

CREATE TRIGGER patient_lab_results_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON patient_lab_results
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();
CREATE TRIGGER wellbeing_checkins_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON wellbeing_checkins
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();

COMMENT ON TABLE patient_lab_results IS
    'Patient-confirmed reported values. Never use this table for automated diagnosis or prescribing.';
COMMENT ON TABLE wellbeing_checkins IS
    'Non-diagnostic support check-in. An immediate safety concern creates a clinical alert for urgent assessment.';
