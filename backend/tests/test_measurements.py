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
