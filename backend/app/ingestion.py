"""Authenticated HTTP ingestion for normalized wearable telemetry."""

from __future__ import annotations

import hashlib
import json
import math
import re
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from flask import Blueprint, abort, current_app, jsonify, request
from psycopg.types.json import Jsonb

from .alerting import POLICY_VERSION, evaluate_alerts
from .db import get_db
from .outbox import deliver_outbox_ids, enqueue_projection

ingestion_bp = Blueprint("ingestion", __name__)
_hasher = PasswordHasher()
_MEASUREMENT_FIELDS = (
    "heart_rate_bpm",
    "spo2_percent",
    "temperature_c",
    "systolic_bp",
    "diastolic_bp",
    "battery_percent",
    "blood_loss_ml",
)
_INTEGER_FIELDS = {"heart_rate_bpm", "systolic_bp", "diastolic_bp", "battery_percent"}
_RANGES = {
    "heart_rate_bpm": (20, 260),
    "spo2_percent": (0, 100),
    "temperature_c": (25, 45),
    "systolic_bp": (50, 260),
    "diastolic_bp": (30, 180),
    "battery_percent": (0, 100),
    "blood_loss_ml": (0, 10000),
}
_MOTION_NUMERIC_FIELDS = {
    "impact_g": (0, 20),
    "orientation_change_degrees": (0, 360),
    "post_impact_immobile_seconds": (0, 3600),
    "classifier_confidence": (0, 1),
}
_EVENT_ID_PATTERN = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")


def _parse_timestamp(value):
    if not isinstance(value, str) or not value:
        abort(400, description="captured_at is required and must be an ISO-8601 timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        abort(400, description="captured_at must be an ISO-8601 timestamp")
    if parsed.tzinfo is None:
        abort(400, description="captured_at must include a timezone")
    parsed = parsed.astimezone(timezone.utc)
    if parsed > datetime.now(timezone.utc) + timedelta(minutes=5):
        abort(400, description="captured_at cannot be more than five minutes in the future")
    return parsed


def _parse_uuid(value: str | None, field: str) -> UUID:
    try:
        return UUID(value or "")
    except (ValueError, AttributeError):
        abort(401, description=f"{field} must be a valid UUID")


def _locked_device_for_request(connection):
    """Authenticate and lock the current device assignment for this transaction."""
    device_id = _parse_uuid(request.headers.get("X-Device-Id"), "X-Device-Id")
    device_key = request.headers.get("X-Device-Key")
    if not device_key:
        abort(401, description="X-Device-Key is required")
    with connection.cursor() as cursor:
        cursor.execute(
            """SELECT d.id, d.hospital_id, d.assigned_patient_id, d.api_key_hash, d.status
                 FROM devices d
                 JOIN patients p ON p.id = d.assigned_patient_id AND p.is_active = true
                 WHERE d.id = %s
                 FOR UPDATE OF d""",
            (device_id,),
        )
        device = cursor.fetchone()
    if not device or device["status"] != "assigned" or not device["assigned_patient_id"]:
        abort(401, description="This device is not active or assigned")
    try:
        key_valid = _hasher.verify(device["api_key_hash"], device_key)
    except (VerificationError, InvalidHashError):
        key_valid = False
    if not key_valid:
        abort(401, description="Invalid device credentials")
    return device


def _number(value, field: str, lower: float, upper: float, integer: bool = False):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        abort(400, description=f"{field} must be a finite numeric value")
    if integer and not isinstance(value, int):
        abort(400, description=f"{field} must be an integer")
    if not lower <= value <= upper:
        abort(400, description=f"{field} must be between {lower} and {upper}")
    return value


def _parse_motion(value):
    if value is None:
        return {}
    if not isinstance(value, dict):
        abort(400, description="motion must be a JSON object")
    motion = dict(value)
    if "fall_detected" in motion and not isinstance(motion["fall_detected"], bool):
        abort(400, description="motion.fall_detected must be a boolean")
    for field, (lower, upper) in _MOTION_NUMERIC_FIELDS.items():
        if field in motion and motion[field] is not None:
            motion[field] = _number(motion[field], f"motion.{field}", lower, upper)
    return motion


def _payload():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        abort(400, description="A JSON object is required")

    event_id = data.get("event_id")
    if not isinstance(event_id, str) or not _EVENT_ID_PATTERN.fullmatch(event_id):
        abort(400, description="event_id is required (1-128 URL-safe characters)")

    parsed = {}
    for field in _MEASUREMENT_FIELDS:
        value = data.get(field)
        parsed[field] = (
            None
            if value is None
            else _number(value, field, *_RANGES[field], integer=field in _INTEGER_FIELDS)
        )
    motion = _parse_motion(data.get("motion"))
    if not any(value is not None for value in parsed.values()) and not motion:
        abort(400, description="At least one measurement or motion field is required")

    bleeding_reported = data.get("bleeding_reported", False)
    if not isinstance(bleeding_reported, bool):
        abort(400, description="bleeding_reported must be a boolean")
    source_sequence = data.get("source_sequence")
    if source_sequence is not None:
        source_sequence = _number(source_sequence, "source_sequence", 0, 2_147_483_647, integer=True)

    parsed.update(
        {
            "source_event_id": event_id,
            "source_sequence": source_sequence,
            "captured_at": _parse_timestamp(data.get("captured_at")),
            "motion": motion,
            "bleeding_reported": bleeding_reported,
            "raw_payload": data,
            "payload_fingerprint": _fingerprint(data),
        }
    )
    return parsed


def _fingerprint(payload: dict) -> str:
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _existing_event(cursor, device_id, source_event_id):
    cursor.execute(
        """SELECT id, payload_fingerprint
           FROM vital_readings
           WHERE device_id = %s AND source_event_id = %s""",
        (device_id, source_event_id),
    )
    return cursor.fetchone()


def _upsert_alert(cursor, *, device, reading_id, payload, candidate):
    evidence = {
        "policy_version": POLICY_VERSION,
        "source_event_id": payload["source_event_id"],
        "captured_at": payload["captured_at"].isoformat(),
        "rule_evidence": candidate.evidence,
    }
    cursor.execute(
        """INSERT INTO alerts
           (hospital_id, patient_id, vital_reading_id, severity, status, alert_type,
            message, rule_id, rule_version, dedupe_key, evidence, last_seen_at)
           VALUES (%s, %s, %s, %s, 'open', %s, %s, %s, %s, %s, %s, now())
           ON CONFLICT (hospital_id, patient_id, dedupe_key)
               WHERE dedupe_key IS NOT NULL AND status IN ('open', 'acknowledged', 'escalated')
           DO UPDATE SET
               vital_reading_id = EXCLUDED.vital_reading_id,
               severity = EXCLUDED.severity,
               message = EXCLUDED.message,
               rule_version = EXCLUDED.rule_version,
               evidence = EXCLUDED.evidence,
               last_seen_at = now(),
               occurrence_count = alerts.occurrence_count + 1
           RETURNING id, severity, status, alert_type, message, triggered_at,
                     last_seen_at, occurrence_count, rule_version, updated_at,
                     acknowledged_at, escalated_at, resolved_at""",
        (
            device["hospital_id"],
            device["assigned_patient_id"],
            reading_id,
            candidate.severity,
            candidate.rule_id,
            candidate.message,
            candidate.rule_id,
            POLICY_VERSION,
            candidate.dedupe_key,
            Jsonb(evidence),
        ),
    )
    alert = cursor.fetchone()
    return alert, alert["occurrence_count"] == 1


def _record_alert_observation(cursor, *, alert_id, reading_id, payload, candidate):
    cursor.execute(
        """INSERT INTO alert_observations (alert_id, vital_reading_id, rule_version, evidence)
           VALUES (%s, %s, %s, %s)
           ON CONFLICT (alert_id, vital_reading_id) DO NOTHING""",
        (
            alert_id,
            reading_id,
            POLICY_VERSION,
            Jsonb(
                {
                    "source_event_id": payload["source_event_id"],
                    "captured_at": payload["captured_at"].isoformat(),
                    "rule_evidence": candidate.evidence,
                }
            ),
        ),
    )


def _audit(cursor, *, hospital_id, request_id, action, entity_type, entity_id, metadata):
    cursor.execute(
        """INSERT INTO audit_log (hospital_id, request_id, action, entity_type, entity_id, metadata)
           VALUES (%s, %s, %s, %s, %s, %s)""",
        (hospital_id, request_id, action, entity_type, str(entity_id), Jsonb(metadata)),
    )


def _active_status(cursor, hospital_id, patient_id):
    cursor.execute(
        """SELECT severity FROM alerts
           WHERE hospital_id = %s AND patient_id = %s
             AND status IN ('open', 'acknowledged', 'escalated')
           ORDER BY CASE severity WHEN 'critical' THEN 3 WHEN 'warning' THEN 2 ELSE 1 END DESC
           LIMIT 1""",
        (hospital_id, patient_id),
    )
    result = cursor.fetchone()
    return result["severity"] if result else None


def _live_vitals_payload(device, payload, saved, active_severity):
    return {
        "hospital_id": str(device["hospital_id"]),
        "patient_id": str(device["assigned_patient_id"]),
        "reading": {
            "captured_at": payload["captured_at"].isoformat(),
            "received_at": saved["received_at"].isoformat(),
            "device_id": str(device["id"]),
            "source_event_id": payload["source_event_id"],
            "source_sequence": payload["source_sequence"],
            **{field: payload[field] for field in _MEASUREMENT_FIELDS},
            "motion": payload["motion"],
            "bleeding_reported": payload["bleeding_reported"],
            "assessment_state": "rule_evaluated",
            "status": active_severity or "normal",
        },
    }


def _live_alert_payload(device, alert):
    return {
        "hospital_id": str(device["hospital_id"]),
        "alert_id": str(alert["id"]),
        "alert": {
            "id": str(alert["id"]),
            "patient_id": str(device["assigned_patient_id"]),
            "severity": alert["severity"],
            "status": alert["status"],
            "alert_type": alert["alert_type"],
            "message": alert["message"],
            "triggered_at": alert["triggered_at"].isoformat(),
            "last_seen_at": alert["last_seen_at"].isoformat(),
            "updated_at": alert["updated_at"].isoformat() if alert.get("updated_at") else None,
            "occurrence_count": alert["occurrence_count"],
            "rule_version": alert["rule_version"],
            "acknowledged_at": alert["acknowledged_at"].isoformat() if alert.get("acknowledged_at") else None,
            "escalated_at": alert["escalated_at"].isoformat() if alert.get("escalated_at") else None,
            "resolved_at": alert["resolved_at"].isoformat() if alert.get("resolved_at") else None,
        },
    }


def _duplicate_response(connection, cursor, existing, payload):
    if existing["payload_fingerprint"] != payload["payload_fingerprint"]:
        abort(409, description="event_id was already used with a different payload")
    cursor.execute("SELECT alert_id AS id FROM alert_observations WHERE vital_reading_id = %s", (existing["id"],))
    alert_ids = [str(row["id"]) for row in cursor.fetchall()]
    connection.rollback()
    return jsonify(
        {
            "reading_id": str(existing["id"]),
            "event_id": payload["source_event_id"],
            "duplicate": True,
            "alert_ids": alert_ids,
            "realtime": "unchanged",
        }
    ), 200


@ingestion_bp.post("/ingest/vitals")
@ingestion_bp.post("/ingest/telemetry")
def ingest_vitals():
    """Persist one device event, assess it, and durably queue Firebase projections."""
    payload = _payload()
    if current_app.config.get("DEMO_IN_MEMORY"):
        from .demo_store import DemoStoreError, demo_store

        try:
            result = demo_store.ingest(
                request.headers.get("X-Device-Id", ""),
                request.headers.get("X-Device-Key"),
                payload,
            )
        except DemoStoreError as error:
            abort(error.status_code, description=str(error))
        return jsonify(result), 200 if result["duplicate"] else 201
    connection = get_db()
    request_id = uuid4()
    outbox_ids: list = []

    with connection.cursor() as cursor:
        device = _locked_device_for_request(connection)
        existing = _existing_event(cursor, device["id"], payload["source_event_id"])
        if existing:
            return _duplicate_response(connection, cursor, existing, payload)

        cursor.execute(
            """INSERT INTO vital_readings
               (hospital_id, patient_id, device_id, source_event_id, source_sequence,
                payload_fingerprint, captured_at, heart_rate_bpm, spo2_percent,
                temperature_c, systolic_bp, diastolic_bp, battery_percent, blood_loss_ml,
                bleeding_reported, motion, raw_payload)
               VALUES (%(hospital_id)s, %(patient_id)s, %(device_id)s, %(source_event_id)s,
                       %(source_sequence)s, %(payload_fingerprint)s, %(captured_at)s,
                       %(heart_rate_bpm)s, %(spo2_percent)s, %(temperature_c)s,
                       %(systolic_bp)s, %(diastolic_bp)s, %(battery_percent)s,
                       %(blood_loss_ml)s, %(bleeding_reported)s, %(motion)s, %(raw_payload)s)
               ON CONFLICT (device_id, source_event_id) WHERE source_event_id IS NOT NULL DO NOTHING
               RETURNING id, received_at""",
            {
                "hospital_id": device["hospital_id"],
                "patient_id": device["assigned_patient_id"],
                "device_id": device["id"],
                **payload,
                "motion": Jsonb(payload["motion"]),
                "raw_payload": Jsonb(payload["raw_payload"]),
            },
        )
        saved = cursor.fetchone()
        if saved is None:
            # A concurrent retry won the unique event-ID race. It committed
            # first (Postgres waits for that transaction), so return its result
            # without evaluating or delivering the event a second time.
            existing = _existing_event(cursor, device["id"], payload["source_event_id"])
            if not existing:
                abort(409, description="event_id conflict could not be resolved")
            return _duplicate_response(connection, cursor, existing, payload)
        cursor.execute("UPDATE devices SET last_seen_at = now(), updated_at = now() WHERE id = %s", (device["id"],))

        alerts = []
        for candidate in evaluate_alerts(payload):
            alert, created = _upsert_alert(cursor, device=device, reading_id=saved["id"], payload=payload, candidate=candidate)
            _record_alert_observation(
                cursor,
                alert_id=alert["id"],
                reading_id=saved["id"],
                payload=payload,
                candidate=candidate,
            )
            alerts.append(alert)
            outbox_ids.append(
                enqueue_projection(
                    cursor,
                    topic="live_alert",
                    payload=_live_alert_payload(device, alert),
                    idempotency_key=f"live-alert:{alert['id']}:{saved['id']}",
                )
            )
            if created:
                _audit(
                    cursor,
                    hospital_id=device["hospital_id"],
                    request_id=request_id,
                    action="alert.created",
                    entity_type="alert",
                    entity_id=alert["id"],
                    metadata={
                        "device_id": str(device["id"]),
                        "patient_id": str(device["assigned_patient_id"]),
                        "event_id": payload["source_event_id"],
                        "rule_id": candidate.rule_id,
                        "rule_version": POLICY_VERSION,
                    },
                )

        active_severity = _active_status(cursor, device["hospital_id"], device["assigned_patient_id"])
        outbox_ids.append(
            enqueue_projection(
                cursor,
                topic="live_vitals",
                payload=_live_vitals_payload(device, payload, saved, active_severity),
                idempotency_key=f"live-vitals:{saved['id']}",
            )
        )
    connection.commit()

    # Fast path for live dashboards. The transactional outbox remains the
    # source of retry truth if Firebase is offline or slow.
    delivery = deliver_outbox_ids(outbox_ids)
    realtime = "synced" if delivery["pending"] == 0 else "pending"
    return jsonify(
        {
            "reading_id": str(saved["id"]),
            "event_id": payload["source_event_id"],
            "duplicate": False,
            "alert_ids": [str(alert["id"]) for alert in alerts],
            "realtime": realtime,
        }
    ), 201
