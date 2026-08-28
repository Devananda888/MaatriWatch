from datetime import datetime, timezone
import unittest
from uuid import uuid4

from app.demo_store import DemoStore


class DemoStoreTest(unittest.TestCase):
    def setUp(self):
        self.store = DemoStore()
        self.hospital_id = self.store.hospital["id"]

    def test_seed_has_dashboard_data_and_screenings(self):
        patients = self.store.patient_list(sort="risk")
        self.assertEqual(len(patients["items"]), 7)
        self.assertEqual(patients["items"][0]["status"], "critical")
        second_patient = patients["items"][1]["id"]
        self.assertTrue(self.store.screenings(second_patient)["items"] or self.store.screenings(patients["items"][-1]["id"])["items"])
        self.assertGreaterEqual(len(self.store.alert_list(status="active")["items"]), 2)
        self.assertIsNotNone(patients["items"][0]["latest_vital"]["ambient_temperature_c"])
        self.assertIsNotNone(patients["items"][0]["latest_vital"]["ambient_humidity_percent"])

    def test_new_fall_uses_the_existing_threshold_engine(self):
        device = next(iter(self.store._devices.values()))
        payload = {
            "event_id": f"demo-store-test:{uuid4().hex}",
            "source_sequence": 999,
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "heart_rate_bpm": 80,
            "spo2_percent": 98,
            "temperature_c": 36.8,
            "systolic_bp": 112,
            "diastolic_bp": 72,
            "battery_percent": 80,
            "motion": {
                "fall_detected": True,
                "impact_g": 3.1,
                "orientation_change_degrees": 82,
                "post_impact_immobile_seconds": 38,
            },
        }
        result = self.store.ingest(device["id"], device["_demo_key"], payload)
        self.assertFalse(result["duplicate"])
        self.assertTrue(result["alert_ids"])
        self.assertEqual(result["realtime"], "demo_polling")


if __name__ == "__main__":
    unittest.main()
