import unittest
from datetime import datetime, timezone
from werkzeug.exceptions import BadRequest

from app import create_app
from app.ingestion import _payload


class TelemetryPayloadTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app({"TESTING": True})

    def test_normalized_motion_telemetry_is_accepted(self):
        data = {
            "event_id": "sim:session:1",
            "source_sequence": 1,
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "heart_rate_bpm": 78,
            "spo2_percent": 98,
            "temperature_c": 36.8,
            "motion": {"impact_g": 0.2, "orientation_change_degrees": 2, "post_impact_immobile_seconds": 0},
        }
        with self.app.test_request_context("/api/v1/ingest/telemetry", method="POST", json=data):
            parsed = _payload()
        self.assertEqual(parsed["source_event_id"], "sim:session:1")
        self.assertEqual(parsed["motion"]["impact_g"], 0.2)
        self.assertEqual(parsed["temperature_source"], "wearable_skin_adjacent")

    def test_unprovenanced_bp_and_contact_lost_ppg_are_not_saved_as_readings(self):
        data = {
            "event_id": "sim:session:quality",
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "heart_rate_bpm": 170,
            "spo2_percent": 94,
            "temperature_c": 36.6,
            "systolic_bp": 150,
            "diastolic_bp": 100,
            "contact_detected": False,
        }
        with self.app.test_request_context("/api/v1/ingest/telemetry", method="POST", json=data):
            parsed = _payload()
        self.assertIsNone(parsed["heart_rate_bpm"])
        self.assertIsNone(parsed["spo2_percent"])
        self.assertIsNone(parsed["systolic_bp"])
        self.assertIsNone(parsed["diastolic_bp"])
        self.assertTrue(parsed["measurement_metadata"]["blood_pressure_discarded"])

    def test_event_id_is_required_for_retry_safe_ingestion(self):
        with self.app.test_request_context(
            "/api/v1/ingest/telemetry",
            method="POST",
            json={"captured_at": "2026-08-14T10:12:00Z", "heart_rate_bpm": 78},
        ):
            with self.assertRaises(BadRequest):
                _payload()

    def test_motion_contract_rejects_non_boolean_fall_marker(self):
        with self.app.test_request_context(
            "/api/v1/ingest/telemetry",
            method="POST",
            json={
                "event_id": "sim:session:1",
                "captured_at": "2026-08-14T10:12:00Z",
                "motion": {"fall_detected": "yes"},
            },
        ):
            with self.assertRaises(BadRequest):
                _payload()


if __name__ == "__main__":
    unittest.main()
