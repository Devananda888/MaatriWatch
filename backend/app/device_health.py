"""Non-clinical wearable connectivity and sensor-health status.

This module intentionally does not create alerts and does not assess a
patient.  It only explains whether the assigned hardware recently checked in
and whether its sensor reports an availability problem.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Mapping


def device_health(
    device: Mapping[str, Any] | None,
    *,
    now: datetime | None = None,
    offline_after_minutes: int = 30,
) -> dict[str, Any]:
    """Return an explicit hardware state separate from clinical alert state."""
    now = now or datetime.now(timezone.utc)
    if not device:
        return {
            "status": "not_assigned",
            "title": "No wearable assigned",
            "message": "Ask your care team if a wearable should be assigned.",
            "last_seen_at": None,
        }
    last_seen = _as_utc(device.get("last_seen_at"))
    base = {
        "last_seen_at": last_seen.isoformat().replace("+00:00", "Z") if last_seen else None,
        "battery_percent": device.get("last_battery_percent"),
        "sensor_status": device.get("last_sensor_status") or "unknown",
        "contact_detected": device.get("last_contact_detected"),
    }
    if device.get("status") != "assigned":
        return {
            **base,
            "status": "not_assigned",
            "title": "Wearable is not assigned",
            "message": "This device is not currently assigned to this patient.",
        }
    if not last_seen:
        return {
            **base,
            "status": "awaiting_first_check_in",
            "title": "Waiting for wearable check-in",
            "message": "Turn on the wearable and connect it to its approved network.",
        }
    if now - last_seen > timedelta(minutes=offline_after_minutes):
        return {
            **base,
            "status": "offline",
            "title": "Wearable has not checked in recently",
            "message": "This is a device connection issue, not a clinical alert.",
        }
    if base["sensor_status"] in {"sensor_error", "unavailable"}:
        return {
            **base,
            "status": "sensor_attention_needed",
            "title": "Wearable sensor needs attention",
            "message": "Check the sensor placement and contact your care team if it continues.",
        }
    if base["sensor_status"] == "contact_lost" or base["contact_detected"] is False:
        return {
            **base,
            "status": "contact_needed",
            "title": "Wearable contact is needed",
            "message": "Reposition the wearable for a new reading.",
        }
    return {
        **base,
        "status": "connected",
        "title": "Wearable connected",
        "message": "The wearable checked in recently. This is not a clinical assessment.",
    }


def _as_utc(value: Any) -> datetime | None:
    if not isinstance(value, datetime):
        return None
    return value.astimezone(timezone.utc) if value.tzinfo else value.replace(tzinfo=timezone.utc)
