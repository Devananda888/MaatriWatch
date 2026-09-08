import unittest
from datetime import datetime, timedelta, timezone

from app.device_health import device_health


class DeviceHealthTest(unittest.TestCase):
    def test_recent_device_is_connected_without_a_clinical_status(self):
        now = datetime(2026, 9, 8, 10, 0, tzinfo=timezone.utc)
        result = device_health(
            {"status": "assigned", "last_seen_at": now - timedelta(minutes=5), "last_sensor_status": "ok"},
            now=now,
        )
        self.assertEqual(result["status"], "connected")
        self.assertNotIn("severity", result)

    def test_old_device_checkin_is_offline_not_a_clinical_alert(self):
        now = datetime(2026, 9, 8, 10, 0, tzinfo=timezone.utc)
        result = device_health(
            {"status": "assigned", "last_seen_at": now - timedelta(minutes=31), "last_sensor_status": "ok"},
            now=now,
        )
        self.assertEqual(result["status"], "offline")
        self.assertIn("not a clinical alert", result["message"])

    def test_sensor_failure_is_a_device_attention_state(self):
        now = datetime(2026, 9, 8, 10, 0, tzinfo=timezone.utc)
        result = device_health(
            {"status": "assigned", "last_seen_at": now, "last_sensor_status": "sensor_error"}, now=now
        )
        self.assertEqual(result["status"], "sensor_attention_needed")


if __name__ == "__main__":
    unittest.main()
