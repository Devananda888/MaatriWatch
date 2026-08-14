"""Send realistic, replay-safe MaatriWatch telemetry to a local or deployed API.

This is a software simulator only. It does not flash, configure, or otherwise
interact with wearable hardware.

Example:
  python scripts/simulate_device.py --device-id <UUID> --device-key <secret> \
      --scenario fall --count 3
"""

from __future__ import annotations

import argparse
import json
import os
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from uuid import uuid4


def parse_args():
    parser = argparse.ArgumentParser(description="Send MaatriWatch device telemetry every five seconds.")
    parser.add_argument("--api-url", default=os.getenv("MAATRIWATCH_API_URL", "http://127.0.0.1:8000/api/v1/ingest/telemetry"))
    parser.add_argument("--device-id", default=os.getenv("MAATRIWATCH_DEVICE_ID"), required=os.getenv("MAATRIWATCH_DEVICE_ID") is None)
    parser.add_argument("--device-key", default=os.getenv("MAATRIWATCH_DEVICE_KEY"), required=os.getenv("MAATRIWATCH_DEVICE_KEY") is None)
    parser.add_argument("--scenario", choices=("normal", "hypertension", "pph", "fall"), default="normal")
    parser.add_argument("--count", type=int, default=0, help="Number of events; 0 means run until interrupted.")
    parser.add_argument("--interval", type=float, default=5.0, help="Seconds between events.")
    return parser.parse_args()


def telemetry(scenario: str, session_id: str, sequence: int) -> dict:
    payload = {
        "event_id": f"sim:{session_id}:{sequence}",
        "source_sequence": sequence,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "heart_rate_bpm": 76,
        "spo2_percent": 98,
        "temperature_c": 36.8,
        "systolic_bp": 112,
        "diastolic_bp": 72,
        "battery_percent": 84,
        "motion": {"impact_g": 0.1, "orientation_change_degrees": 2, "post_impact_immobile_seconds": 0},
    }
    if scenario == "hypertension":
        payload.update({"systolic_bp": 165, "diastolic_bp": 112})
    elif scenario == "pph":
        payload.update({"heart_rate_bpm": 112, "systolic_bp": 88, "blood_loss_ml": 350, "bleeding_reported": True})
    elif scenario == "fall":
        payload["motion"] = {"fall_detected": True, "impact_g": 3.1, "orientation_change_degrees": 85, "post_impact_immobile_seconds": 35}
    return payload


def post(api_url: str, device_id: str, device_key: str, payload: dict):
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        api_url,
        data=body,
        headers={"Content-Type": "application/json", "X-Device-Id": device_id, "X-Device-Key": device_key},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            print(f"{response.status} {response.read().decode('utf-8')}")
    except urllib.error.HTTPError as error:
        print(f"{error.code} {error.read().decode('utf-8')}")
    except urllib.error.URLError as error:
        print(f"network error: {error.reason}")


def main():
    args = parse_args()
    if args.interval <= 0:
        raise SystemExit("--interval must be greater than zero")
    session_id = uuid4().hex
    sequence = 0
    try:
        while args.count == 0 or sequence < args.count:
            started = time.monotonic()
            post(args.api_url, args.device_id, args.device_key, telemetry(args.scenario, session_id, sequence))
            sequence += 1
            time.sleep(max(0, args.interval - (time.monotonic() - started)))
    except KeyboardInterrupt:
        print("Simulator stopped.")


if __name__ == "__main__":
    main()
