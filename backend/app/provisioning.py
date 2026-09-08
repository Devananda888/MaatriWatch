"""Hospital-controlled patient account invitation and activation APIs."""

from __future__ import annotations

from datetime import date
from uuid import UUID, uuid4

from firebase_admin import auth as firebase_auth
from flask import Blueprint, abort, current_app, g, jsonify, request
from psycopg.types.json import Jsonb

from .auth import require_hospital_role
from .db import get_db

provisioning_bp = Blueprint("provisioning", __name__)


def _uuid(value: str, field: str) -> UUID:
    try:
        return UUID(value)
    except (TypeError, ValueError):
        abort(400, description=f"{field} must be a UUID")


def _body() -> dict:
    value = request.get_json(silent=True)
    if not isinstance(value, dict):
        abort(400, description="A JSON object is required")
    return value


def _text(value: object, field: str, *, minimum: int = 1, maximum: int = 160) -> str:
    if not isinstance(value, str):
        abort(400, description=f"{field} is required")
    result = value.strip()
    if not minimum <= len(result) <= maximum:
        abort(400, description=f"{field} must be {minimum}-{maximum} characters")
    return result


def _email(value: object) -> str:
    result = _text(value, "email", maximum=254).lower()
    # This intentionally rejects malformed addresses without trying to be an
    # email parser. Firebase performs the final provider-level validation.
    if result.count("@") != 1 or result.startswith("@") or result.endswith("@"):
        abort(400, description="email must be a valid email address")
    return result


def _optional_date(value: object, field: str) -> date | None:
    if value in (None, ""):
        return None
    if not isinstance(value, str):
        abort(400, description=f"{field} must be an ISO date")
    try:
        return date.fromisoformat(value)
    except ValueError:
        abort(400, description=f"{field} must be an ISO date")


def _invitation_input(body: dict) -> dict:
    language = str(body.get("preferred_language", "en")).strip().lower()
    if not 2 <= len(language) <= 16:
        abort(400, description="preferred_language must be a language code")
    return {
        "medical_record_number": _text(body.get("medical_record_number"), "medical_record_number", maximum=96),
        "full_name": _text(body.get("full_name"), "full_name", maximum=200),
        "email": _email(body.get("email")),
        "preferred_language": language,
        "date_of_birth": _optional_date(body.get("date_of_birth"), "date_of_birth"),
        "delivery_date": _optional_date(body.get("delivery_date"), "delivery_date"),
        "emergency_contact_name": _optional_text(body.get("emergency_contact_name"), "emergency_contact_name"),
        "emergency_contact_phone": _optional_text(body.get("emergency_contact_phone"), "emergency_contact_phone", maximum=32),
    }


def _optional_text(value: object, field: str, *, maximum: int = 160) -> str | None:
    if value in (None, ""):
        return None
    return _text(value, field, maximum=maximum)


def _require_firebase_auth() -> None:
    if not current_app.config.get("FIREBASE_AUTH_READY"):
        abort(503, description="Patient account activation is temporarily unavailable")


def _firebase_user(email: str, display_name: str):
    """Get or create a disabled-by-default? No: Firebase must permit reset.

    PostgreSQL RBAC remains the access gate, so a Firebase account without a
    patient linkage cannot access patient APIs.  This preserves password-reset
    and email-verification flow without an application-side shared password.
    """
    _require_firebase_auth()
    try:
        return firebase_auth.get_user_by_email(email), False
    except firebase_auth.UserNotFoundError:
        try:
            return firebase_auth.create_user(
                email=email, email_verified=False, disabled=False, display_name=display_name
            ), True
        except Exception:
            abort(503, description="Patient account could not be created. Try again later.")
    except Exception:
        abort(503, description="Patient account lookup is temporarily unavailable")


def _activation_link(email: str) -> str:
    _require_firebase_auth()
    action_url = current_app.config.get("FIREBASE_AUTH_ACTION_URL")
    try:
        settings = firebase_auth.ActionCodeSettings(url=action_url, handle_code_in_app=False)
        return firebase_auth.generate_password_reset_link(email, action_code_settings=settings)
    except Exception:
        abort(503, description="Activation link could not be generated. Reissue it when Firebase is available.")


def _audit(cursor, *, hospital_id, action: str, entity_id, metadata: dict) -> None:
    cursor.execute(
        """INSERT INTO audit_log (actor_user_id, hospital_id, action, entity_type, entity_id, request_id, metadata, ip_address)
           VALUES (%s, %s, %s, 'patient_invitation', %s, %s, %s, %s)""",
        (g.actor["id"], hospital_id, action, str(entity_id), uuid4(), Jsonb(metadata), request.remote_addr),
    )


def _wire(row) -> dict:
    return {
        "id": str(row["id"]),
        "patient_id": str(row["patient_id"]),
        "status": row["status"],
        "issued_at": row["issued_at"],
        "expires_at": row["expires_at"],
        "activation_link_issued_at": row["activation_link_issued_at"],
        "reissued_at": row["reissued_at"],
        "activated_at": row["activated_at"],
    }


def _issue_link_for_invitation(invitation_id: UUID, email: str, *, reissued: bool) -> tuple[str, dict]:
    # Generate before storing its timestamp. The action URL itself is not
    # persisted, logged, or placed into realtime projections.
    link = _activation_link(email)
    connection = get_db()
    with connection.cursor() as cursor:
        cursor.execute(
            """UPDATE patient_invitations
                  SET activation_link_issued_at = now(),
                      reissued_at = CASE WHEN %s THEN now() ELSE reissued_at END
                WHERE id = %s
                RETURNING activation_link_issued_at, reissued_at""",
            (reissued, invitation_id),
        )
        stamps = dict(cursor.fetchone())
    connection.commit()
    return link, stamps


@provisioning_bp.post("/hospitals/<hospital_id>/patient-invitations")
@require_hospital_role("clinician", "hospital_admin")
def create_patient_invitation(hospital_id: str):
    """Create a linked patient and return one activation link to authorised staff."""
    hospital = _uuid(hospital_id, "hospital_id")
    details = _invitation_input(_body())
    firebase_user, _created = _firebase_user(details["email"], details["full_name"])
    connection = get_db()
    with connection.cursor() as cursor:
        cursor.execute("SELECT id FROM patients WHERE hospital_id = %s AND medical_record_number = %s", (hospital, details["medical_record_number"]))
        if cursor.fetchone():
            abort(409, description="A patient with this medical record number already exists in this hospital")
        cursor.execute(
            """SELECT id, firebase_uid, is_active FROM app_users
                 WHERE firebase_uid = %s OR email = %s FOR UPDATE""",
            (firebase_user.uid, details["email"]),
        )
        existing_users = cursor.fetchall()
        if any(row["firebase_uid"] != firebase_user.uid for row in existing_users):
            abort(409, description="This email is already linked to a different application account")
        cursor.execute(
            """INSERT INTO app_users (firebase_uid, email, display_name)
               VALUES (%s, %s, %s)
               ON CONFLICT (firebase_uid) DO UPDATE SET email = EXCLUDED.email, display_name = EXCLUDED.display_name, updated_at = now()
               RETURNING id, is_active""",
            (firebase_user.uid, details["email"], details["full_name"]),
        )
        user = cursor.fetchone()
        if not user["is_active"]:
            abort(409, description="This account is inactive and cannot be linked to a new patient profile")
        cursor.execute("SELECT id FROM patients WHERE user_id = %s", (user["id"],))
        if cursor.fetchone():
            abort(409, description="This Firebase account is already linked to a patient profile")
        cursor.execute(
            """INSERT INTO patients (hospital_id, user_id, medical_record_number, full_name, date_of_birth,
                                      preferred_language, delivery_date, emergency_contact_name, emergency_contact_phone)
               VALUES (%(hospital)s, %(user_id)s, %(medical_record_number)s, %(full_name)s, %(date_of_birth)s,
                       %(preferred_language)s, %(delivery_date)s, %(emergency_contact_name)s, %(emergency_contact_phone)s)
               RETURNING id""",
            {"hospital": hospital, "user_id": user["id"], **details},
        )
        patient = cursor.fetchone()
        cursor.execute(
            """INSERT INTO hospital_memberships (hospital_id, user_id, role, is_active)
               VALUES (%s, %s, 'patient', true)
               ON CONFLICT (hospital_id, user_id, role) DO UPDATE SET is_active = true""",
            (hospital, user["id"]),
        )
        cursor.execute(
            """INSERT INTO patient_invitations (hospital_id, patient_id, user_id, issued_by)
               VALUES (%s, %s, %s, %s)
               RETURNING id, patient_id, status, issued_at, expires_at, activation_link_issued_at, reissued_at, activated_at""",
            (hospital, patient["id"], user["id"], g.actor["id"]),
        )
        invitation = cursor.fetchone()
        _audit(cursor, hospital_id=hospital, action="patient.invited", entity_id=invitation["id"], metadata={"patient_id": str(patient["id"])})
    connection.commit()
    activation_url, stamps = _issue_link_for_invitation(invitation["id"], details["email"], reissued=False)
    return jsonify({
        "patient_id": str(patient["id"]),
        "invitation": _wire({**dict(invitation), **stamps}),
        "activation_url": activation_url,
    }), 201


@provisioning_bp.post("/hospitals/<hospital_id>/patients/<patient_id>/activation-link")
@require_hospital_role("clinician", "hospital_admin")
def reissue_patient_activation(hospital_id: str, patient_id: str):
    """Return a newly generated one-time activation link; never return an old one."""
    hospital, patient = _uuid(hospital_id, "hospital_id"), _uuid(patient_id, "patient_id")
    connection = get_db()
    with connection.cursor() as cursor:
        cursor.execute(
            """SELECT p.id, p.user_id, u.email, u.is_active FROM patients p JOIN app_users u ON u.id = p.user_id
               WHERE p.id = %s AND p.hospital_id = %s AND p.is_active = true""",
            (patient, hospital),
        )
        linked = cursor.fetchone()
        if not linked or not linked["email"] or not linked["is_active"]:
            abort(404, description="An active patient account with an email address was not found")
        cursor.execute(
            """SELECT id, patient_id, status, issued_at, expires_at, activation_link_issued_at, reissued_at, activated_at
               FROM patient_invitations WHERE patient_id = %s AND status = 'issued'
               ORDER BY issued_at DESC LIMIT 1 FOR UPDATE""",
            (patient,),
        )
        invitation = cursor.fetchone()
        if not invitation:
            cursor.execute(
                """SELECT status FROM patient_invitations
                   WHERE patient_id = %s ORDER BY issued_at DESC LIMIT 1""",
                (patient,),
            )
            latest = cursor.fetchone()
            if latest and latest["status"] == "activated":
                abort(409, description="This patient account is already activated; use the approved account-recovery process")
            cursor.execute(
                """INSERT INTO patient_invitations (hospital_id, patient_id, user_id, issued_by)
                   VALUES (%s, %s, %s, %s)
                   RETURNING id, patient_id, status, issued_at, expires_at, activation_link_issued_at, reissued_at, activated_at""",
                (hospital, patient, linked["user_id"], g.actor["id"]),
            )
            invitation = cursor.fetchone()
        _audit(cursor, hospital_id=hospital, action="patient.activation_link_reissued", entity_id=invitation["id"], metadata={"patient_id": str(patient)})
    connection.commit()
    activation_url, stamps = _issue_link_for_invitation(invitation["id"], linked["email"], reissued=True)
    return jsonify({"invitation": _wire({**dict(invitation), **stamps}), "activation_url": activation_url})


@provisioning_bp.get("/hospitals/<hospital_id>/patient-invitations")
@require_hospital_role("clinician", "hospital_admin")
def list_patient_invitations(hospital_id: str):
    hospital = _uuid(hospital_id, "hospital_id")
    requested_status = request.args.get("status")
    if requested_status and requested_status not in {"issued", "activated", "revoked", "expired"}:
        abort(400, description="status is invalid")
    with get_db().cursor() as cursor:
        cursor.execute(
            """SELECT i.id, i.patient_id, i.status, i.issued_at, i.expires_at, i.activation_link_issued_at,
                      i.reissued_at, i.activated_at, p.full_name, p.medical_record_number
               FROM patient_invitations i JOIN patients p ON p.id = i.patient_id
               WHERE i.hospital_id = %s AND (%s::text IS NULL OR i.status = %s)
               ORDER BY i.issued_at DESC LIMIT 200""",
            (hospital, requested_status, requested_status),
        )
        items = []
        for row in cursor.fetchall():
            item = _wire(row)
            item.update({"full_name": row["full_name"], "medical_record_number": row["medical_record_number"]})
            items.append(item)
    return jsonify({"items": items})
