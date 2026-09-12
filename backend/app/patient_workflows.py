"""Safety-first patient submitted lab and wellbeing workflow helpers.

These helpers intentionally do not diagnose, prescribe diets, or calculate a
postpartum-depression score.  They validate what the API is allowed to store
and make an explicit urgent-safety path available to the care team.
"""

from __future__ import annotations

import re
from datetime import date, datetime, timezone
from typing import Any
from uuid import UUID

from flask import abort


LAB_CATEGORIES = {"gestational_diabetes", "thyroid"}
CHECKIN_ANSWERS = {"never", "some_days", "often", "almost_every_day", "prefer_not_to_say"}
SAFETY_ANSWERS = {"no", "yes", "prefer_not_to_say"}
PREGNANCY_STAGES = {
    "not_recorded", "first_trimester", "second_trimester", "third_trimester", "postpartum",
}
ACTIVITY_TYPES = {"walking", "other"}
ACTIVITY_PARTS = {"morning", "evening", "other"}
GUIDANCE_CATEGORIES = {"gdm_support", "thyroid_followup", "activity", "wellbeing"}
VALIDATION_METRICS = {"heart_rate_bpm", "spo2_percent", "skin_adjacent_temperature_c"}


def _number(value: Any, field: str, *, minimum: float = 0, maximum: float = 10000) -> float:
    if isinstance(value, bool):
        abort(400, description=f"{field} must be a number")
    try:
        result = float(value)
    except (TypeError, ValueError):
        abort(400, description=f"{field} must be a number")
    if not minimum <= result <= maximum:
        abort(400, description=f"{field} is outside a supported range")
    return result


def lab_result_input(body: dict[str, Any]) -> dict[str, Any]:
    """Validate a manually confirmed lab result for later clinician review.

    A report can be transcribed or parsed from text on-device, but the server
    only persists confirmed values and never marks a patient healthy/unhealthy.
    """

    category = body.get("category")
    if category not in LAB_CATEGORIES:
        abort(400, description="category must be gestational_diabetes or thyroid")
    test_type = str(body.get("test_type", "")).strip().lower()
    raw_values = body.get("values")
    if not isinstance(raw_values, dict):
        abort(400, description="values must be an object")
    units = body.get("units")
    if not isinstance(units, dict):
        abort(400, description="units must be an object")

    values: dict[str, float] = {}
    if category == "gestational_diabetes":
        if test_type != "75g_ogtt":
            abort(400, description="Gestational diabetes results must identify a 75g_ogtt before submission")
        for key in ("fasting", "one_hour", "two_hour"):
            if key not in raw_values:
                abort(400, description=f"values.{key} is required for a 75g OGTT")
            if str(units.get(key, "")).strip().lower() not in {"mg/dl", "mgdl"}:
                abort(400, description=f"units.{key} must be mg/dL")
            values[key] = _number(raw_values[key], f"values.{key}", maximum=1000)
    else:
        if test_type != "thyroid_function":
            abort(400, description="Thyroid results must use test_type thyroid_function")
        if "tsh" not in raw_values:
            abort(400, description="values.tsh is required for a thyroid result")
        if str(units.get("tsh", "")).strip().lower() not in {"miu/l", "mu/l", "uiu/ml"}:
            abort(400, description="units.tsh must be mIU/L (or equivalent)")
        values["tsh"] = _number(raw_values["tsh"], "values.tsh", maximum=1000)
        if "free_t4" in raw_values:
            unit = str(units.get("free_t4", "")).strip()
            if not unit:
                abort(400, description="units.free_t4 is required when free_t4 is supplied")
            values["free_t4"] = _number(raw_values["free_t4"], "values.free_t4", maximum=1000)

    reported_on = body.get("reported_on")
    if reported_on is not None:
        try:
            reported_on = date.fromisoformat(str(reported_on)).isoformat()
        except ValueError:
            abort(400, description="reported_on must be an ISO date")
    trimester = body.get("trimester")
    if trimester is not None:
        if isinstance(trimester, bool) or not isinstance(trimester, int) or trimester not in {1, 2, 3}:
            abort(400, description="trimester must be 1, 2, or 3")
    return {
        "category": category,
        "test_type": test_type,
        "values": values,
        "units": {key: str(units[key]).strip() for key in values},
        "reported_on": reported_on,
        "trimester": trimester,
        "extraction_method": "patient_confirmed",
    }


def wellbeing_checkin_input(body: dict[str, Any]) -> dict[str, Any]:
    """Validate the five-item *non-diagnostic* support check-in."""

    answers = body.get("answers")
    if not isinstance(answers, dict):
        abort(400, description="answers must be an object")
    keys = ("mood", "enjoyment", "overwhelmed", "support", "safety")
    if set(answers) != set(keys):
        abort(400, description="answers must include mood, enjoyment, overwhelmed, support, and safety")
    validated = {key: str(answers[key]).strip() for key in keys}
    if any(validated[key] not in CHECKIN_ANSWERS for key in keys[:-1]):
        abort(400, description="wellbeing answers use the supported response options")
    if validated["safety"] not in SAFETY_ANSWERS:
        abort(400, description="answers.safety must be no, yes, or prefer_not_to_say")
    consent = body.get("guardian_notification_consent", False)
    if not isinstance(consent, bool):
        abort(400, description="guardian_notification_consent must be a boolean")
    return {
        "answers": validated,
        "immediate_safety_concern": validated["safety"] == "yes",
        "guardian_notification_consent": consent,
    }


def extract_supported_values(category: str, text: str) -> dict[str, Any]:
    """Best-effort text extraction for a *patient to confirm* before save.

    This has deliberately narrow patterns and reports no clinical status. Image
    OCR belongs on a consented device flow; the backend receives only text the
    patient elects to submit.
    """

    if category not in LAB_CATEGORIES:
        abort(400, description="category must be gestational_diabetes or thyroid")
    normalized = " ".join(str(text or "").split())[:5000]
    if not normalized:
        abort(400, description="report_text is required")

    def match(pattern: str) -> float | None:
        found = re.search(pattern, normalized, flags=re.IGNORECASE)
        return float(found.group(1)) if found else None

    if category == "gestational_diabetes":
        values = {
            "fasting": match(r"(?:fasting|fast)\D{0,24}(\d{1,3}(?:\.\d+)?)\s*(?:mg\s*/?\s*d[l1])"),
            "one_hour": match(r"(?:1\s*(?:hour|hr)|one\s*hour)\D{0,24}(\d{1,3}(?:\.\d+)?)\s*(?:mg\s*/?\s*d[l1])"),
            "two_hour": match(r"(?:2\s*(?:hour|hr)|two\s*hour)\D{0,24}(\d{1,3}(?:\.\d+)?)\s*(?:mg\s*/?\s*d[l1])"),
        }
        values = {key: value for key, value in values.items() if value is not None}
        return {"category": category, "test_type": "75g_ogtt", "values": values,
                "units": {key: "mg/dL" for key in values}, "requires_confirmation": True}
    values = {"tsh": match(r"\bTSH\D{0,24}(\d{1,3}(?:\.\d+)?)\s*(?:m?IU\s*/?\s*L|uIU\s*/?\s*mL)")}
    values = {key: value for key, value in values.items() if value is not None}
    return {"category": category, "test_type": "thyroid_function", "values": values,
            "units": {key: "mIU/L" for key in values}, "requires_confirmation": True}


def _short_text(value: Any, field: str, *, maximum: int, required: bool = True) -> str | None:
    if value is None and not required:
        return None
    if not isinstance(value, str):
        abort(400, description=f"{field} must be text")
    cleaned = value.strip()
    if required and not cleaned:
        abort(400, description=f"{field} is required")
    if len(cleaned) > maximum:
        abort(400, description=f"{field} must not exceed {maximum} characters")
    return cleaned or None


def _string_list(value: Any, field: str, *, maximum_items: int = 20, item_maximum: int = 160) -> list[str]:
    if not isinstance(value, list) or len(value) > maximum_items:
        abort(400, description=f"{field} must contain no more than {maximum_items} items")
    cleaned: list[str] = []
    for item in value:
        text = _short_text(item, field, maximum=item_maximum)
        if text and text not in cleaned:
            cleaned.append(text)
    return cleaned


def clinical_profile_input(body: dict[str, Any]) -> dict[str, Any]:
    """Validate patient-reported background without treating it as confirmed history."""

    stage = body.get("pregnancy_stage", "not_recorded")
    if stage not in PREGNANCY_STAGES:
        abort(400, description="pregnancy_stage is invalid")
    history = body.get("history", {})
    if not isinstance(history, dict):
        abort(400, description="history must be an object")
    allowed = {
        "previous_hypertension", "gdm_or_diabetes_history", "previous_pregnancy_complications",
        "other_conditions", "allergies",
    }
    if not set(history).issubset(allowed):
        abort(400, description="history includes an unsupported field")
    for field in ("previous_hypertension", "gdm_or_diabetes_history"):
        if field in history and not isinstance(history[field], bool):
            abort(400, description=f"history.{field} must be a boolean")
    validated_history = {
        "previous_hypertension": bool(history.get("previous_hypertension", False)),
        "gdm_or_diabetes_history": bool(history.get("gdm_or_diabetes_history", False)),
        "previous_pregnancy_complications": _string_list(
            history.get("previous_pregnancy_complications", []), "history.previous_pregnancy_complications"
        ),
        "other_conditions": _string_list(history.get("other_conditions", []), "history.other_conditions"),
        "allergies": _string_list(history.get("allergies", []), "history.allergies"),
    }
    return {
        "pregnancy_stage": stage,
        "history": validated_history,
        "current_medications": _string_list(body.get("current_medications", []), "current_medications"),
    }


def care_message_input(body: dict[str, Any]) -> dict[str, Any]:
    in_reply_to = _short_text(body.get("in_reply_to"), "in_reply_to", maximum=64, required=False)
    if in_reply_to:
        try:
            UUID(in_reply_to)
        except ValueError:
            abort(400, description="in_reply_to must be a valid message identifier")
    return {
        "body": _short_text(body.get("body"), "body", maximum=2000),
        "in_reply_to": in_reply_to,
    }


def activity_entry_input(body: dict[str, Any]) -> dict[str, Any]:
    activity_type = body.get("activity_type")
    session_part = body.get("session_part", "other")
    if activity_type not in ACTIVITY_TYPES or session_part not in ACTIVITY_PARTS:
        abort(400, description="activity_type or session_part is invalid")
    minutes = body.get("minutes")
    if isinstance(minutes, bool) or not isinstance(minutes, int) or not 1 <= minutes <= 180:
        abort(400, description="minutes must be a whole number between 1 and 180")
    return {
        "activity_type": activity_type,
        "session_part": session_part,
        "minutes": minutes,
        "note": _short_text(body.get("note"), "note", maximum=500, required=False),
    }


def clinician_guidance_input(body: dict[str, Any]) -> dict[str, str]:
    category = body.get("category")
    if category not in GUIDANCE_CATEGORIES:
        abort(400, description="guidance category is invalid")
    return {
        "category": category,
        "title": _short_text(body.get("title"), "title", maximum=160),
        "body": _short_text(body.get("body"), "body", maximum=4000),
    }


def validation_observation_input(body: dict[str, Any]) -> dict[str, Any]:
    metric = body.get("metric")
    if metric not in VALIDATION_METRICS:
        abort(400, description="metric is invalid")
    wearable_value = _number(body.get("wearable_value"), "wearable_value", maximum=1000)
    reference_value = _number(body.get("reference_value"), "reference_value", maximum=1000)
    label = _short_text(body.get("reference_device_label"), "reference_device_label", maximum=160)
    observed = body.get("observation_time")
    if not isinstance(observed, str):
        abort(400, description="observation_time must be an ISO-8601 timestamp")
    try:
        observed_at = datetime.fromisoformat(observed.replace("Z", "+00:00"))
    except ValueError:
        abort(400, description="observation_time must be an ISO-8601 timestamp")
    if observed_at.tzinfo is None:
        abort(400, description="observation_time must include a timezone")
    if observed_at.astimezone(timezone.utc) > datetime.now(timezone.utc).replace(microsecond=0):
        abort(400, description="observation_time cannot be in the future")
    return {
        "metric": metric,
        "wearable_value": wearable_value,
        "reference_value": reference_value,
        "reference_device_label": label,
        "observation_time": observed_at.astimezone(timezone.utc),
        "note": _short_text(body.get("note"), "note", maximum=1000, required=False),
    }
