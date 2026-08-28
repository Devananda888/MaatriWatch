"""Seed repeatable MaatriWatch MVP demo data into an already-migrated Postgres DB.

This script is deliberately limited to demo-only data.  It does not create a
database, apply migrations, configure Firebase, or print ``DATABASE_URL``.
Run the four SQL migrations first, set ``DATABASE_URL``, then run:

    python scripts/seed_demo.py

The final output includes intentionally non-secret *demo* device credentials
for use with the device simulator.  Delete or rotate this data before using a
shared environment.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from argon2 import PasswordHasher
from dotenv import load_dotenv
from psycopg import connect
from psycopg.errors import OperationalError
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb


ROOT_DIR = Path(__file__).resolve().parents[1]
load_dotenv(ROOT_DIR / ".env")

DEMO_HOSPITAL_CODE = "MW-DEMO"
DEMO_HOSPITAL_NAME = "MaatriWatch Demo Community Hospital"
POLICY_VERSION = "baseline-2026-08-14"
DEMO_DEVICE_PREFIX = "MW-DEMO-"
_HASHER = PasswordHasher()


@dataclass(frozen=True)
class DemoPatient:
    index: int
    full_name: str
    language: str
    days_postpartum: int
    base_heart_rate: int
    base_spo2: float
    base_temperature: float
    base_systolic: int
    base_diastolic: int
    risk: str | None = None

    @property
    def mrn(self) -> str:
        return f"DEMO-{self.index:03d}"

    @property
    def serial_number(self) -> str:
        return f"{DEMO_DEVICE_PREFIX}{self.index:04d}"


DEMO_PATIENTS: tuple[DemoPatient, ...] = (
    DemoPatient(1, "Ananya Sharma", "hi", 12, 76, 98.0, 36.8, 112, 72),
    DemoPatient(2, "Meera Kulkarni", "mr", 19, 82, 97.0, 36.9, 116, 74),
    DemoPatient(3, "Lakshmi Nair", "ml", 8, 79, 98.0, 36.7, 110, 70),
    DemoPatient(4, "Kavya Reddy", "te", 25, 84, 97.0, 37.0, 118, 76),
    DemoPatient(5, "Pooja Yadav", "hi", 5, 74, 99.0, 36.6, 108, 68),
    DemoPatient(6, "Farah Khan", "ur", 16, 88, 97.0, 36.9, 138, 88, "hypertension"),
    DemoPatient(7, "Nandini Rao", "ta", 10, 80, 98.0, 36.8, 114, 72, "fall"),
)


def demo_device_key(index: int) -> str:
    """Return an intentionally predictable credential for an isolated demo DB."""

    return f"mw-demo-device-key-{index:02d}-for-demo-only"


def _require_database_url() -> str:
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise SystemExit(
            "DATABASE_URL is required. Apply 001_initial_schema.sql through "
            "004_patient_safety_workflows.sql first."
        )
    return database_url


def _require_migrated_schema(connection) -> None:
    """Fail clearly rather than partially seeding a pre-Phase-3 database."""

    required_tables = {
        "hospitals",
        "app_users",
        "hospital_memberships",
        "patients",
        "devices",
        "vital_readings",
        "alerts",
        "alert_observations",
        "screenings",
        "realtime_outbox",
    }
    required_columns = {
        "vital_readings": {
            "source_event_id",
            "source_sequence",
            "payload_fingerprint",
            "blood_loss_ml",
            "bleeding_reported",
            "motion",
        },
        "alerts": {
            "rule_id",
            "rule_version",
            "dedupe_key",
            "evidence",
            "last_seen_at",
            "occurrence_count",
            "escalated_at",
            "updated_at",
        },
    }

    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename = ANY(%s)",
            (list(required_tables),),
        )
        present_tables = {row["tablename"] for row in cursor.fetchall()}
        cursor.execute(
            """SELECT table_name, column_name
                 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = ANY(%s)""",
            (list(required_columns),),
        )
        present_columns: dict[str, set[str]] = {}
        for row in cursor.fetchall():
            present_columns.setdefault(row["table_name"], set()).add(row["column_name"])

    missing_tables = sorted(required_tables - present_tables)
    missing_columns = sorted(
        f"{table}.{column}"
        for table, columns in required_columns.items()
        for column in columns - present_columns.get(table, set())
    )
    if missing_tables or missing_columns:
        missing = ", ".join([*missing_tables, *missing_columns])
        raise SystemExit(
            "MaatriWatch migrations are not fully applied (missing: "
            f"{missing}). Apply 001_initial_schema.sql through 004_patient_safety_workflows.sql, then retry."
        )


def _upsert_user(cursor, *, firebase_uid: str, email: str, display_name: str, phone_e164: str | None = None):
    cursor.execute(
        """INSERT INTO app_users (firebase_uid, email, phone_e164, display_name)
           VALUES (%s, %s, %s, %s)
           ON CONFLICT (firebase_uid) DO UPDATE SET
               email = EXCLUDED.email,
               phone_e164 = EXCLUDED.phone_e164,
               display_name = EXCLUDED.display_name,
               is_active = true,
               updated_at = now()
           RETURNING id""",
        (firebase_uid, email, phone_e164, display_name),
    )
    return cursor.fetchone()["id"]


def _upsert_membership(cursor, *, hospital_id, user_id, role: str) -> None:
    cursor.execute(
        """INSERT INTO hospital_memberships (hospital_id, user_id, role, is_active)
           VALUES (%s, %s, %s, true)
           ON CONFLICT (hospital_id, user_id, role) DO UPDATE SET is_active = true""",
        (hospital_id, user_id, role),
    )


def _reading_for(patient: DemoPatient, sample: int, captured_at: datetime) -> dict[str, Any]:
    """Create a small, believable historical series, with two seeded risk cases."""

    heart_offsets = (-3, 1, 0, 3, -1, 2)
    bp_offsets = (-4, -1, 2, 0, 3, 1)
    heart_rate = patient.base_heart_rate + heart_offsets[sample]
    systolic = patient.base_systolic + bp_offsets[sample]
    diastolic = patient.base_diastolic + max(-2, bp_offsets[sample] // 2)
    motion: dict[str, Any] = {
        "fall_detected": False,
        "impact_g": 0.1,
        "orientation_change_degrees": 2,
        "post_impact_immobile_seconds": 0,
    }

    # The final seed point makes one patient visibly high-risk on first load.
    if patient.risk == "hypertension" and sample == 5:
        systolic, diastolic, heart_rate = 148, 96, 92
    elif patient.risk == "fall" and sample == 5:
        motion = {
            "fall_detected": True,
            "impact_g": 3.2,
            "orientation_change_degrees": 88,
            "post_impact_immobile_seconds": 42,
        }

    payload = {
        "event_id": f"demo-history:{patient.serial_number}:{sample}",
        "source_sequence": sample,
        "captured_at": captured_at.isoformat(),
        "heart_rate_bpm": heart_rate,
        "spo2_percent": round(patient.base_spo2 - (0.2 if sample % 3 == 0 else 0), 1),
        "temperature_c": round(patient.base_temperature + (0.1 if sample == 3 else 0), 1),
        "systolic_bp": systolic,
        "diastolic_bp": diastolic,
        "battery_percent": 92 - sample,
        "motion": motion,
        "bleeding_reported": False,
    }
    return payload


def _insert_reading(cursor, *, hospital_id, patient_id, device_id, payload: dict[str, Any]):
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    fingerprint = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    cursor.execute(
        """INSERT INTO vital_readings
           (hospital_id, patient_id, device_id, source_event_id, source_sequence,
            payload_fingerprint, captured_at, heart_rate_bpm, spo2_percent,
            temperature_c, systolic_bp, diastolic_bp, battery_percent, blood_loss_ml,
            bleeding_reported, motion, raw_payload)
           VALUES (%(hospital_id)s, %(patient_id)s, %(device_id)s, %(event_id)s,
                   %(source_sequence)s, %(payload_fingerprint)s, %(captured_at)s,
                   %(heart_rate_bpm)s, %(spo2_percent)s, %(temperature_c)s,
                   %(systolic_bp)s, %(diastolic_bp)s, %(battery_percent)s,
                   %(blood_loss_ml)s, %(bleeding_reported)s, %(motion)s, %(raw_payload)s)
           ON CONFLICT (device_id, source_event_id) WHERE source_event_id IS NOT NULL DO NOTHING
           RETURNING id, captured_at""",
        {
            "hospital_id": hospital_id,
            "patient_id": patient_id,
            "device_id": device_id,
            "event_id": payload["event_id"],
            "source_sequence": payload["source_sequence"],
            "payload_fingerprint": fingerprint,
            "captured_at": datetime.fromisoformat(payload["captured_at"]),
            "heart_rate_bpm": payload["heart_rate_bpm"],
            "spo2_percent": payload["spo2_percent"],
            "temperature_c": payload["temperature_c"],
            "systolic_bp": payload["systolic_bp"],
            "diastolic_bp": payload["diastolic_bp"],
            "battery_percent": payload["battery_percent"],
            "blood_loss_ml": payload.get("blood_loss_ml"),
            "bleeding_reported": payload["bleeding_reported"],
            "motion": Jsonb(payload["motion"]),
            "raw_payload": Jsonb(payload),
        },
    )
    row = cursor.fetchone()
    if row:
        return row
    cursor.execute(
        """SELECT id, captured_at FROM vital_readings
           WHERE device_id = %s AND source_event_id = %s""",
        (device_id, payload["event_id"]),
    )
    return cursor.fetchone()


def _upsert_alert(cursor, *, hospital_id, patient_id, reading_id, captured_at, kind: str):
    if kind == "hypertension":
        rule_id = "postpartum_hypertension_risk"
        severity = "warning"
        message = "Elevated blood pressure: assess for a postpartum hypertensive disorder."
        evidence: dict[str, Any] = {
            "policy_version": POLICY_VERSION,
            "demo_seed": True,
            "rule_evidence": {"systolic_bp": 148, "diastolic_bp": 96},
        }
    elif kind == "fall":
        rule_id = "fall_detected"
        severity = "critical"
        message = "Possible fall detected: contact the mother and assess urgently."
        evidence = {
            "policy_version": POLICY_VERSION,
            "demo_seed": True,
            "rule_evidence": {"source": "device_classifier", "motion": {"fall_detected": True}},
        }
    else:  # Defensive guard in case a future patient fixture is misconfigured.
        raise ValueError(f"Unsupported demo risk fixture: {kind}")

    cursor.execute(
        """INSERT INTO alerts
           (hospital_id, patient_id, vital_reading_id, severity, status, alert_type,
            message, triggered_at, rule_id, rule_version, dedupe_key, evidence,
            last_seen_at, occurrence_count)
           VALUES (%s, %s, %s, %s, 'open', %s, %s, %s, %s, %s, %s, %s, %s, 1)
           ON CONFLICT (hospital_id, patient_id, dedupe_key)
               WHERE dedupe_key IS NOT NULL AND status IN ('open', 'acknowledged', 'escalated')
           DO UPDATE SET
               vital_reading_id = EXCLUDED.vital_reading_id,
               severity = EXCLUDED.severity,
               message = EXCLUDED.message,
               rule_version = EXCLUDED.rule_version,
               evidence = EXCLUDED.evidence,
               last_seen_at = EXCLUDED.last_seen_at
           RETURNING id""",
        (
            hospital_id,
            patient_id,
            reading_id,
            severity,
            rule_id,
            message,
            captured_at,
            rule_id,
            POLICY_VERSION,
            rule_id,
            Jsonb(evidence),
            captured_at,
        ),
    )
    return cursor.fetchone()["id"], rule_id, evidence


def _upsert_screening(
    cursor,
    *,
    hospital_id,
    patient_id,
    screening_type: str,
    score: float,
    risk_level: str,
    responses: dict[str, Any],
) -> None:
    cursor.execute(
        """SELECT id FROM screenings
           WHERE hospital_id = %s AND patient_id = %s
             AND screening_type = %s AND source = 'demo_seed'
           ORDER BY submitted_at DESC LIMIT 1""",
        (hospital_id, patient_id, screening_type),
    )
    existing = cursor.fetchone()
    if existing:
        cursor.execute(
            """UPDATE screenings
               SET screening_type = %s, language_code = 'en', score = %s, risk_level = %s,
                   responses = %s, submitted_at = now()
               WHERE id = %s""",
            (screening_type, score, risk_level, Jsonb(responses), existing["id"]),
        )
    else:
        cursor.execute(
            """INSERT INTO screenings
               (hospital_id, patient_id, screening_type, language_code, score,
                risk_level, responses, source)
               VALUES (%s, %s, %s, 'en', %s, %s, %s, 'demo_seed')""",
            (hospital_id, patient_id, screening_type, score, risk_level, Jsonb(responses)),
        )


def seed(connection) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    with connection.cursor() as cursor:
        cursor.execute(
            """INSERT INTO hospitals (name, code, address, district, state, contact_phone)
               VALUES (%s, %s, %s, %s, %s, %s)
               ON CONFLICT (code) DO UPDATE SET
                   name = EXCLUDED.name,
                   address = EXCLUDED.address,
                   district = EXCLUDED.district,
                   state = EXCLUDED.state,
                   contact_phone = EXCLUDED.contact_phone,
                   updated_at = now()
               RETURNING id, name, code""",
            (
                DEMO_HOSPITAL_NAME,
                DEMO_HOSPITAL_CODE,
                "12 Community Health Road",
                "Nashik",
                "Maharashtra",
                "+919000000001",
            ),
        )
        hospital = cursor.fetchone()
        hospital_id = hospital["id"]

        clinician_id = _upsert_user(
            cursor,
            firebase_uid="demo-doctor",
            email="demo.doctor@maatriwatch.local",
            display_name="Dr. Asha Mehta",
        )
        admin_id = _upsert_user(
            cursor,
            firebase_uid="demo-admin",
            email="demo.admin@maatriwatch.local",
            display_name="Demo Hospital Admin",
        )
        _upsert_membership(cursor, hospital_id=hospital_id, user_id=clinician_id, role="clinician")
        _upsert_membership(cursor, hospital_id=hospital_id, user_id=admin_id, role="hospital_admin")

        now = datetime.now(timezone.utc).replace(microsecond=0)
        seeded_devices: list[dict[str, Any]] = []
        patient_rows: dict[int, dict[str, Any]] = {}
        for patient in DEMO_PATIENTS:
            patient_user_id = _upsert_user(
                cursor,
                firebase_uid=f"demo-patient-{patient.index}",
                email=f"demo.patient.{patient.index}@maatriwatch.local",
                phone_e164=f"+919000010{patient.index:02d}",
                display_name=patient.full_name,
            )
            _upsert_membership(cursor, hospital_id=hospital_id, user_id=patient_user_id, role="patient")
            cursor.execute(
                """INSERT INTO patients
                   (hospital_id, user_id, medical_record_number, full_name, date_of_birth,
                    preferred_language, delivery_date, emergency_contact_name,
                    emergency_contact_phone, consented_at, is_active)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, now(), true)
                   ON CONFLICT (hospital_id, medical_record_number) DO UPDATE SET
                       user_id = EXCLUDED.user_id,
                       full_name = EXCLUDED.full_name,
                       preferred_language = EXCLUDED.preferred_language,
                       delivery_date = EXCLUDED.delivery_date,
                       emergency_contact_name = EXCLUDED.emergency_contact_name,
                       emergency_contact_phone = EXCLUDED.emergency_contact_phone,
                       is_active = true,
                       updated_at = now()
                   RETURNING id, full_name""",
                (
                    hospital_id,
                    patient_user_id,
                    patient.mrn,
                    patient.full_name,
                    date(1992 + (patient.index % 7), (patient.index % 12) + 1, min(patient.index + 3, 27)),
                    patient.language,
                    now.date() - timedelta(days=patient.days_postpartum),
                    f"Family contact for {patient.full_name}",
                    f"+919100020{patient.index:02d}",
                ),
            )
            patient_row = cursor.fetchone()
            patient_rows[patient.index] = patient_row

            key = demo_device_key(patient.index)
            cursor.execute(
                """INSERT INTO devices
                   (hospital_id, serial_number, api_key_hash, status, assigned_patient_id,
                    firmware_version, last_seen_at)
                   VALUES (%s, %s, %s, 'assigned', %s, 'demo-sim-1.0.0', %s)
                   ON CONFLICT (serial_number) DO UPDATE SET
                       hospital_id = EXCLUDED.hospital_id,
                       api_key_hash = EXCLUDED.api_key_hash,
                       status = 'assigned',
                       assigned_patient_id = EXCLUDED.assigned_patient_id,
                       firmware_version = EXCLUDED.firmware_version,
                       last_seen_at = GREATEST(devices.last_seen_at, EXCLUDED.last_seen_at),
                       updated_at = now()
                   RETURNING id, serial_number""",
                (hospital_id, patient.serial_number, _HASHER.hash(key), patient_row["id"], now),
            )
            device = cursor.fetchone()
            seeded_devices.append({"id": device["id"], "serial_number": device["serial_number"], "key": key})

            # Five-minute spacing gives the dashboard a compact but useful trend chart.
            latest_reading = None
            for sample in range(6):
                captured_at = now - timedelta(minutes=(5 - sample) * 5)
                payload = _reading_for(patient, sample, captured_at)
                latest_reading = _insert_reading(
                    cursor,
                    hospital_id=hospital_id,
                    patient_id=patient_row["id"],
                    device_id=device["id"],
                    payload=payload,
                )

            if patient.risk and latest_reading:
                alert_id, rule_id, evidence = _upsert_alert(
                    cursor,
                    hospital_id=hospital_id,
                    patient_id=patient_row["id"],
                    reading_id=latest_reading["id"],
                    captured_at=latest_reading["captured_at"],
                    kind=patient.risk,
                )
                cursor.execute(
                    """INSERT INTO alert_observations (alert_id, vital_reading_id, rule_version, evidence)
                       VALUES (%s, %s, %s, %s)
                       ON CONFLICT (alert_id, vital_reading_id) DO NOTHING""",
                    (alert_id, latest_reading["id"], POLICY_VERSION, Jsonb(evidence)),
                )

        _upsert_screening(
            cursor,
            hospital_id=hospital_id,
            patient_id=patient_rows[2]["id"],
            screening_type="EPDS",
            score=6,
            risk_level="low",
            responses={"demo_seed": True, "q1": 0, "q2": 1, "q3": 1},
        )
        _upsert_screening(
            cursor,
            hospital_id=hospital_id,
            patient_id=patient_rows[6]["id"],
            screening_type="GDM",
            score=152,
            risk_level="review",
            responses={"demo_seed": True, "fasting_glucose_mg_dl": 104, "two_hour_glucose_mg_dl": 152},
        )
    return hospital, seeded_devices


def main() -> int:
    database_url = _require_database_url()
    try:
        with connect(database_url, row_factory=dict_row) as connection:
            _require_migrated_schema(connection)
            hospital, devices = seed(connection)
            connection.commit()
    except OperationalError:
        print("Could not connect to Postgres. Check DATABASE_URL without printing or committing it.", file=sys.stderr)
        return 1
    except SystemExit:
        raise
    except Exception:
        # Do not echo a database exception: connection details can be embedded in it.
        print("Demo seed failed. Confirm the three SQL migrations completed successfully, then retry.", file=sys.stderr)
        return 1

    print("MaatriWatch demo data is ready.")
    print(f"Hospital: {hospital['name']} ({hospital['code']})")
    print(f"Hospital ID: {hospital['id']}")
    print("Demo clinician Firebase UID: demo-doctor | admin Firebase UID: demo-admin")
    print("Demo devices (DEMO ONLY — rotate/delete before any shared deployment):")
    for device in devices:
        print(f"  {device['serial_number']}: id={device['id']} key={device['key']}")
    print("Live-flow command after the Flask API is running:")
    print("  python scripts/trigger_demo_alert.py --serial MW-DEMO-0005 --scenario fall")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
