"""Safe API representations for provenance-labelled telemetry.

The raw table preserves backwards-compatible column names. API consumers use
this module so a legacy temperature column cannot accidentally be presented as
clinical body temperature and unvalidated wearable BP cannot leak into a UI.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, Mapping
from uuid import UUID

_VALID_BP_SOURCES = {"validated_cuff", "clinician_entered"}
_FRESH_FOR = timedelta(minutes=10)


def public_vital(
    row: Mapping[str, Any] | None,
    *,
    now: datetime | None = None,
) -> dict[str, Any] | None:
    if not row:
        return None
    value = dict(row)
    observed_at = value.get("observed_at") or value.get("captured_at")
    value["observed_at"] = observed_at
    value["captured_at"] = observed_at

    # The storage column is retained for migration compatibility only.
    temperature_source = value.get("temperature_source") or "wearable_skin_adjacent"
    value["skin_adjacent_temperature_c"] = (
        value.get("temperature_c")
        if temperature_source == "wearable_skin_adjacent"
        else None
    )
    value.pop("temperature_c", None)

    blood_pressure_source = value.get("blood_pressure_source")
    if blood_pressure_source not in _VALID_BP_SOURCES:
        value["systolic_bp"] = None
        value["diastolic_bp"] = None
        value["blood_pressure_source"] = None

    if value.get("sensor_status") in {"contact_lost", "sensor_error", "unavailable"}:
        availability = "unavailable"
    elif value.get("contact_detected") is False:
        availability = "unavailable"
    elif value.get("signal_quality") is not None:
        availability = "available"
    else:
        availability = "unknown"
    value["measurement_quality"] = availability
    observed = _as_utc(observed_at)
    clock = _as_utc(now) or datetime.now(timezone.utc)
    if availability == "unavailable" or observed is None:
        freshness = "unavailable"
    elif clock - observed > _FRESH_FOR:
        freshness = "stale"
    else:
        freshness = "current"
    value["freshness"] = freshness
    value["is_fresh"] = freshness == "current"
    value["measurement_sources"] = {
        "heart_rate": value.get("heart_rate_source"),
        "spo2": value.get("spo2_source"),
        "temperature": value.get("temperature_source"),
        "blood_pressure": value.get("blood_pressure_source"),
    }
    # Activity context is only descriptive. It must never turn an abnormal
    # physiological reading into "normal" or suppress an SOS/fall pathway.
    motion = value.get("motion") if isinstance(value.get("motion"), Mapping) else {}
    state = motion.get("activity_state")
    confidence = motion.get("classifier_confidence")
    value["activity_context"] = (
        state
        if state in {"resting", "walking", "exercising"}
        and isinstance(confidence, (int, float)) and confidence >= 0.75
        else "unknown"
    )
    return {key: _json_value(item) for key, item in value.items()}


def _as_utc(value: Any) -> datetime | None:
    if not isinstance(value, datetime):
        return None
    return value.astimezone(timezone.utc) if value.tzinfo else value.replace(tzinfo=timezone.utc)


def _json_value(value: Any) -> Any:
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, datetime):
        stamp = value.astimezone(timezone.utc) if value.tzinfo else value.replace(tzinfo=timezone.utc)
        return stamp.isoformat().replace("+00:00", "Z")
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, dict):
        return {key: _json_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_value(item) for item in value]
    return value
