"""Safe API representations for provenance-labelled telemetry.

The raw table preserves backwards-compatible column names. API consumers use
this module so a legacy temperature column cannot accidentally be presented as
clinical body temperature and unvalidated wearable BP cannot leak into a UI.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any, Mapping
from uuid import UUID

_VALID_BP_SOURCES = {"validated_cuff", "external_validated_device", "clinician_entered"}


def public_vital(row: Mapping[str, Any] | None) -> dict[str, Any] | None:
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
        value["measurement_quality"] = "unavailable"
    elif value.get("contact_detected") is False:
        value["measurement_quality"] = "unavailable"
    elif value.get("signal_quality") is not None:
        value["measurement_quality"] = "available"
    else:
        value["measurement_quality"] = "unknown"
    return {key: _json_value(item) for key, item in value.items()}


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
