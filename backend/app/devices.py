"""Hospital device inventory and assignment lifecycle APIs."""

from __future__ import annotations

import secrets
from uuid import UUID

from argon2 import PasswordHasher
from flask import Blueprint, abort, g, jsonify, request

from .auth import require_hospital_role
from .db import get_db

devices_bp = Blueprint("devices", __name__)
_hasher = PasswordHasher()


def _uuid(value: str, field: str) -> UUID:
    try:
        return UUID(value)
    except ValueError:
        abort(400, description=f"{field} must be a UUID")


def _body() -> dict:
    value = request.get_json(silent=True)
    if not isinstance(value, dict):
        abort(400, description="A JSON object is required")
    return value


@devices_bp.get("/hospitals/<hospital_id>/devices")
@require_hospital_role("clinician", "hospital_admin")
def list_devices(hospital_id: str):
    hospital = _uuid(hospital_id, "hospital_id")
    with get_db().cursor() as cursor:
        cursor.execute(
            """SELECT d.id, d.serial_number, d.status, d.firmware_version, d.last_seen_at,
                      d.assigned_patient_id, p.full_name AS assigned_patient_name
                 FROM devices d LEFT JOIN patients p ON p.id = d.assigned_patient_id
                WHERE d.hospital_id = %s ORDER BY d.status, d.serial_number""",
            (hospital,),
        )
        items = [dict(row) for row in cursor.fetchall()]
    return jsonify({"items": items})


@devices_bp.post("/hospitals/<hospital_id>/devices")
@require_hospital_role("hospital_admin")
def create_device(hospital_id: str):
    hospital = _uuid(hospital_id, "hospital_id")
    serial = str(_body().get("serial_number", "")).strip()
    if not 3 <= len(serial) <= 128:
        abort(400, description="serial_number must be 3–128 characters")
    api_key = secrets.token_urlsafe(32)
    connection = get_db()
    with connection.cursor() as cursor:
        cursor.execute(
            """INSERT INTO devices (hospital_id, serial_number, api_key_hash, status)
               VALUES (%s, %s, %s, 'inventory')
               RETURNING id, serial_number, status""",
            (hospital, serial, _hasher.hash(api_key)),
        )
        device = dict(cursor.fetchone())
    connection.commit()
    # This is deliberately the sole response that includes the secret.
    return jsonify({"device": device, "device_key": api_key}), 201


@devices_bp.patch("/hospitals/<hospital_id>/devices/<device_id>/assignment")
@require_hospital_role("clinician", "hospital_admin")
def set_assignment(hospital_id: str, device_id: str):
    hospital, device = _uuid(hospital_id, "hospital_id"), _uuid(device_id, "device_id")
    patient_value = _body().get("patient_id")
    patient = _uuid(patient_value, "patient_id") if patient_value else None
    connection = get_db()
    with connection.cursor() as cursor:
        if patient:
            cursor.execute("SELECT id FROM patients WHERE id = %s AND hospital_id = %s AND is_active = true", (patient, hospital))
            if not cursor.fetchone():
                abort(404, description="Active patient was not found in this hospital")
        cursor.execute(
            """UPDATE devices SET assigned_patient_id = %s, status = %s, updated_at = now()
                 WHERE id = %s AND hospital_id = %s
                 RETURNING id, serial_number, status, assigned_patient_id""",
            (patient, "assigned" if patient else "inventory", device, hospital),
        )
        result = cursor.fetchone()
    if not result:
        abort(404, description="Device was not found in this hospital")
    connection.commit()
    return jsonify({"device": dict(result)})


@devices_bp.post("/hospitals/<hospital_id>/devices/<device_id>/rotate-key")
@require_hospital_role("hospital_admin")
def rotate_device_key(hospital_id: str, device_id: str):
    """Invalidate a returned/lost device credential before its next issue."""
    hospital, device = _uuid(hospital_id, "hospital_id"), _uuid(device_id, "device_id")
    api_key = secrets.token_urlsafe(32)
    connection = get_db()
    with connection.cursor() as cursor:
        cursor.execute(
            """UPDATE devices SET api_key_hash = %s, updated_at = now()
                 WHERE id = %s AND hospital_id = %s
                 RETURNING id, serial_number, status""",
            (_hasher.hash(api_key), device, hospital),
        )
        result = cursor.fetchone()
    if not result:
        abort(404, description="Device was not found in this hospital")
    connection.commit()
    return jsonify({"device": dict(result), "device_key": api_key})
