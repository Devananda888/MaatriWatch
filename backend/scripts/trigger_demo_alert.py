"""Post one fresh, threshold-triggering demo device event to the Flask API.

Run ``seed_demo.py`` first.  This is an HTTP client only: it never talks to a
wearable or writes directly to Firebase.  A new event ID is generated for each
run, so the API's ingestion/alert/outbox path is exercised end to end.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from uuid import NAMESPACE_URL, uuid4, uuid5

from dotenv import load_dotenv
from psycopg import connect
from psycopg.errors import OperationalError
from psycopg.rows import dict_row


ROOT_DIR = Path(__file__).resolve().parents[1]
load_dotenv(ROOT_DIR / ".env")
DEFAULT_API_URL = "http://127.0.0.1:8000/api/v1/ingest/telemetry"


def demo_device_key(serial_number: str) -> str:
    try:
        index = int(serial_number.rsplit("-", 1)[1])
    except (IndexError, ValueError):
        raise SystemExit("--serial must be a seeded device such as MW-DEMO-0005") from None
    return f"mw-demo-device-key-{index:02d}-for-demo-only"


def parse_args():
    parser = argparse.ArgumentParser(description="Trigger one live MaatriWatch demo alert through Flask ingestion.")
    parser.add_argument(
        "--api-url",
        default=os.getenv("MAATRIWATCH_API_URL", DEFAULT_API_URL),
        help="Flask ingestion endpoint (defaults to local /api/v1/ingest/telemetry)",
    )
    parser.add_argument("--serial", default="MW-DEMO-0005", help="Seeded device serial number")
    parser.add_argument("--scenario", choices=("fall", "hypertension", "pph"), default="fall")
    parser.add_argument("--device-id", help="Optional device UUID; skips the DATABASE_URL lookup")
    parser.add_argument("--device-key", help="Optional demo device key; defaults from --serial")
    return parser.parse_args()


def lookup_device_id(database_url: str, serial_number: str) -> str:
    try:
        with connect(database_url, row_factory=dict_row) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """SELECT id FROM devices
                       WHERE serial_number = %s AND status = 'assigned'""",
                    (serial_number,),
                )
                device = cursor.fetchone()
    except OperationalError:
        raise SystemExit("Could not connect to Postgres. Check DATABASE_URL without printing it.") from None
    if not device:
        raise SystemExit(f"No assigned demo device found for {serial_number}. Run seed_demo.py first.")
    return str(device["id"])


def in_memory_device_id(serial_number: str) -> str:
    """Mirror demo_store's deterministic device IDs without touching Postgres."""

    try:
        index = int(serial_number.rsplit("-", 1)[1])
    except (IndexError, ValueError):
        raise SystemExit("--serial must be a seeded device such as MW-DEMO-0005") from None
    return str(uuid5(NAMESPACE_URL, f"maatriwatch-demo/device/{index}"))


def telemetry(scenario: str) -> dict:
    payload = {
        "event_id": f"demo-live:{uuid4().hex}",
        "source_sequence": int(datetime.now(timezone.utc).timestamp()),
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "heart_rate_bpm": 78,
        "spo2_percent": 98,
        "temperature_c": 36.8,
        "systolic_bp": 112,
        "diastolic_bp": 72,
        "battery_percent": 83,
        "motion": {
            "fall_detected": False,
            "impact_g": 0.1,
            "orientation_change_degrees": 2,
            "post_impact_immobile_seconds": 0,
        },
    }
    if scenario == "fall":
        payload["motion"] = {
            "fall_detected": True,
            "impact_g": 3.1,
            "orientation_change_degrees": 82,
            "post_impact_immobile_seconds": 38,
        }
    elif scenario == "hypertension":
        payload.update({"systolic_bp": 166, "diastolic_bp": 112, "heart_rate_bpm": 94})
    elif scenario == "pph":
        payload.update(
            {
                "heart_rate_bpm": 116,
                "systolic_bp": 86,
                "blood_loss_ml": 420,
                "bleeding_reported": True,
            }
        )
    return payload


def post_event(api_url: str, device_id: str, device_key: str, payload: dict) -> int:
    request = urllib.request.Request(
        api_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-Device-Id": device_id,
            "X-Device-Key": device_key,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        print(f"Flask rejected the demo reading (HTTP {error.code}).", file=sys.stderr)
        return 1
    except urllib.error.URLError:
        print("Could not reach Flask. Start the API and confirm --api-url.", file=sys.stderr)
        return 1

    alert_ids = body.get("alert_ids") or []
    print(f"Ingestion accepted (HTTP 201): reading_id={body.get('reading_id')}")
    print(f"Threshold result: alert_ids={', '.join(alert_ids) if alert_ids else 'none'}")
    print(f"Realtime delivery: {body.get('realtime', 'unknown')}")
    if not alert_ids:
        print("Unexpected: this demo scenario should create a risk alert.", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    args = parse_args()
    device_id = args.device_id
    if not device_id:
        if os.getenv("DEMO_IN_MEMORY", "").strip().lower() in {"1", "true", "yes"}:
            device_id = in_memory_device_id(args.serial)
        else:
            database_url = os.getenv("DATABASE_URL")
            if not database_url:
                print("DATABASE_URL is required to look up the seeded device ID.", file=sys.stderr)
                return 1
            device_id = lookup_device_id(database_url, args.serial)
    return post_event(args.api_url, device_id, args.device_key or demo_device_key(args.serial), telemetry(args.scenario))


if __name__ == "__main__":
    raise SystemExit(main())
