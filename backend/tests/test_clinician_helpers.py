from datetime import date, datetime, timezone
from decimal import Decimal
from uuid import uuid4
import unittest

from app.clinician import _wire
from app.firebase import _is_newer_alert, clinician_entitlements


class ClinicianHelperTest(unittest.TestCase):
    def test_wire_serialises_postgres_scalars(self):
        identifier = uuid4()
        payload = _wire(
            {
                "id": identifier,
                "value": Decimal("97.50"),
                "delivery_date": date(2026, 8, 14),
                "captured_at": datetime(2026, 8, 14, 10, 30, tzinfo=timezone.utc),
            }
        )
        self.assertEqual(payload["id"], str(identifier))
        self.assertEqual(payload["value"], 97.5)
        self.assertEqual(payload["delivery_date"], "2026-08-14")
        self.assertEqual(payload["captured_at"], "2026-08-14T10:30:00Z")

    def test_clinical_state_update_wins_without_new_sensor_event(self):
        current = {
            "last_seen_at": "2026-08-14T10:30:00Z",
            "updated_at": "2026-08-14T10:30:00Z",
            "occurrence_count": 8,
            "status": "open",
        }
        resolved = {
            "last_seen_at": "2026-08-14T10:30:00Z",
            "updated_at": "2026-08-14T10:31:00Z",
            "occurrence_count": 8,
            "status": "resolved",
        }
        self.assertTrue(_is_newer_alert(resolved, current))

    def test_clinician_entitlements_are_hospital_scoped(self):
        grants = clinician_entitlements(
            [
                {"hospital_id": "hospital-a", "role": "clinician", "is_active": True},
                {"hospital_id": "hospital-b", "role": "clinician", "is_active": False},
                {"hospital_id": "hospital-c", "role": "patient", "is_active": True},
            ]
        )
        self.assertTrue(grants["hospital-a"]["can_read_all_live_vitals"])
        self.assertFalse(grants["hospital-b"]["active"])
        self.assertFalse(grants["hospital-c"]["can_read_alert_queue"])


if __name__ == "__main__":
    unittest.main()
