"""Hospital-scoped clinician dashboard APIs.

Postgres remains authoritative for records, history, notes, and workflows.
Firebase RTDB is deliberately used only as a low-latency overlay by the web
client; no browser action writes directly to RTDB.
"""

from __future__ import annotations

import json
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from uuid import UUID, uuid4

from flask import Blueprint, abort, current_app, g, jsonify, request
from psycopg.types.json import Jsonb

from .auth import require_hospital_role
from .db import get_db
from .measurements import public_vital
from .outbox import deliver_outbox_ids, enqueue_projection
from .patient_workflows import (
    care_message_input,
    clinician_guidance_input,
    clinical_profile_input,
    validation_observation_input,
)

clinician_bp = Blueprint("clinician", __name__)

_ACTIVE_ALERT_STATUSES = ("open", "acknowledged", "escalated")
_ALERT_STATUSES = (*_ACTIVE_ALERT_STATUSES, "resolved")
_SEVERITIES = ("info", "warning", "critical")
_PATIENT_STATUSES = ("all", "normal", *_SEVERITIES)
_PATIENT_SORTS = {
    "risk": "COALESCE(active.risk_rank, 0) DESC, active.latest_alert_at DESC NULLS LAST, p.full_name ASC",
    "name": "p.full_name ASC, p.id ASC",
    "recent": "latest_vital.observed_at DESC NULLS LAST, p.full_name ASC, p.id ASC",
}


def _demo_enabled() -> bool:
    return bool(current_app.config.get("DEMO_IN_MEMORY"))


def _demo_result(callback, *, status_code: int = 200):
    """Adapt the isolated in-memory hackathon store to Flask responses."""
    from .demo_store import DemoStoreError

    try:
        payload = callback()
    except DemoStoreError as error:
        abort(error.status_code, description=str(error))
    return jsonify(payload), status_code


def _identifier(value: str, label: str) -> UUID:
    try:
        return UUID(value)
    except (TypeError, ValueError):
        abort(400, description=f"{label} must be a valid UUID")


def _limit(default: int, maximum: int) -> int:
    value = request.args.get("limit", str(default))
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        abort(400, description="limit must be an integer")
    if not 1 <= parsed <= maximum:
        abort(400, description=f"limit must be between 1 and {maximum}")
    return parsed


def _json_object() -> dict:
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        abort(400, description="A JSON object is required")
    return payload


def _required_note(payload: dict, *, required: bool) -> str | None:
    note = payload.get("note")
    if note is None and not required:
        return None
    if not isinstance(note, str):
        abort(400, description="note must be text")
    note = note.strip()
    if required and not note:
        abort(400, description="A clinical note is required for this action")
    if len(note) > 5_000:
        abort(400, description="note must not exceed 5000 characters")
    return note or None


def _parse_time(value: str | None, name: str, default: datetime) -> datetime:
    if value is None:
        return default
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        abort(400, description=f"{name} must be an ISO-8601 timestamp")
    if parsed.tzinfo is None:
        abort(400, description=f"{name} must include a timezone")
    return parsed.astimezone(timezone.utc)


def _wire(value):
    """Convert psycopg values to conservative JSON primitives."""
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, dict):
        return {key: _wire(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_wire(item) for item in value]
    return value


def _row(row: dict | None):
    return _wire(row) if row else None


def _patient_or_404(cursor, hospital_id: UUID, patient_id: UUID) -> dict:
    cursor.execute(
        """SELECT id, hospital_id, medical_record_number, full_name, date_of_birth,
                  preferred_language, delivery_date, emergency_contact_name,
                  emergency_contact_phone, consented_at, is_active, created_at, updated_at
           FROM patients
           WHERE hospital_id = %s AND id = %s AND is_active = true""",
        (hospital_id, patient_id),
    )
    patient = cursor.fetchone()
    if not patient:
        abort(404, description="Patient was not found in this hospital")
    return patient


def _audit(cursor, *, hospital_id, action: str, entity_type: str, entity_id, metadata: dict, request_id):
    cursor.execute(
        """INSERT INTO audit_log
           (actor_user_id, hospital_id, action, entity_type, entity_id, request_id, metadata, ip_address)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
        (
            g.actor["id"],
            hospital_id,
            action,
            entity_type,
            str(entity_id),
            request_id,
            Jsonb(metadata),
            request.remote_addr,
        ),
    )


def _live_alert_payload(alert: dict) -> dict:
    def instant(name: str):
        value = alert.get(name)
        return _wire(value) if value is not None else None

    return {
        "hospital_id": str(alert["hospital_id"]),
        "alert_id": str(alert["id"]),
        "alert": {
            "id": str(alert["id"]),
            "patient_id": str(alert["patient_id"]),
            "severity": alert["severity"],
            "status": alert["status"],
            "alert_type": alert["alert_type"],
            "message": alert["message"],
            "triggered_at": instant("triggered_at"),
            "last_seen_at": instant("last_seen_at"),
            "updated_at": instant("updated_at"),
            "occurrence_count": alert["occurrence_count"],
            "rule_version": alert.get("rule_version"),
            "acknowledged_at": instant("acknowledged_at"),
            "escalated_at": instant("escalated_at"),
            "resolved_at": instant("resolved_at"),
        },
    }


def _alert_by_id_for_update(cursor, hospital_id: UUID, alert_id: UUID) -> dict:
    cursor.execute(
        """SELECT id, hospital_id, patient_id, severity, status, alert_type, message,
                  triggered_at, last_seen_at, occurrence_count, rule_version, updated_at,
                  acknowledged_by, acknowledged_at, escalated_by, escalated_at,
                  escalation_note, resolved_by, resolved_at, resolution_note
           FROM alerts
           WHERE hospital_id = %s AND id = %s
           FOR UPDATE""",
        (hospital_id, alert_id),
    )
    alert = cursor.fetchone()
    if not alert:
        abort(404, description="Alert was not found in this hospital")
    return alert


@clinician_bp.get("/hospitals/<hospital_id>/patients")
@require_hospital_role("clinician")
def patients(hospital_id: str):
    """A stable ordered patient list. RTDB updates must not change this order."""
    hospital_uuid = _identifier(hospital_id, "hospital_id")
    status = request.args.get("status", "all")
    if status not in _PATIENT_STATUSES:
        abort(400, description="status must be all, normal, info, warning, or critical")
    sort = request.args.get("sort", "risk")
    if sort not in _PATIENT_SORTS:
        abort(400, description="sort must be risk, name, or recent")
    limit = _limit(100, 250)
    if _demo_enabled():
        from .demo_store import demo_store

        return _demo_result(lambda: demo_store.patient_list(status=status, sort=sort, limit=limit))
    connection = get_db()
    with connection.cursor() as cursor:
        cursor.execute(
            f"""SELECT p.id, p.medical_record_number, p.full_name, p.preferred_language,
                       p.delivery_date, latest_vital.observed_at AS latest_captured_at,
                       latest_vital.observed_at AS latest_observed_at, latest_vital.received_at AS latest_received_at,
                       latest_vital.heart_rate_bpm, latest_vital.spo2_percent,
                       latest_vital.heart_rate_source, latest_vital.spo2_source,
                       latest_vital.temperature_c, latest_vital.temperature_source,
                       latest_vital.ambient_temperature_c,
                       latest_vital.ambient_humidity_percent, latest_vital.systolic_bp,
                       latest_vital.diastolic_bp, latest_vital.blood_pressure_source,
                       latest_vital.contact_detected, latest_vital.signal_quality,
                       latest_vital.sensor_status, device.id AS device_id,
                       device.serial_number AS device_serial_number,
                       device.last_seen_at AS device_last_seen_at,
                       COALESCE(active.active_alert_count, 0) AS active_alert_count,
                       active.highest_severity, active.latest_alert_at
                FROM patients p
                LEFT JOIN LATERAL (
                    SELECT captured_at, observed_at, received_at, heart_rate_bpm, spo2_percent,
                           heart_rate_source, spo2_source, temperature_c,
                           temperature_source,
                           ambient_temperature_c, ambient_humidity_percent,
                           systolic_bp, diastolic_bp, blood_pressure_source,
                           contact_detected, signal_quality, sensor_status
                    FROM vital_readings
                    WHERE hospital_id = p.hospital_id AND patient_id = p.id
                    ORDER BY observed_at DESC, id DESC LIMIT 1
                ) latest_vital ON true
                LEFT JOIN LATERAL (
                    SELECT id, serial_number, last_seen_at
                    FROM devices
                    WHERE hospital_id = p.hospital_id AND assigned_patient_id = p.id
                      AND status = 'assigned'
                    ORDER BY last_seen_at DESC NULLS LAST, id DESC LIMIT 1
                ) device ON true
                LEFT JOIN LATERAL (
                    SELECT max(CASE severity WHEN 'critical' THEN 3 WHEN 'warning' THEN 2 ELSE 1 END) AS risk_rank,
                           (array_agg(severity ORDER BY CASE severity WHEN 'critical' THEN 3 WHEN 'warning' THEN 2 ELSE 1 END DESC))[1] AS highest_severity,
                           count(*) AS active_alert_count,
                           max(updated_at) AS latest_alert_at
                    FROM alerts
                    WHERE hospital_id = p.hospital_id AND patient_id = p.id
                      AND status IN ('open', 'acknowledged', 'escalated')
                ) active ON true
                WHERE p.hospital_id = %s AND p.is_active = true
                  AND (%s = 'all' OR COALESCE(active.highest_severity::text, 'normal') = %s)
                ORDER BY {_PATIENT_SORTS[sort]}
                LIMIT %s""",
            (hospital_uuid, status, status, limit),
        )
        rows = cursor.fetchall()
    items = []
    for value in rows:
        highest = value["highest_severity"]
        items.append(
            {
                "id": str(value["id"]),
                "medical_record_number": value["medical_record_number"],
                "full_name": value["full_name"],
                "preferred_language": value["preferred_language"],
                "delivery_date": _wire(value["delivery_date"]),
                "status": highest or "normal",
                "active_alert_count": value["active_alert_count"],
                "latest_vital": _wire(
                    public_vital(
                        {
                        "captured_at": value["latest_captured_at"],
                        "observed_at": value["latest_observed_at"],
                        "received_at": value["latest_received_at"],
                        "heart_rate_bpm": value["heart_rate_bpm"],
                        "spo2_percent": value["spo2_percent"],
                        "heart_rate_source": value["heart_rate_source"],
                        "spo2_source": value["spo2_source"],
                        "temperature_c": value["temperature_c"],
                        "temperature_source": value["temperature_source"],
                        "ambient_temperature_c": value["ambient_temperature_c"],
                        "ambient_humidity_percent": value["ambient_humidity_percent"],
                        "systolic_bp": value["systolic_bp"],
                        "diastolic_bp": value["diastolic_bp"],
                        "blood_pressure_source": value["blood_pressure_source"],
                        "contact_detected": value["contact_detected"],
                        "signal_quality": value["signal_quality"],
                        "sensor_status": value["sensor_status"],
                        }
                    )
                    if value["latest_captured_at"]
                    else None
                ),
                "device": _wire(
                    {
                        "id": value["device_id"],
                        "serial_number": value["device_serial_number"],
                        "last_seen_at": value["device_last_seen_at"],
                    }
                    if value["device_id"]
                    else None
                ),
            }
        )
    return jsonify({"items": items, "sort": sort, "status_filter": status, "live_ordering": "stable"})


@clinician_bp.get("/hospitals/<hospital_id>/patients/<patient_id>")
@require_hospital_role("clinician")
def patient_detail(hospital_id: str, patient_id: str):
    hospital_uuid = _identifier(hospital_id, "hospital_id")
    patient_uuid = _identifier(patient_id, "patient_id")
    if _demo_enabled():
        from .demo_store import demo_store

        return _demo_result(lambda: demo_store.patient_detail(str(patient_uuid)))
    connection = get_db()
    with connection.cursor() as cursor:
        patient = _patient_or_404(cursor, hospital_uuid, patient_uuid)
        cursor.execute(
            """SELECT captured_at, observed_at, received_at, heart_rate_bpm, spo2_percent,
                      heart_rate_source, spo2_source, temperature_c,
                      temperature_source, blood_pressure_source, contact_detected,
                      signal_quality, sensor_status,
                      ambient_temperature_c, ambient_humidity_percent,
                      systolic_bp, diastolic_bp, battery_percent, blood_loss_ml,
                      bleeding_reported, motion
               FROM vital_readings
               WHERE hospital_id = %s AND patient_id = %s
               ORDER BY observed_at DESC, id DESC LIMIT 1""",
            (hospital_uuid, patient_uuid),
        )
        latest_vital = cursor.fetchone()
        cursor.execute(
            """SELECT id, serial_number, firmware_version, last_seen_at
               FROM devices
               WHERE hospital_id = %s AND assigned_patient_id = %s AND status = 'assigned'
               ORDER BY last_seen_at DESC NULLS LAST, id DESC LIMIT 1""",
            (hospital_uuid, patient_uuid),
        )
        device = cursor.fetchone()
        cursor.execute(
            """SELECT severity, count(*) AS count
               FROM alerts
               WHERE hospital_id = %s AND patient_id = %s
                 AND status IN ('open', 'acknowledged', 'escalated')
               GROUP BY severity
               ORDER BY CASE severity WHEN 'critical' THEN 3 WHEN 'warning' THEN 2 ELSE 1 END DESC""",
            (hospital_uuid, patient_uuid),
        )
        active_alerts = cursor.fetchall()
        cursor.execute(
            """SELECT screening_type, language_code, score, risk_level, submitted_at,
                      reviewed_at
               FROM screenings
               WHERE hospital_id = %s AND patient_id = %s
               ORDER BY submitted_at DESC LIMIT 1""",
            (hospital_uuid, patient_uuid),
        )
        latest_screening = cursor.fetchone()
    highest = active_alerts[0]["severity"] if active_alerts else "normal"
    return jsonify(
        {
            "patient": _row(patient),
            "status": highest,
            "latest_vital": _wire(public_vital(latest_vital)),
            "device": _row(device),
            "active_alerts": _wire(active_alerts),
            "latest_screening": _row(latest_screening),
        }
    )


@clinician_bp.get("/hospitals/<hospital_id>/patients/<patient_id>/vitals")
@require_hospital_role("clinician")
def patient_vitals(hospital_id: str, patient_id: str):
    hospital_uuid = _identifier(hospital_id, "hospital_id")
    patient_uuid = _identifier(patient_id, "patient_id")
    now = datetime.now(timezone.utc)
    start = _parse_time(request.args.get("from"), "from", now - timedelta(days=1))
    end = _parse_time(request.args.get("to"), "to", now)
    if start >= end:
        abort(400, description="from must be before to")
    if end - start > timedelta(days=31):
        abort(400, description="Vital trend range must not exceed 31 days")
    resolution = request.args.get("resolution", "raw")
    if resolution not in {"raw", "5m", "1h"}:
        abort(400, description="resolution must be raw, 5m, or 1h")
    limit = _limit(1_000 if resolution == "raw" else 2_000, 2_000)
    if _demo_enabled():
        from .demo_store import demo_store

        return _demo_result(
            lambda: demo_store.patient_vitals(
                str(patient_uuid), start=start, end=end, resolution=resolution, limit=limit
            )
        )
    connection = get_db()
    with connection.cursor() as cursor:
        _patient_or_404(cursor, hospital_uuid, patient_uuid)
        if resolution == "raw":
            cursor.execute(
                """SELECT captured_at, observed_at, received_at, heart_rate_bpm, spo2_percent,
                          heart_rate_source, spo2_source, temperature_c,
                          temperature_source, blood_pressure_source, contact_detected,
                          signal_quality, sensor_status,
                          ambient_temperature_c, ambient_humidity_percent,
                          systolic_bp, diastolic_bp, battery_percent, blood_loss_ml
                   FROM vital_readings
                   WHERE hospital_id = %s AND patient_id = %s
                     AND observed_at >= %s AND observed_at <= %s
                   ORDER BY observed_at ASC, id ASC LIMIT %s""",
                (hospital_uuid, patient_uuid, start, end, limit),
            )
        else:
            bucket = (
                "date_trunc('hour', observed_at) + floor(extract(minute FROM observed_at) / 5) * interval '5 minutes'"
                if resolution == "5m"
                else "date_trunc('hour', observed_at)"
            )
            cursor.execute(
                f"""SELECT {bucket} AS captured_at,
                           avg(heart_rate_bpm) AS heart_rate_bpm,
                           avg(spo2_percent) AS spo2_percent,
                           avg(temperature_c) AS temperature_c,
                           avg(ambient_temperature_c) AS ambient_temperature_c,
                           avg(ambient_humidity_percent) AS ambient_humidity_percent,
                           avg(systolic_bp) AS systolic_bp,
                           avg(diastolic_bp) AS diastolic_bp,
                           avg(battery_percent) AS battery_percent,
                           max(blood_loss_ml) AS blood_loss_ml,
                           count(*) AS sample_count
                    FROM vital_readings
                    WHERE hospital_id = %s AND patient_id = %s
                      AND observed_at >= %s AND observed_at <= %s
                    GROUP BY {bucket}
                    ORDER BY captured_at ASC LIMIT %s""",
                (hospital_uuid, patient_uuid, start, end, limit),
            )
        readings = cursor.fetchall()
    return jsonify(
        {
            "patient_id": str(patient_uuid),
            "from": _wire(start),
            "to": _wire(end),
            "resolution": resolution,
            "items": _wire([public_vital(reading) for reading in readings]),
            "limited": len(readings) == limit,
        }
    )


@clinician_bp.get("/hospitals/<hospital_id>/alerts")
@require_hospital_role("clinician")
def alerts(hospital_id: str):
    hospital_uuid = _identifier(hospital_id, "hospital_id")
    requested_status = request.args.get("status", "active")
    if requested_status == "active":
        statuses = _ACTIVE_ALERT_STATUSES
    elif requested_status == "all":
        statuses = _ALERT_STATUSES
    elif requested_status in _ALERT_STATUSES:
        statuses = (requested_status,)
    else:
        abort(400, description="Invalid alert status filter")
    severity = request.args.get("severity")
    if severity is not None and severity not in _SEVERITIES:
        abort(400, description="severity must be info, warning, or critical")
    patient_id = request.args.get("patient_id")
    patient_uuid = _identifier(patient_id, "patient_id") if patient_id else None
    limit = _limit(100, 250)
    if _demo_enabled():
        from .demo_store import demo_store

        return _demo_result(
            lambda: demo_store.alert_list(
                status=requested_status, severity=severity, patient_id=str(patient_uuid) if patient_uuid else None, limit=limit
            )
        )
    connection = get_db()
    with connection.cursor() as cursor:
        cursor.execute(
            """SELECT a.id, a.hospital_id, a.patient_id, a.severity, a.status,
                      a.alert_type, a.message, a.triggered_at, a.last_seen_at,
                      a.occurrence_count, a.rule_version, a.updated_at,
                      a.acknowledged_at, a.escalated_at, a.resolved_at,
                      p.full_name, p.medical_record_number
               FROM alerts a
               JOIN patients p ON p.id = a.patient_id AND p.hospital_id = a.hospital_id
               WHERE a.hospital_id = %s
                 AND a.status = ANY(%s::alert_status[])
                 AND (%s::alert_severity IS NULL OR a.severity = %s::alert_severity)
                 AND (%s::uuid IS NULL OR a.patient_id = %s::uuid)
               ORDER BY CASE a.severity WHEN 'critical' THEN 3 WHEN 'warning' THEN 2 ELSE 1 END DESC,
                        a.updated_at DESC, a.id DESC
               LIMIT %s""",
            (hospital_uuid, list(statuses), severity, severity, patient_uuid, patient_uuid, limit),
        )
        items = cursor.fetchall()
    return jsonify({"items": _wire(items), "status_filter": requested_status, "limited": len(items) == limit})


@clinician_bp.patch("/hospitals/<hospital_id>/alerts/<alert_id>")
@require_hospital_role("clinician")
def update_alert(hospital_id: str, alert_id: str):
    hospital_uuid = _identifier(hospital_id, "hospital_id")
    alert_uuid = _identifier(alert_id, "alert_id")
    payload = _json_object()
    action = payload.get("action")
    if action not in {"acknowledge", "resolve", "escalate"}:
        abort(400, description="action must be acknowledge, resolve, or escalate")
    note = _required_note(payload, required=action in {"resolve", "escalate"})
    if _demo_enabled():
        from .demo_store import demo_store

        return _demo_result(
            lambda: demo_store.update_alert(str(alert_uuid), action=action, note=note, actor_id=str(g.actor["id"]))
        )
    connection = get_db()
    request_id = uuid4()
    outbox_ids: list = []
    changed = False
    with connection.cursor() as cursor:
        alert = _alert_by_id_for_update(cursor, hospital_uuid, alert_uuid)
        previous_status = alert["status"]
        if action == "acknowledge":
            if alert["status"] == "open":
                cursor.execute(
                    """UPDATE alerts
                       SET status = 'acknowledged', acknowledged_by = %s, acknowledged_at = now()
                       WHERE id = %s
                       RETURNING id, hospital_id, patient_id, severity, status, alert_type, message,
                                 triggered_at, last_seen_at, occurrence_count, rule_version, updated_at,
                                 acknowledged_at, escalated_at, resolved_at""",
                    (g.actor["id"], alert_uuid),
                )
                alert = cursor.fetchone()
                changed = True
        elif action == "resolve":
            if alert["status"] != "resolved":
                cursor.execute(
                    """UPDATE alerts
                       SET status = 'resolved', resolved_by = %s, resolved_at = now(), resolution_note = %s
                       WHERE id = %s
                       RETURNING id, hospital_id, patient_id, severity, status, alert_type, message,
                                 triggered_at, last_seen_at, occurrence_count, rule_version, updated_at,
                                 acknowledged_at, escalated_at, resolved_at""",
                    (g.actor["id"], note, alert_uuid),
                )
                alert = cursor.fetchone()
                changed = True
        elif action == "escalate":
            if alert["status"] != "resolved" and alert["status"] != "escalated":
                cursor.execute(
                    """UPDATE alerts
                       SET status = 'escalated', escalated_by = %s, escalated_at = now(), escalation_note = %s
                       WHERE id = %s
                       RETURNING id, hospital_id, patient_id, severity, status, alert_type, message,
                                 triggered_at, last_seen_at, occurrence_count, rule_version, updated_at,
                                 acknowledged_at, escalated_at, resolved_at""",
                    (g.actor["id"], note, alert_uuid),
                )
                alert = cursor.fetchone()
                changed = True
        if changed:
            _audit(
                cursor,
                hospital_id=hospital_uuid,
                action=f"alert.{action}d" if action != "acknowledge" else "alert.acknowledged",
                entity_type="alert",
                entity_id=alert_uuid,
                request_id=request_id,
                metadata={
                    "patient_id": str(alert["patient_id"]),
                    "previous_status": previous_status,
                    "new_status": alert["status"],
                },
            )
            outbox_ids.append(
                enqueue_projection(
                    cursor,
                    topic="live_alert",
                    payload=_live_alert_payload(alert),
                    idempotency_key=f"live-alert:{alert['id']}:{alert['updated_at'].isoformat()}",
                )
            )
    connection.commit()
    delivery = deliver_outbox_ids(outbox_ids)
    return jsonify(
        {
            "alert": _row(alert),
            "changed": changed,
            "realtime": "synced" if delivery["pending"] == 0 else "pending",
        }
    )


@clinician_bp.get("/hospitals/<hospital_id>/patients/<patient_id>/clinical-notes")
@require_hospital_role("clinician")
def clinical_notes(hospital_id: str, patient_id: str):
    hospital_uuid = _identifier(hospital_id, "hospital_id")
    patient_uuid = _identifier(patient_id, "patient_id")
    limit = _limit(100, 250)
    if _demo_enabled():
        from .demo_store import demo_store

        return _demo_result(lambda: demo_store.list_notes(str(patient_uuid)))
    connection = get_db()
    with connection.cursor() as cursor:
        _patient_or_404(cursor, hospital_uuid, patient_uuid)
        cursor.execute(
            """SELECT n.id, n.note, n.created_at, n.updated_at, u.id AS author_user_id,
                      u.display_name AS author_display_name
               FROM clinical_notes n
               JOIN app_users u ON u.id = n.author_user_id
               WHERE n.hospital_id = %s AND n.patient_id = %s
               ORDER BY n.created_at DESC, n.id DESC LIMIT %s""",
            (hospital_uuid, patient_uuid, limit),
        )
        items = cursor.fetchall()
    return jsonify({"items": _wire(items), "limited": len(items) == limit})


@clinician_bp.post("/hospitals/<hospital_id>/patients/<patient_id>/clinical-notes")
@require_hospital_role("clinician")
def create_clinical_note(hospital_id: str, patient_id: str):
    hospital_uuid = _identifier(hospital_id, "hospital_id")
    patient_uuid = _identifier(patient_id, "patient_id")
    note = _required_note(_json_object(), required=True)
    if _demo_enabled():
        from .demo_store import demo_store

        return _demo_result(
            lambda: demo_store.add_note(str(patient_uuid), note, author_user_id=str(g.actor["id"])), status_code=201
        )
    connection = get_db()
    request_id = uuid4()
    with connection.cursor() as cursor:
        _patient_or_404(cursor, hospital_uuid, patient_uuid)
        cursor.execute(
            """INSERT INTO clinical_notes (hospital_id, patient_id, author_user_id, note)
               VALUES (%s, %s, %s, %s)
               RETURNING id, hospital_id, patient_id, author_user_id, note, created_at, updated_at""",
            (hospital_uuid, patient_uuid, g.actor["id"], note),
        )
        created = cursor.fetchone()
        _audit(
            cursor,
            hospital_id=hospital_uuid,
            action="clinical_note.created",
            entity_type="clinical_note",
            entity_id=created["id"],
            request_id=request_id,
            metadata={"patient_id": str(patient_uuid)},
        )
    connection.commit()
    return jsonify({"note": _row(created)}), 201


@clinician_bp.route("/hospitals/<hospital_id>/patients/<patient_id>/care-messages", methods=["GET", "POST"])
@require_hospital_role("clinician")
def care_messages(hospital_id: str, patient_id: str):
    hospital_uuid = _identifier(hospital_id, "hospital_id")
    patient_uuid = _identifier(patient_id, "patient_id")
    if _demo_enabled():
        abort(501, description="Care messaging is not included in the isolated demo store")
    connection = get_db()
    if request.method == "GET":
        with connection.cursor() as cursor:
            _patient_or_404(cursor, hospital_uuid, patient_uuid)
            cursor.execute(
                """SELECT m.id, m.sender_role, m.body, m.status, m.in_reply_to, m.created_at, m.read_at,
                          CASE WHEN m.sender_role = 'clinician' THEN u.display_name ELSE p.full_name END AS sender_name
                     FROM care_messages m
                     JOIN app_users u ON u.id = m.sender_user_id
                     JOIN patients p ON p.id = m.patient_id
                    WHERE m.hospital_id = %s AND m.patient_id = %s
                    ORDER BY m.created_at ASC, m.id ASC LIMIT 100""",
                (hospital_uuid, patient_uuid),
            )
            items = cursor.fetchall()
            cursor.execute(
                """UPDATE care_messages SET read_at = now()
                     WHERE hospital_id = %s AND patient_id = %s
                       AND sender_role = 'patient' AND read_at IS NULL""",
                (hospital_uuid, patient_uuid),
            )
        connection.commit()
        return jsonify({"items": _wire(items)})

    payload = care_message_input(_json_object())
    with connection.cursor() as cursor:
        _patient_or_404(cursor, hospital_uuid, patient_uuid)
        if payload["in_reply_to"]:
            cursor.execute(
                "SELECT id FROM care_messages WHERE id = %s AND patient_id = %s AND hospital_id = %s",
                (payload["in_reply_to"], patient_uuid, hospital_uuid),
            )
            if not cursor.fetchone():
                abort(400, description="in_reply_to does not belong to this patient conversation")
        cursor.execute(
            """INSERT INTO care_messages
                   (hospital_id, patient_id, sender_user_id, sender_role, body, in_reply_to, status)
                 VALUES (%s, %s, %s, 'clinician', %s, %s, 'responded')
                 RETURNING id, sender_role, body, status, in_reply_to, created_at, read_at""",
            (hospital_uuid, patient_uuid, g.actor["id"], payload["body"], payload["in_reply_to"]),
        )
        saved = cursor.fetchone()
        if payload["in_reply_to"]:
            cursor.execute(
                """UPDATE care_messages SET status = 'responded'
                     WHERE id = %s AND patient_id = %s AND sender_role = 'patient'""",
                (payload["in_reply_to"], patient_uuid),
            )
        _audit(
            cursor, hospital_id=hospital_uuid, action="clinician.care_message_sent",
            entity_type="care_message", entity_id=saved["id"], request_id=uuid4(),
            metadata={"patient_id": str(patient_uuid)},
        )
    connection.commit()
    return jsonify({"message": _row(saved)}), 201


@clinician_bp.route("/hospitals/<hospital_id>/patients/<patient_id>/clinical-profile", methods=["GET", "PUT"])
@require_hospital_role("clinician")
def patient_clinical_profile(hospital_id: str, patient_id: str):
    hospital_uuid = _identifier(hospital_id, "hospital_id")
    patient_uuid = _identifier(patient_id, "patient_id")
    if _demo_enabled():
        abort(501, description="Clinical profiles are not included in the isolated demo store")
    connection = get_db()
    if request.method == "GET":
        with connection.cursor() as cursor:
            _patient_or_404(cursor, hospital_uuid, patient_uuid)
            cursor.execute(
                """SELECT pregnancy_stage, patient_reported_history, clinician_confirmed_history,
                          current_medications, activity_clearance, last_patient_update_at, reviewed_at
                     FROM patient_clinical_profiles WHERE patient_id = %s""",
                (patient_uuid,),
            )
            profile = cursor.fetchone()
        return jsonify({"profile": _row(profile) or {
            "pregnancy_stage": "not_recorded", "patient_reported_history": {},
            "clinician_confirmed_history": {}, "current_medications": [],
            "activity_clearance": "not_recorded",
        }})

    payload = _json_object()
    profile = clinical_profile_input(payload)
    clearance = payload.get("activity_clearance", "not_recorded")
    if clearance not in {"not_recorded", "cleared_by_clinician", "restricted_by_clinician"}:
        abort(400, description="activity_clearance is invalid")
    with connection.cursor() as cursor:
        _patient_or_404(cursor, hospital_uuid, patient_uuid)
        cursor.execute(
            """INSERT INTO patient_clinical_profiles
                   (patient_id, hospital_id, pregnancy_stage, clinician_confirmed_history,
                    current_medications, activity_clearance, reviewed_by, reviewed_at)
                 VALUES (%s, %s, %s, %s::jsonb, %s::jsonb, %s, %s, now())
                 ON CONFLICT (patient_id) DO UPDATE SET
                   pregnancy_stage = EXCLUDED.pregnancy_stage,
                   clinician_confirmed_history = EXCLUDED.clinician_confirmed_history,
                   current_medications = EXCLUDED.current_medications,
                   activity_clearance = EXCLUDED.activity_clearance,
                   reviewed_by = EXCLUDED.reviewed_by, reviewed_at = now(), updated_at = now()
                 RETURNING pregnancy_stage, patient_reported_history, clinician_confirmed_history,
                           current_medications, activity_clearance, last_patient_update_at, reviewed_at""",
            (patient_uuid, hospital_uuid, profile["pregnancy_stage"], json.dumps(profile["history"]),
             json.dumps(profile["current_medications"]), clearance, g.actor["id"]),
        )
        saved = cursor.fetchone()
        _audit(
            cursor, hospital_id=hospital_uuid, action="clinician.clinical_profile_reviewed",
            entity_type="patient_clinical_profile", entity_id=patient_uuid, request_id=uuid4(),
            metadata={"activity_clearance": clearance},
        )
    connection.commit()
    return jsonify({"profile": _row(saved)})


@clinician_bp.route("/hospitals/<hospital_id>/patients/<patient_id>/guidance", methods=["GET", "POST"])
@require_hospital_role("clinician")
def patient_guidance(hospital_id: str, patient_id: str):
    hospital_uuid = _identifier(hospital_id, "hospital_id")
    patient_uuid = _identifier(patient_id, "patient_id")
    if _demo_enabled():
        abort(501, description="Clinician guidance is not included in the isolated demo store")
    connection = get_db()
    if request.method == "GET":
        with connection.cursor() as cursor:
            _patient_or_404(cursor, hospital_uuid, patient_uuid)
            cursor.execute(
                """SELECT id, category, title, body, status, created_at, updated_at
                     FROM patient_guidance WHERE hospital_id = %s AND patient_id = %s
                     ORDER BY created_at DESC LIMIT 50""",
                (hospital_uuid, patient_uuid),
            )
            items = cursor.fetchall()
        return jsonify({"items": _wire(items)})

    guidance = clinician_guidance_input(_json_object())
    with connection.cursor() as cursor:
        _patient_or_404(cursor, hospital_uuid, patient_uuid)
        cursor.execute(
            """INSERT INTO patient_guidance
                   (hospital_id, patient_id, category, title, body, created_by)
                 VALUES (%s, %s, %s, %s, %s, %s)
                 RETURNING id, category, title, body, status, created_at, updated_at""",
            (hospital_uuid, patient_uuid, guidance["category"], guidance["title"], guidance["body"], g.actor["id"]),
        )
        saved = cursor.fetchone()
        _audit(
            cursor, hospital_id=hospital_uuid, action="clinician.guidance_created",
            entity_type="patient_guidance", entity_id=saved["id"], request_id=uuid4(),
            metadata={"patient_id": str(patient_uuid), "category": guidance["category"]},
        )
    connection.commit()
    return jsonify({"guidance": _row(saved)}), 201


@clinician_bp.route("/hospitals/<hospital_id>/patients/<patient_id>/wearable-validation", methods=["GET", "POST"])
@require_hospital_role("clinician")
def wearable_validation(hospital_id: str, patient_id: str):
    hospital_uuid = _identifier(hospital_id, "hospital_id")
    patient_uuid = _identifier(patient_id, "patient_id")
    if _demo_enabled():
        abort(501, description="Validation records are not included in the isolated demo store")
    connection = get_db()
    if request.method == "GET":
        with connection.cursor() as cursor:
            _patient_or_404(cursor, hospital_uuid, patient_uuid)
            cursor.execute(
                """SELECT id, metric, wearable_value, reference_value, reference_device_label,
                          observation_time, absolute_error, percent_error, note, created_at
                     FROM wearable_validation_observations
                    WHERE hospital_id = %s AND patient_id = %s
                    ORDER BY observation_time DESC, id DESC LIMIT 100""",
                (hospital_uuid, patient_uuid),
            )
            items = cursor.fetchall()
        return jsonify({"items": _wire(items), "notice": "These paired observations do not by themselves establish clinical validation."})

    observation = validation_observation_input(_json_object())
    absolute_error = abs(observation["wearable_value"] - observation["reference_value"])
    percent_error = (
        (absolute_error / abs(observation["reference_value"])) * 100
        if observation["reference_value"] != 0 else None
    )
    with connection.cursor() as cursor:
        _patient_or_404(cursor, hospital_uuid, patient_uuid)
        cursor.execute(
            """INSERT INTO wearable_validation_observations
                   (hospital_id, patient_id, recorded_by, metric, wearable_value, reference_value,
                    reference_device_label, observation_time, absolute_error, percent_error, note)
                 VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                 RETURNING id, metric, wearable_value, reference_value, reference_device_label,
                           observation_time, absolute_error, percent_error, note, created_at""",
            (hospital_uuid, patient_uuid, g.actor["id"], observation["metric"],
             observation["wearable_value"], observation["reference_value"],
             observation["reference_device_label"], observation["observation_time"], absolute_error,
             percent_error, observation["note"]),
        )
        saved = cursor.fetchone()
        _audit(
            cursor, hospital_id=hospital_uuid, action="clinician.wearable_validation_recorded",
            entity_type="wearable_validation_observation", entity_id=saved["id"], request_id=uuid4(),
            metadata={"patient_id": str(patient_uuid), "metric": observation["metric"]},
        )
    connection.commit()
    return jsonify({"observation": _row(saved), "notice": "Recorded as a prototype comparison, not a clinical validation claim."}), 201


@clinician_bp.patch("/hospitals/<hospital_id>/patients/<patient_id>/lab-results/<result_id>")
@require_hospital_role("clinician")
def review_lab_result(hospital_id: str, patient_id: str, result_id: str):
    """Record a clinician review without converting a lab value into an app diagnosis."""
    hospital_uuid = _identifier(hospital_id, "hospital_id")
    patient_uuid = _identifier(patient_id, "patient_id")
    result_uuid = _identifier(result_id, "result_id")
    if _demo_enabled():
        abort(501, description="Lab review is not included in the isolated demo store")
    payload = _json_object()
    reference_status = payload.get("reference_status")
    if reference_status not in {"not_interpreted", "needs_clinician_review"}:
        abort(400, description="reference_status is invalid")
    note = _required_note(payload, required=False)
    connection = get_db()
    with connection.cursor() as cursor:
        _patient_or_404(cursor, hospital_uuid, patient_uuid)
        cursor.execute(
            """UPDATE patient_lab_results SET review_status = 'reviewed',
                       reference_status = %s, review_note = %s,
                       reviewed_by = %s, reviewed_at = now()
                 WHERE id = %s AND hospital_id = %s AND patient_id = %s
                 RETURNING id, category, test_type, result_values, result_units, reported_on,
                           trimester, review_status, reference_status, review_note, submitted_at, reviewed_at""",
            (reference_status, note, g.actor["id"], result_uuid, hospital_uuid, patient_uuid),
        )
        saved = cursor.fetchone()
        if not saved:
            abort(404, description="Lab result was not found for this patient")
        _audit(
            cursor, hospital_id=hospital_uuid, action="clinician.lab_result_reviewed",
            entity_type="patient_lab_result", entity_id=saved["id"], request_id=uuid4(),
            metadata={"patient_id": str(patient_uuid), "reference_status": reference_status},
        )
    connection.commit()
    return jsonify({"result": _row(saved)})
