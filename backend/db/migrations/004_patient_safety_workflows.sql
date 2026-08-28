-- Patient-facing safety, consent, symptom and follow-up workflows.
-- Apply after 003_clinician_dashboard.sql.

CREATE TABLE patient_consents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    consent_type TEXT NOT NULL CHECK (consent_type IN ('monitoring', 'care_team_sharing', 'emergency_contact', 'location')), 
    granted BOOLEAN NOT NULL,
    policy_version TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    withdrawn_at TIMESTAMPTZ,
    UNIQUE (patient_id, consent_type, policy_version)
);
CREATE INDEX patient_consents_patient_idx ON patient_consents(patient_id, recorded_at DESC);

CREATE TABLE symptom_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    symptoms JSONB NOT NULL DEFAULT '[]'::jsonb,
    notes TEXT,
    severity TEXT NOT NULL CHECK (severity IN ('routine', 'urgent')),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_by UUID REFERENCES app_users(id),
    reviewed_at TIMESTAMPTZ
);
CREATE INDEX symptom_reports_patient_idx ON symptom_reports(patient_id, submitted_at DESC);

CREATE TABLE care_plan_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    title TEXT NOT NULL,
    detail TEXT,
    due_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'completed', 'skipped')),
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX care_plan_tasks_patient_idx ON care_plan_tasks(patient_id, status, due_at);

CREATE OR REPLACE FUNCTION enforce_patient_workflow_hospital_match()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM patients p WHERE p.id = NEW.patient_id AND p.hospital_id = NEW.hospital_id) THEN
        RAISE EXCEPTION 'Patient workflow record must belong to the patient hospital';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER patient_consents_hospital_match BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON patient_consents
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();
CREATE TRIGGER symptom_reports_hospital_match BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON symptom_reports
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();
CREATE TRIGGER care_plan_tasks_hospital_match BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON care_plan_tasks
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();
