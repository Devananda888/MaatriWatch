from datetime import date, datetime, timezone
from decimal import Decimal
from uuid import uuid4
import unittest

from app.clinician import _wire
from app.firebase import _is_newer_alert


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


if __name__ == "__main__":
    unittest.main()
