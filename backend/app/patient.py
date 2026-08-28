"""Patient-owned companion APIs. These never accept a patient ID from the client."""

from __future__ import annotations

from uuid import uuid4

from flask import Blueprint, abort, g, jsonify, request

from .auth import require_firebase_user
from .db import get_db

patient_bp = Blueprint("patient", __name__)
_CONSENT_TYPES = {"monitoring", "care_team_sharing", "emergency_contact", "location"}
_DANGER_SIGNS = [
    {"id": "heavy_bleeding", "title": "Heavy bleeding", "action": "Get emergency care now if you soak a pad in an hour or pass large clots."},
    {"id": "breathing", "title": "Trouble breathing or chest pain", "action": "Call emergency services or go to the nearest emergency department now."},
    {"id": "headache", "title": "Severe headache or vision change", "action": "Seek urgent medical assessment today."},
    {"id": "fever", "title": "Fever or feeling very unwell", "action": "Contact your care team urgently."},
    {"id": "mental_health", "title": "Thoughts of harming yourself or your baby", "action": "Get emergency help now. Do not stay alone."},
]


def _row(row):
    return dict(row) if row else None


def _patient_for_actor(cursor):
    cursor.execute(
        """SELECT p.*, h.name AS hospital_name FROM patients p JOIN hospitals h ON h.id = p.hospital_id
           WHERE p.user_id = %s AND p.is_active = true""",
        (g.actor["id"],),
    )
    patient = cursor.fetchone()
    if not patient:
        abort(403, description="This account is not linked to an active patient profile")
    return patient


@patient_bp.get("/patient/home")
@require_firebase_user
def home():
    connection = get_db()
    with connection.cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute("""SELECT captured_at, heart_rate_bpm, spo2_percent, temperature_c, systolic_bp, diastolic_bp,
                                 battery_percent FROM vital_readings WHERE patient_id = %s ORDER BY captured_at DESC LIMIT 1""", (patient["id"],))
        latest_vital = cursor.fetchone()
        cursor.execute("""SELECT id, severity, status, alert_type, message, triggered_at, last_seen_at
                          FROM alerts WHERE patient_id = %s AND status IN ('open', 'acknowledged', 'escalated')
                          ORDER BY triggered_at DESC LIMIT 10""", (patient["id"],))
        alerts = cursor.fetchall()
        cursor.execute("""SELECT id, title, detail, due_at, status FROM care_plan_tasks
                          WHERE patient_id = %s AND status = 'open' ORDER BY due_at NULLS LAST, created_at DESC LIMIT 6""", (patient["id"],))
        tasks = cursor.fetchall()
        cursor.execute("""SELECT serial_number, firmware_version, last_seen_at, status FROM devices
                          WHERE assigned_patient_id = %s AND status = 'assigned' ORDER BY last_seen_at DESC NULLS LAST LIMIT 1""", (patient["id"],))
        device = cursor.fetchone()
    return jsonify({"patient": _row(patient), "latest_vital": _row(latest_vital), "active_alerts": [_row(x) for x in alerts], "care_plan": [_row(x) for x in tasks], "device": _row(device), "danger_signs": _DANGER_SIGNS})


@patient_bp.post("/patient/sos")
@require_firebase_user
def sos():
    body = request.get_json(silent=True) or {}
    note = str(body.get("note", "")).strip()[:500]
    connection = get_db()
    with connection.cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute("""INSERT INTO alerts (hospital_id, patient_id, severity, status, alert_type, message, triggered_at,
                          last_seen_at, occurrence_count, rule_id, rule_version, dedupe_key, evidence)
                          VALUES (%s, %s, 'critical', 'open', 'sos_help_request', %s, now(), now(), 1, 'patient_sos', '2026-1', %s, %s)
                          ON CONFLICT (hospital_id, patient_id, dedupe_key) WHERE dedupe_key IS NOT NULL AND status IN ('open','acknowledged','escalated')
                          DO UPDATE SET last_seen_at = now(), occurrence_count = alerts.occurrence_count + 1, updated_at = now()
                          RETURNING id, status, triggered_at""",
                       (patient["hospital_id"], patient["id"], "Patient requested urgent help." + (f" Note: {note}" if note else ""), f"patient-sos:{patient['id']}", '{"source":"patient_app"}'))
        alert = cursor.fetchone()
        cursor.execute("""INSERT INTO audit_log (actor_user_id, hospital_id, action, entity_type, entity_id, request_id, metadata, ip_address)
                          VALUES (%s, %s, 'patient.sos_requested', 'alert', %s, %s, %s, %s)""",
                       (g.actor["id"], patient["hospital_id"], str(alert["id"]), uuid4(), '{"source":"patient_app"}', request.remote_addr))
    connection.commit()
    return jsonify({"alert": _row(alert), "message": "Your care team has been notified. If this is life-threatening, call local emergency services now."}), 201


@patient_bp.post("/patient/symptoms")
@require_firebase_user
def symptoms():
    body = request.get_json(silent=True) or {}
    symptom_ids = body.get("symptoms", [])
    if not isinstance(symptom_ids, list) or not all(isinstance(x, str) and len(x) <= 64 for x in symptom_ids):
        abort(400, description="symptoms must be a list of valid symptom IDs")
    notes = str(body.get("notes", "")).strip()[:1000]
    urgent = bool(set(symptom_ids) & {"heavy_bleeding", "breathing", "headache", "mental_health"})
    connection = get_db()
    with connection.cursor() as cursor:
        patient = _patient_for_actor(cursor)
        import json
        cursor.execute("""INSERT INTO symptom_reports (hospital_id, patient_id, symptoms, notes, severity)
                          VALUES (%s, %s, %s::jsonb, %s, %s) RETURNING id, severity, submitted_at""",
                       (patient["hospital_id"], patient["id"], json.dumps(symptom_ids), notes or None, "urgent" if urgent else "routine"))
        report = cursor.fetchone()
    connection.commit()
    return jsonify({"report": _row(report), "urgent": urgent}), 201


@patient_bp.get("/patient/consents")
@require_firebase_user
def consents():
    with get_db().cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute("""SELECT DISTINCT ON (consent_type) consent_type, granted, policy_version, recorded_at, withdrawn_at
                          FROM patient_consents WHERE patient_id = %s ORDER BY consent_type, recorded_at DESC""", (patient["id"],))
        values = cursor.fetchall()
    return jsonify({"items": [_row(x) for x in values]})


@patient_bp.put("/patient/consents/<consent_type>")
@require_firebase_user
def set_consent(consent_type):
    if consent_type not in _CONSENT_TYPES:
        abort(404)
    body = request.get_json(silent=True) or {}
    if not isinstance(body.get("granted"), bool):
        abort(400, description="granted must be a boolean")
    with get_db().cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute("""INSERT INTO patient_consents (hospital_id, patient_id, consent_type, granted, policy_version, withdrawn_at)
                          VALUES (%s, %s, %s, %s, '2026-1', CASE WHEN %s THEN NULL ELSE now() END)
                          ON CONFLICT (patient_id, consent_type, policy_version) DO UPDATE SET granted = EXCLUDED.granted,
                            recorded_at = now(), withdrawn_at = EXCLUDED.withdrawn_at
                          RETURNING consent_type, granted, policy_version, recorded_at, withdrawn_at""",
                       (patient["hospital_id"], patient["id"], consent_type, body["granted"], body["granted"]))
        value = cursor.fetchone()
    get_db().commit()
    return jsonify({"consent": _row(value)})


@patient_bp.patch("/patient/care-plan/<task_id>")
@require_firebase_user
def complete_task(task_id):
    body = request.get_json(silent=True) or {}
    status = body.get("status")
    if status not in {"completed", "skipped"}:
        abort(400, description="status must be completed or skipped")
    with get_db().cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute("""UPDATE care_plan_tasks SET status = %s, completed_at = now() WHERE id = %s AND patient_id = %s
                          RETURNING id, title, status, completed_at""", (status, task_id, patient["id"]))
        task = cursor.fetchone()
    if not task:
        abort(404)
    get_db().commit()
    return jsonify({"task": _row(task)})
