-- Phase 6: provenance and quality labels for wearable telemetry.
--
-- Existing temperature_c values are legacy wearable readings. They are
-- explicitly reclassified as skin-adjacent measurements; they are not core
-- body-temperature values and must never feed fever alerts.

ALTER TABLE vital_readings
    ADD COLUMN IF NOT EXISTS observed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS heart_rate_source TEXT NOT NULL DEFAULT 'wearable_ppg'
        CHECK (heart_rate_source IN ('wearable_ppg', 'external_validated_device', 'clinician_entered')),
    ADD COLUMN IF NOT EXISTS spo2_source TEXT NOT NULL DEFAULT 'wearable_ppg'
        CHECK (spo2_source IN ('wearable_ppg', 'external_validated_device', 'clinician_entered')),
    ADD COLUMN IF NOT EXISTS temperature_source TEXT NOT NULL DEFAULT 'wearable_skin_adjacent'
        CHECK (temperature_source IN ('wearable_skin_adjacent', 'external_validated_device', 'clinician_entered')),
    ADD COLUMN IF NOT EXISTS blood_pressure_source TEXT
        CHECK (blood_pressure_source IN ('validated_cuff', 'external_validated_device', 'clinician_entered')),
    ADD COLUMN IF NOT EXISTS contact_detected BOOLEAN,
    ADD COLUMN IF NOT EXISTS signal_quality NUMERIC(5,4)
        CHECK (signal_quality BETWEEN 0 AND 1),
    ADD COLUMN IF NOT EXISTS sensor_status TEXT NOT NULL DEFAULT 'unknown'
        CHECK (sensor_status IN ('ok', 'contact_lost', 'sensor_error', 'unavailable', 'unknown')),
    ADD COLUMN IF NOT EXISTS measurement_metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

UPDATE vital_readings
SET observed_at = captured_at
WHERE observed_at IS NULL;

ALTER TABLE vital_readings
    ALTER COLUMN observed_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS vital_readings_patient_observed_idx
    ON vital_readings(patient_id, observed_at DESC);

COMMENT ON COLUMN vital_readings.temperature_c IS
    'Legacy storage name for a wearable skin-adjacent/device temperature only; not clinical body temperature.';
COMMENT ON COLUMN vital_readings.blood_pressure_source IS
    'Required before systolic/diastolic values may be exposed or evaluated as blood pressure.';
