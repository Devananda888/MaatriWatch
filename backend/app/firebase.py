"""Firebase Admin initialisation and RTDB projection helpers."""

from __future__ import annotations

import json
from datetime import datetime, timezone

import firebase_admin
from firebase_admin import credentials, db
from flask import current_app


def init_firebase(app):
    """Initialise Firebase Auth independently from optional RTDB live sync."""
    raw_service_account = app.config.get("FIREBASE_SERVICE_ACCOUNT_JSON")
    database_url = app.config.get("FIREBASE_DATABASE_URL")
    project_id = app.config.get("FIREBASE_PROJECT_ID")
    if not raw_service_account and not project_id:
        return
    options = {
        **({"databaseURL": database_url} if database_url else {}),
        **({"projectId": project_id} if project_id else {}),
    }
    try:
        existing_app = firebase_admin.get_app()
        if database_url and existing_app.options.get("databaseURL") != database_url:
            app.logger.error("Existing Firebase Admin app has a different or missing RTDB URL")
            database_url = None
    except ValueError:
        # No default app yet: create it from deployment-provided credentials.
        try:
            credential = credentials.Certificate(json.loads(raw_service_account)) if raw_service_account else credentials.ApplicationDefault()
            # ApplicationDefault defers discovery until the first request. Probe
            # it here so the health/readiness flags do not claim RTDB is usable
            # on a workstation with no Google credentials.
            credential.get_credential()
            firebase_admin.initialize_app(credential, options)
        except Exception:
            app.logger.warning("Firebase Admin initialisation failed; Auth/RTDB server paths are unavailable")
            return
    try:
        # Token verification remains usable when RTDB is temporarily unavailable.
        firebase_admin.get_app()
        app.config["FIREBASE_AUTH_READY"] = True
        app.config["FIREBASE_READY"] = True
        app.config["FIREBASE_RTDB_READY"] = bool(database_url)
    except Exception:
        app.logger.exception("Firebase Admin is unavailable")


def live_vitals_ref(hospital_id: str, patient_id: str):
    if not current_app.config.get("FIREBASE_RTDB_READY"):
        raise RuntimeError("Firebase Admin is unavailable")
    return db.reference(f"live_vitals/{hospital_id}/{patient_id}")


def project_live_vitals(hospital_id: str, patient_id: str, reading: dict):
    """Project only a monotonic latest reading, even when the outbox retries out of order."""
    reference = live_vitals_ref(hospital_id, patient_id)

    def keep_newest(current):
        if not current or _is_newer(reading, current):
            return reading
        return current

    reference.transaction(keep_newest)


def project_live_alert(hospital_id: str, alert_id: str, alert: dict):
    if not current_app.config.get("FIREBASE_RTDB_READY"):
        raise RuntimeError("Firebase Admin is unavailable")
    # Delivery is at least once and workers can run out of order. Keep only the
    # newest small, non-PHI clinician queue projection for this alert episode.
    reference = db.reference(f"live_alerts/{hospital_id}/{alert_id}")

    def keep_newest(current):
        if not current or _is_newer_alert(alert, current):
            return alert
        return current

    reference.transaction(keep_newest)


def clinician_entitlements(memberships: list[dict]) -> dict[str, dict]:
    """Build the minimal RTDB grants required by the clinician dashboard.

    Postgres is the authority for memberships.  RTDB receives only this small
    read-entitlement projection so its rules can permit live subscriptions
    without exposing hospital records to every authenticated Firebase user.
    """
    values: dict[str, dict] = {}
    for membership in memberships:
        hospital_id = str(membership["hospital_id"])
        role = membership["role"]
        active = bool(membership.get("is_active", True)) and role in {"clinician", "hospital_admin"}
        values[hospital_id] = {
            "role": role,
            "active": active,
            "can_read_all_live_vitals": active,
            "can_read_alert_queue": active,
        }
    return values


def sync_clinician_entitlements(firebase_uid: str, memberships: list[dict]) -> None:
    """Best-effort refresh of a signed-in clinician's RTDB read grants.

    A failure here must not prevent the REST dashboard from using the durable
    Postgres record.  It simply leaves the UI in its existing Refresh fallback.
    """
    if not current_app.config.get("FIREBASE_RTDB_READY"):
        return
    entitlements = clinician_entitlements(memberships)
    if not entitlements:
        return
    try:
        db.reference(f"access/{firebase_uid}").update(entitlements)
    except Exception:
        current_app.logger.exception("Failed to refresh Firebase RTDB clinician entitlements")


def publish_realtime_projection(topic: str, payload: dict):
    """Dispatch a durable outbox message to its Firebase RTDB projection."""
    if topic == "live_vitals":
        project_live_vitals(payload["hospital_id"], payload["patient_id"], payload["reading"])
        return
    if topic == "live_alert":
        project_live_alert(payload["hospital_id"], payload["alert_id"], payload["alert"])
        return
    raise ValueError(f"Unsupported realtime outbox topic: {topic}")


def _is_newer(candidate: dict, current: dict) -> bool:
    """Use capture time then event ID as a stable tie-breaker for RTDB retries."""
    candidate_time = _timestamp(candidate.get("captured_at"))
    current_time = _timestamp(current.get("captured_at"))
    if candidate_time != current_time:
        return candidate_time > current_time
    candidate_sequence = candidate.get("source_sequence")
    current_sequence = current.get("source_sequence")
    if (
        isinstance(candidate_sequence, int)
        and not isinstance(candidate_sequence, bool)
        and isinstance(current_sequence, int)
        and not isinstance(current_sequence, bool)
        and candidate_sequence != current_sequence
    ):
        return candidate_sequence > current_sequence
    return str(candidate.get("source_event_id", "")) > str(current.get("source_event_id", ""))


def _timestamp(value) -> datetime:
    if not isinstance(value, str):
        return datetime.min.replace(tzinfo=timezone.utc)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed.astimezone(timezone.utc) if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return datetime.min.replace(tzinfo=timezone.utc)


def _is_newer_alert(candidate: dict, current: dict) -> bool:
    # Clinical workflow state may change without a new sensor observation.  Use
    # updated_at first so an acknowledgement or resolution replaces an older
    # live alert even when last_seen_at is unchanged.
    candidate_time = _timestamp(candidate.get("updated_at") or candidate.get("last_seen_at"))
    current_time = _timestamp(current.get("updated_at") or current.get("last_seen_at"))
    if candidate_time != current_time:
        return candidate_time > current_time
    return int(candidate.get("occurrence_count", 0)) > int(current.get("occurrence_count", 0))
