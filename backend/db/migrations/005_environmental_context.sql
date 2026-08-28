-- Phase 5: preserve explicitly non-clinical environmental context.
-- DHT11 readings are ambient conditions only; never use these columns for
-- maternal temperature assessment or alerting.

ALTER TABLE vital_readings
    ADD COLUMN IF NOT EXISTS ambient_temperature_c NUMERIC(5,2)
        CHECK (ambient_temperature_c BETWEEN -20 AND 85),
    ADD COLUMN IF NOT EXISTS ambient_humidity_percent NUMERIC(5,2)
        CHECK (ambient_humidity_percent BETWEEN 0 AND 100);
