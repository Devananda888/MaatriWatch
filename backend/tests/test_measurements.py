import unittest
from datetime import datetime, timezone

from app.measurements import public_vital


class PublicVitalTest(unittest.TestCase):
    def test_legacy_temperature_is_exposed_only_as_skin_adjacent(self):
        result = public_vital(
            {
                "captured_at": datetime(2026, 9, 8, tzinfo=timezone.utc),
                "temperature_c": 36.5,
                "temperature_source": "wearable_skin_adjacent",
            }
        )
        self.assertEqual(result["skin_adjacent_temperature_c"], 36.5)
        self.assertNotIn("temperature_c", result)

    def test_bp_without_validated_source_is_hidden(self):
        result = public_vital({"captured_at": datetime.now(timezone.utc), "systolic_bp": 150, "diastolic_bp": 95})
        self.assertIsNone(result["systolic_bp"])
        self.assertIsNone(result["diastolic_bp"])
        self.assertIsNone(result["blood_pressure_source"])

    def test_contact_loss_is_unavailable(self):
        result = public_vital({"captured_at": datetime.now(timezone.utc), "contact_detected": False})
        self.assertEqual(result["measurement_quality"], "unavailable")

    def test_reading_has_explicit_source_observation_and_freshness(self):
        observed = datetime(2026, 9, 8, 10, 0, tzinfo=timezone.utc)
        result = public_vital(
            {
                "observed_at": observed,
                "heart_rate_bpm": 78,
                "heart_rate_source": "wearable_ppg",
                "spo2_source": "wearable_ppg",
                "temperature_source": "wearable_skin_adjacent",
                "sensor_status": "ok",
                "signal_quality": 0.9,
            },
            now=datetime(2026, 9, 8, 10, 5, tzinfo=timezone.utc),
        )
        self.assertEqual(result["observed_at"], "2026-09-08T10:00:00Z")
        self.assertEqual(result["measurement_sources"]["heart_rate"], "wearable_ppg")
        self.assertEqual(result["freshness"], "current")
        self.assertTrue(result["is_fresh"])

    def test_old_available_reading_is_explicitly_stale(self):
        result = public_vital(
            {"captured_at": datetime(2026, 9, 8, 10, 0, tzinfo=timezone.utc), "sensor_status": "ok"},
            now=datetime(2026, 9, 8, 10, 11, tzinfo=timezone.utc),
        )
        self.assertEqual(result["freshness"], "stale")
