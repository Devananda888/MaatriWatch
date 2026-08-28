"""In-memory data source for the time-boxed MaatriWatch MVP demo.

``DemoStore`` is deliberately framework-free: Flask routes may adapt its
return values and map its exceptions to HTTP responses, but no request/global
state is used here.  It is not a production datastore and must only be used
when the application explicitly enables DEMO_MODE.
"""

from __future__ import annotations

import copy
import hashlib
import json
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from threading import RLock
from typing import Any
from uuid import NAMESPACE_URL, uuid5

from .alerting import POLICY_VERSION, evaluate_alerts


UTC = timezone.utc
ACTIVE_ALERT_STATUSES = {"open", "acknowledged", "escalated"}
SEVERITY_RANK = {"normal": 0, "info": 1, "warning": 2, "critical": 3}
DEMO_HOSPITAL_ID = str(uuid5(NAMESPACE_URL, "maatriwatch-demo/hospital"))


class DemoStoreError(ValueError):
    """Base error that a route adapter can turn into a 400-series response."""

    status_code = 400


class DemoNotFoundError(DemoStoreError):
    status_code = 404


class DemoDeviceAuthError(DemoStoreError):
    status_code = 401


class DemoEventConflictError(DemoStoreError):
    status_code = 409


def _demo_id(kind: str, value: str | int) -> str:
    return str(uuid5(NAMESPACE_URL, f"maatriwatch-demo/{kind}/{value}"))


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _as_datetime(value: Any) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exc:
            raise DemoStoreError("captured_at must be an ISO-8601 timestamp") from exc
    else:
        raise DemoStoreError("captured_at is required")
    if parsed.tzinfo is None:
        raise DemoStoreError("captured_at must include a timezone")
    return parsed.astimezone(UTC)


def _json_copy(value: Any) -> Any:
    """Return JSON-safe copies so callers cannot mutate in-memory state."""

    return copy.deepcopy(value)


def _fingerprint(value: Any) -> str:
    def default(item: Any):
        if isinstance(item, datetime):
            return _iso(item)
        raise TypeError(f"Unsupported demo event value: {type(item)!r}")

    canonical = json.dumps(value, default=default, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


class DemoStore:
    """A small, concurrency-safe repository for a locally demoable workflow.

    Public methods return the same JSON-shaped payloads as the clinician REST
    API wherever that helps the Flutter dashboard.  Timestamps and IDs are
    strings, so Flask can call ``jsonify`` directly.
    """

    def __init__(self) -> None:
        self._lock = RLock()
        self.hospital = {
            "id": DEMO_HOSPITAL_ID,
            "name": "MaatriWatch Demo Community Hospital",
            "code": "MW-DEMO",
            "district": "Nashik",
            "state": "Maharashtra",
        }
        self._users: dict[str, dict[str, Any]] = {}
        self._memberships: dict[str, list[dict[str, str]]] = defaultdict(list)
        self._patients: dict[str, dict[str, Any]] = {}
        self._devices: dict[str, dict[str, Any]] = {}
        self._device_by_serial: dict[str, str] = {}
        self._readings_by_patient: dict[str, list[dict[str, Any]]] = defaultdict(list)
        self._events_by_device: dict[str, dict[str, dict[str, Any]]] = defaultdict(dict)
        self._alerts: dict[str, dict[str, Any]] = {}
        self._alert_episode: dict[tuple[str, str], str] = {}
        self._notes_by_patient: dict[str, list[dict[str, Any]]] = defaultdict(list)
        self._screenings_by_patient: dict[str, list[dict[str, Any]]] = defaultdict(list)
        self._revision = 0
        self._seed()

    # -- Lightweight identity helpers -------------------------------------------------

    def get_user(self, firebase_uid: str) -> dict[str, Any] | None:
        with self._lock:
            user = self._users.get(firebase_uid)
            return _json_copy(user) if user else None

    def memberships_for(self, user_id: str) -> list[dict[str, str]]:
        with self._lock:
            return _json_copy(self._memberships.get(str(user_id), []))

    def demo_context(self, role: str) -> dict[str, Any]:
        """Return a seeded identity for a role-picker adapter.

        Accepted aliases intentionally match the temporary UI labels.
        """

        aliases = {
            "doctor": "demo-doctor",
            "clinician": "demo-doctor",
            "patient": "demo-patient-1",
            "admin": "demo-admin",
            "hospital_admin": "demo-admin",
        }
        firebase_uid = aliases.get(role.strip().lower())
        user = self.get_user(firebase_uid or "")
        if not user:
            raise DemoNotFoundError("Demo role was not found")
        return {"user": user, "hospital_memberships": self.memberships_for(user["id"])}

    # -- Device ingestion --------------------------------------------------------------

    def validate_device(self, device_id: str, device_key: str | None) -> dict[str, Any]:
        """Check one demo device ID/key pair and return non-secret device data."""

        with self._lock:
            device = self._devices.get(str(device_id))
            if not device or device.get("status") != "assigned" or not device.get("assigned_patient_id"):
                raise DemoDeviceAuthError("This demo device is not active or assigned")
            if not device_key or device_key != device["_demo_key"]:
                raise DemoDeviceAuthError("Invalid demo device credentials")
            return self._device_public(device)

    def ingest(self, device_id: str, device_key: str | None, payload: dict[str, Any]) -> dict[str, Any]:
        """Store normalized telemetry and upsert active risk-signal episodes.

        ``payload`` is expected to have passed the production ingestion
        parser.  The method nevertheless checks the event ID, timestamp, and
        device credentials so it remains safe for a simple direct route hook.
        ``evaluate_alerts`` is the production rule evaluator; demo mode does
        not invent a second threshold policy.
        """

        if not isinstance(payload, dict):
            raise DemoStoreError("A JSON object is required")
        with self._lock:
            device = self._devices.get(str(device_id))
            if not device or device.get("status") != "assigned" or not device.get("assigned_patient_id"):
                raise DemoDeviceAuthError("This demo device is not active or assigned")
            if not device_key or device_key != device["_demo_key"]:
                raise DemoDeviceAuthError("Invalid demo device credentials")

            normalized = self._normalize_payload(payload)
            event_id = normalized["source_event_id"]
            event_fingerprint = _fingerprint(normalized["raw_payload"])
            existing = self._events_by_device[device["id"]].get(event_id)
            if existing:
                if existing["payload_fingerprint"] != event_fingerprint:
                    raise DemoEventConflictError("event_id was already used with a different payload")
                return {
                    "reading_id": existing["id"],
                    "event_id": event_id,
                    "duplicate": True,
                    "alert_ids": _json_copy(existing["alert_ids"]),
                    "realtime": "demo_polling",
                    "revision": self._revision,
                }

            now = datetime.now(UTC)
            reading = {
                "id": _demo_id("reading", f"{device['id']}:{event_id}"),
                "hospital_id": self.hospital["id"],
                "patient_id": device["assigned_patient_id"],
                "device_id": device["id"],
                "captured_at": _iso(normalized["captured_at"]),
                "received_at": _iso(now),
                "source_event_id": event_id,
                "source_sequence": normalized.get("source_sequence"),
                "heart_rate_bpm": normalized.get("heart_rate_bpm"),
                "spo2_percent": normalized.get("spo2_percent"),
                "temperature_c": normalized.get("temperature_c"),
                "ambient_temperature_c": normalized.get("ambient_temperature_c"),
                "ambient_humidity_percent": normalized.get("ambient_humidity_percent"),
                "systolic_bp": normalized.get("systolic_bp"),
                "diastolic_bp": normalized.get("diastolic_bp"),
                "battery_percent": normalized.get("battery_percent"),
                "blood_loss_ml": normalized.get("blood_loss_ml"),
                "bleeding_reported": normalized["bleeding_reported"],
                "motion": _json_copy(normalized["motion"]),
                "payload_fingerprint": event_fingerprint,
            }

            alert_ids: list[str] = []
            for candidate in evaluate_alerts(normalized):
                alert_ids.append(self._upsert_alert(device, reading, normalized, candidate))
            reading["alert_ids"] = alert_ids
            self._readings_by_patient[reading["patient_id"]].append(reading)
            self._readings_by_patient[reading["patient_id"]].sort(
                key=lambda item: (item["captured_at"], item["id"])
            )
            self._events_by_device[device["id"]][event_id] = reading
            device["last_seen_at"] = reading["captured_at"]
            self._revision += 1
            return {
                "reading_id": reading["id"],
                "event_id": event_id,
                "duplicate": False,
                "alert_ids": _json_copy(alert_ids),
                "realtime": "demo_polling",
                "revision": self._revision,
                "live_vital": self._live_vital(reading),
                "live_alerts": [self._alert_public(self._alerts[alert_id]) for alert_id in alert_ids],
            }

    # Alias makes a route hook read naturally without exposing implementation details.
    ingest_vitals = ingest

    # -- Dashboard data ---------------------------------------------------------------

    def patient_list(self, *, status: str = "all", sort: str = "risk", limit: int = 100) -> dict[str, Any]:
        if status not in {"all", "normal", "info", "warning", "critical"}:
            raise DemoStoreError("status must be all, normal, info, warning, or critical")
        if sort not in {"risk", "name", "recent"}:
            raise DemoStoreError("sort must be risk, name, or recent")
        if not 1 <= int(limit) <= 250:
            raise DemoStoreError("limit must be between 1 and 250")
        with self._lock:
            items = [self._patient_summary(patient) for patient in self._patients.values() if patient["is_active"]]
            if status != "all":
                items = [item for item in items if item["status"] == status]
            if sort == "risk":
                # Stable passes give severity/recentness descending while the
                # final name tie-break remains alphabetically predictable.
                items.sort(key=lambda item: (item["full_name"].lower(), item["id"]))
                items.sort(
                    key=lambda item: item["latest_vital"]["captured_at"] if item["latest_vital"] else "",
                    reverse=True,
                )
                items.sort(key=lambda item: SEVERITY_RANK[item["status"]], reverse=True)
            elif sort == "recent":
                items.sort(
                    key=lambda item: (item["latest_vital"]["captured_at"] if item["latest_vital"] else "", item["full_name"].lower()),
                    reverse=True,
                )
            else:
                items.sort(key=lambda item: (item["full_name"].lower(), item["id"]))
            return {
                "items": _json_copy(items[: int(limit)]),
                "sort": sort,
                "status_filter": status,
                "live_ordering": "stable",
                "revision": self._revision,
            }

    def patient_detail(self, patient_id: str) -> dict[str, Any]:
        with self._lock:
            patient = self._patient(patient_id)
            latest = self._latest_reading(patient["id"])
            active = self._active_alerts(patient["id"])
            severity = self._patient_status(patient["id"])
            device = self._device_for_patient(patient["id"])
            latest_screening = self._latest_screening(patient["id"])
            grouped: dict[str, int] = defaultdict(int)
            for alert in active:
                grouped[alert["severity"]] += 1
            active_summary = [
                {"severity": severity_name, "count": count}
                for severity_name, count in sorted(grouped.items(), key=lambda item: SEVERITY_RANK[item[0]], reverse=True)
            ]
            return {
                "patient": _json_copy(patient),
                "status": severity,
                "latest_vital": self._vital_public(latest) if latest else None,
                "device": self._device_public(device) if device else None,
                "active_alerts": active_summary,
                "latest_screening": _json_copy(latest_screening) if latest_screening else None,
                "revision": self._revision,
            }

    def patient_vitals(
        self,
        patient_id: str,
        *,
        start: str | datetime | None = None,
        end: str | datetime | None = None,
        resolution: str = "raw",
        limit: int = 1_000,
    ) -> dict[str, Any]:
        if resolution not in {"raw", "5m", "1h"}:
            raise DemoStoreError("resolution must be raw, 5m, or 1h")
        if not 1 <= int(limit) <= 2_000:
            raise DemoStoreError("limit must be between 1 and 2000")
        with self._lock:
            patient = self._patient(patient_id)
            now = datetime.now(UTC)
            from_time = _as_datetime(start) if start is not None else now - timedelta(days=1)
            to_time = _as_datetime(end) if end is not None else now
            if from_time >= to_time:
                raise DemoStoreError("from must be before to")
            readings = [
                reading
                for reading in self._readings_by_patient[patient["id"]]
                if from_time <= _as_datetime(reading["captured_at"]) <= to_time
            ]
            if resolution == "raw":
                items = [self._vital_public(reading) for reading in readings]
            else:
                items = self._aggregate_vitals(readings, resolution)
            return {
                "patient_id": patient["id"],
                "from": _iso(from_time),
                "to": _iso(to_time),
                "resolution": resolution,
                "items": _json_copy(items[: int(limit)]),
                "limited": len(items) > int(limit),
                "revision": self._revision,
            }

    def alert_list(
        self,
        *,
        status: str = "active",
        severity: str | None = None,
        patient_id: str | None = None,
        limit: int = 100,
    ) -> dict[str, Any]:
        if status not in {"active", "all", "open", "acknowledged", "escalated", "resolved"}:
            raise DemoStoreError("Invalid alert status filter")
        if severity is not None and severity not in {"info", "warning", "critical"}:
            raise DemoStoreError("severity must be info, warning, or critical")
        if not 1 <= int(limit) <= 250:
            raise DemoStoreError("limit must be between 1 and 250")
        with self._lock:
            if patient_id is not None:
                self._patient(patient_id)
            allowed = ACTIVE_ALERT_STATUSES if status == "active" else None
            values = []
            for alert in self._alerts.values():
                if allowed is not None and alert["status"] not in allowed:
                    continue
                if status not in {"active", "all"} and alert["status"] != status:
                    continue
                if severity is not None and alert["severity"] != severity:
                    continue
                if patient_id is not None and alert["patient_id"] != patient_id:
                    continue
                values.append(self._alert_public(alert, include_patient=True))
            values.sort(
                key=lambda item: (SEVERITY_RANK[item["severity"]], item["updated_at"], item["id"]),
                reverse=True,
            )
            return {
                "items": _json_copy(values[: int(limit)]),
                "status_filter": status,
                "limited": len(values) > int(limit),
                "revision": self._revision,
            }

    # A short alias for route adapters mirroring the REST resource name.
    alerts = alert_list

    def update_alert(
        self,
        alert_id: str,
        *,
        action: str,
        note: str | None = None,
        actor_id: str = "demo-doctor",
    ) -> dict[str, Any]:
        if action not in {"acknowledge", "resolve", "escalate"}:
            raise DemoStoreError("action must be acknowledge, resolve, or escalate")
        cleaned_note = note.strip() if isinstance(note, str) else None
        if action in {"resolve", "escalate"} and not cleaned_note:
            raise DemoStoreError("A clinical note is required for this action")
        if cleaned_note and len(cleaned_note) > 5_000:
            raise DemoStoreError("note must not exceed 5000 characters")
        with self._lock:
            alert = self._alerts.get(str(alert_id))
            if not alert:
                raise DemoNotFoundError("Alert was not found in this hospital")
            if alert["status"] == "resolved" and action != "resolve":
                raise DemoStoreError("A resolved alert cannot be changed")
            now = _iso(datetime.now(UTC))
            changed = False
            if action == "acknowledge" and alert["status"] == "open":
                alert.update({"status": "acknowledged", "acknowledged_by": actor_id, "acknowledged_at": now})
                changed = True
            elif action == "resolve" and alert["status"] != "resolved":
                alert.update(
                    {
                        "status": "resolved",
                        "resolved_by": actor_id,
                        "resolved_at": now,
                        "resolution_note": cleaned_note,
                    }
                )
                self._alert_episode.pop((alert["patient_id"], alert["dedupe_key"]), None)
                changed = True
            elif action == "escalate" and alert["status"] in ACTIVE_ALERT_STATUSES:
                alert.update(
                    {
                        "status": "escalated",
                        "escalated_by": actor_id,
                        "escalated_at": now,
                        "escalation_note": cleaned_note,
                    }
                )
                changed = True
            if changed:
                alert["updated_at"] = now
                self._revision += 1
            return {"alert": self._alert_public(alert, include_patient=True), "changed": changed, "revision": self._revision}

    def list_notes(self, patient_id: str) -> dict[str, Any]:
        with self._lock:
            self._patient(patient_id)
            notes = sorted(self._notes_by_patient[patient_id], key=lambda item: item["created_at"], reverse=True)
            return {"items": _json_copy(notes), "revision": self._revision}

    def add_note(self, patient_id: str, note: str, *, author_user_id: str = "demo-doctor") -> dict[str, Any]:
        if not isinstance(note, str) or not note.strip():
            raise DemoStoreError("note must be text")
        cleaned = note.strip()
        if len(cleaned) > 5_000:
            raise DemoStoreError("note must not exceed 5000 characters")
        with self._lock:
            self._patient(patient_id)
            author = self._users.get(author_user_id)
            author_name = author["display_name"] if author else "Demo clinician"
            created_at = _iso(datetime.now(UTC))
            item = {
                "id": _demo_id("note", f"{patient_id}:{created_at}:{len(self._notes_by_patient[patient_id])}"),
                "hospital_id": self.hospital["id"],
                "patient_id": patient_id,
                "author_user_id": author_user_id,
                "author_name": author_name,
                "author_display_name": author_name,
                "note": cleaned,
                "created_at": created_at,
                "updated_at": created_at,
            }
            self._notes_by_patient[patient_id].append(item)
            self._revision += 1
            return {"note": _json_copy(item), "revision": self._revision}

    def screenings(self, patient_id: str) -> dict[str, Any]:
        with self._lock:
            self._patient(patient_id)
            values = sorted(self._screenings_by_patient[patient_id], key=lambda item: item["submitted_at"], reverse=True)
            return {"items": _json_copy(values), "revision": self._revision}

    def live_snapshot(self) -> dict[str, Any]:
        """Return a small poll-friendly projection for a no-Firebase demo."""

        with self._lock:
            vitals = {
                patient_id: self._live_vital(reading)
                for patient_id in self._patients
                if (reading := self._latest_reading(patient_id)) is not None
            }
            alerts = {
                alert_id: self._alert_public(alert)
                for alert_id, alert in self._alerts.items()
                if alert["status"] in ACTIVE_ALERT_STATUSES
            }
            return {
                "hospital_id": self.hospital["id"],
                "revision": self._revision,
                "live_vitals": _json_copy(vitals),
                "live_alerts": _json_copy(alerts),
            }

    # -- Internal serializers and seed data -------------------------------------------

    def _seed(self) -> None:
        now = datetime.now(UTC).replace(microsecond=0)
        self._add_user("demo-doctor", "demo.doctor@maatriwatch.local", "Dr. Asha Mehta", "clinician")
        self._add_user("demo-admin", "demo.admin@maatriwatch.local", "Demo Hospital Admin", "hospital_admin")

        fixtures = (
            ("Ananya Sharma", "hi", 12, 76, 98.0, 36.8, 112, 72, None),
            ("Meera Kulkarni", "mr", 19, 82, 97.0, 36.9, 116, 74, None),
            ("Lakshmi Nair", "ml", 8, 79, 98.0, 36.7, 110, 70, None),
            ("Kavya Reddy", "te", 25, 84, 97.0, 37.0, 118, 76, None),
            ("Pooja Yadav", "hi", 5, 74, 99.0, 36.6, 108, 68, None),
            ("Farah Khan", "ur", 16, 88, 97.0, 36.9, 138, 88, "hypertension"),
            ("Nandini Rao", "ta", 10, 80, 98.0, 36.8, 114, 72, "fall"),
        )
        for index, fixture in enumerate(fixtures, start=1):
            name, language, days_postpartum, heart_rate, spo2, temperature, systolic, diastolic, risk = fixture
            patient_id = _demo_id("patient", index)
            user_uid = f"demo-patient-{index}"
            user = self._add_user(user_uid, f"demo.patient.{index}@maatriwatch.local", name, "patient")
            patient = {
                "id": patient_id,
                "hospital_id": self.hospital["id"],
                "user_id": user["id"],
                "medical_record_number": f"DEMO-{index:03d}",
                "full_name": name,
                "date_of_birth": date(1992 + (index % 7), (index % 12) + 1, min(index + 3, 27)).isoformat(),
                "preferred_language": language,
                "delivery_date": (now.date() - timedelta(days=days_postpartum)).isoformat(),
                "emergency_contact_name": f"Family contact for {name}",
                "emergency_contact_phone": f"+919100020{index:02d}",
                "consented_at": _iso(now - timedelta(days=days_postpartum + 2)),
                "is_active": True,
                "created_at": _iso(now - timedelta(days=days_postpartum + 7)),
                "updated_at": _iso(now),
            }
            self._patients[patient_id] = patient
            device = {
                "id": _demo_id("device", index),
                "hospital_id": self.hospital["id"],
                "serial_number": f"MW-DEMO-{index:04d}",
                "_demo_key": f"mw-demo-device-key-{index:02d}-for-demo-only",
                "status": "assigned",
                "assigned_patient_id": patient_id,
                "firmware_version": "demo-sim-1.0.0",
                "last_seen_at": _iso(now - timedelta(minutes=5)),
            }
            self._devices[device["id"]] = device
            self._device_by_serial[device["serial_number"]] = device["id"]
            self._seed_patient_history(
                device,
                heart_rate=heart_rate,
                spo2=spo2,
                temperature=temperature,
                systolic=systolic,
                diastolic=diastolic,
                risk=risk,
                now=now,
            )

        # Two common dashboard cards: a brief EPDS-style check and GDM follow-up.
        meera_id = _demo_id("patient", 2)
        farah_id = _demo_id("patient", 6)
        self._screenings_by_patient[meera_id].append(
            {
                "id": _demo_id("screening", "epds-2"),
                "hospital_id": self.hospital["id"],
                "patient_id": meera_id,
                "screening_type": "EPDS",
                "language_code": "mr",
                "score": 6.0,
                "risk_level": "low",
                "responses": {"q1": 0, "q2": 1, "q3": 1, "demo": True},
                "submitted_at": _iso(now - timedelta(hours=5)),
                "source": "demo_patient_app",
            }
        )
        self._screenings_by_patient[farah_id].append(
            {
                "id": _demo_id("screening", "gdm-6"),
                "hospital_id": self.hospital["id"],
                "patient_id": farah_id,
                "screening_type": "GDM",
                "language_code": "ur",
                "score": 154.0,
                "risk_level": "follow_up",
                "responses": {"fasting_glucose_mg_dl": 104, "post_meal_glucose_mg_dl": 154, "demo": True},
                "submitted_at": _iso(now - timedelta(hours=2)),
                "source": "demo_patient_app",
            }
        )
        self._revision = 1

    def _add_user(self, firebase_uid: str, email: str, display_name: str, role: str) -> dict[str, Any]:
        user = {
            "id": _demo_id("user", firebase_uid),
            "firebase_uid": firebase_uid,
            "email": email,
            "phone_e164": None,
            "display_name": display_name,
            "is_active": True,
        }
        self._users[firebase_uid] = user
        self._memberships[user["id"]].append(
            {
                "hospital_id": self.hospital["id"],
                "hospital_name": self.hospital["name"],
                "role": role,
            }
        )
        return user

    def _seed_patient_history(
        self,
        device: dict[str, Any],
        *,
        heart_rate: int,
        spo2: float,
        temperature: float,
        systolic: int,
        diastolic: int,
        risk: str | None,
        now: datetime,
    ) -> None:
        heart_offsets = (-3, 1, 0, 3, -1, 2)
        bp_offsets = (-4, -1, 2, 0, 3, 1)
        for sample in range(6):
            sample_systolic = systolic + bp_offsets[sample]
            sample_diastolic = diastolic + max(-2, bp_offsets[sample] // 2)
            sample_heart_rate = heart_rate + heart_offsets[sample]
            motion: dict[str, Any] = {
                "fall_detected": False,
                "impact_g": 0.1,
                "orientation_change_degrees": 2,
                "post_impact_immobile_seconds": 0,
            }
            if sample == 5 and risk == "hypertension":
                sample_systolic, sample_diastolic, sample_heart_rate = 148, 96, 92
            if sample == 5 and risk == "fall":
                motion = {
                    "fall_detected": True,
                    "impact_g": 3.2,
                    "orientation_change_degrees": 88,
                    "post_impact_immobile_seconds": 42,
                }
            captured_at = now - timedelta(minutes=(5 - sample) * 5)
            payload = {
                "source_event_id": f"demo-history:{device['serial_number']}:{sample}",
                "source_sequence": sample,
                "captured_at": captured_at,
                "heart_rate_bpm": sample_heart_rate,
                "spo2_percent": round(spo2 - (0.2 if sample % 3 == 0 else 0), 1),
                "temperature_c": round(temperature + (0.1 if sample == 3 else 0), 1),
                "ambient_temperature_c": round(26.0 + (0.2 if sample % 2 else 0), 1),
                "ambient_humidity_percent": 58.0 + sample,
                "systolic_bp": sample_systolic,
                "diastolic_bp": sample_diastolic,
                "battery_percent": 92 - sample,
                "motion": motion,
                "bleeding_reported": False,
            }
            # Direct internal call avoids credential checks while still using
            # the same read-normalise-rule-upsert pathway as a live event.
            self._ingest_seed(device, payload)

    def _ingest_seed(self, device: dict[str, Any], payload: dict[str, Any]) -> None:
        normalized = self._normalize_payload(payload)
        event_id = normalized["source_event_id"]
        now = datetime.now(UTC)
        reading = {
            "id": _demo_id("reading", f"{device['id']}:{event_id}"),
            "hospital_id": self.hospital["id"],
            "patient_id": device["assigned_patient_id"],
            "device_id": device["id"],
            "captured_at": _iso(normalized["captured_at"]),
            "received_at": _iso(now),
            "source_event_id": event_id,
            "source_sequence": normalized.get("source_sequence"),
            "heart_rate_bpm": normalized.get("heart_rate_bpm"),
            "spo2_percent": normalized.get("spo2_percent"),
            "temperature_c": normalized.get("temperature_c"),
            "ambient_temperature_c": normalized.get("ambient_temperature_c"),
            "ambient_humidity_percent": normalized.get("ambient_humidity_percent"),
            "systolic_bp": normalized.get("systolic_bp"),
            "diastolic_bp": normalized.get("diastolic_bp"),
            "battery_percent": normalized.get("battery_percent"),
            "blood_loss_ml": normalized.get("blood_loss_ml"),
            "bleeding_reported": normalized["bleeding_reported"],
            "motion": _json_copy(normalized["motion"]),
            "payload_fingerprint": _fingerprint(normalized["raw_payload"]),
        }
        alert_ids = [self._upsert_alert(device, reading, normalized, candidate) for candidate in evaluate_alerts(normalized)]
        reading["alert_ids"] = alert_ids
        self._readings_by_patient[reading["patient_id"]].append(reading)
        self._events_by_device[device["id"]][event_id] = reading
        device["last_seen_at"] = reading["captured_at"]

    def _normalize_payload(self, payload: dict[str, Any]) -> dict[str, Any]:
        event_id = payload.get("source_event_id", payload.get("event_id"))
        if not isinstance(event_id, str) or not event_id.strip():
            raise DemoStoreError("event_id is required")
        motion = payload.get("motion") or {}
        if not isinstance(motion, dict):
            raise DemoStoreError("motion must be an object")
        raw_payload = payload.get("raw_payload")
        if not isinstance(raw_payload, dict):
            raw_payload = {
                key: (_iso(value) if isinstance(value, datetime) else _json_copy(value))
                for key, value in payload.items()
                if key not in {"payload_fingerprint", "raw_payload"}
            }
        return {
            "source_event_id": event_id.strip(),
            "source_sequence": payload.get("source_sequence"),
            "captured_at": _as_datetime(payload.get("captured_at")),
            "heart_rate_bpm": payload.get("heart_rate_bpm"),
            "spo2_percent": payload.get("spo2_percent"),
            "temperature_c": payload.get("temperature_c"),
            "ambient_temperature_c": payload.get("ambient_temperature_c"),
            "ambient_humidity_percent": payload.get("ambient_humidity_percent"),
            "systolic_bp": payload.get("systolic_bp"),
            "diastolic_bp": payload.get("diastolic_bp"),
            "battery_percent": payload.get("battery_percent"),
            "blood_loss_ml": payload.get("blood_loss_ml"),
            "bleeding_reported": bool(payload.get("bleeding_reported", False)),
            "motion": _json_copy(motion),
            "raw_payload": raw_payload,
        }

    def _upsert_alert(self, device: dict[str, Any], reading: dict[str, Any], payload: dict[str, Any], candidate) -> str:
        episode_key = (reading["patient_id"], candidate.dedupe_key)
        existing_id = self._alert_episode.get(episode_key)
        now = _iso(datetime.now(UTC))
        evidence = {
            "policy_version": POLICY_VERSION,
            "source_event_id": payload["source_event_id"],
            "captured_at": reading["captured_at"],
            "rule_evidence": _json_copy(candidate.evidence),
        }
        if existing_id and self._alerts[existing_id]["status"] in ACTIVE_ALERT_STATUSES:
            alert = self._alerts[existing_id]
            alert.update(
                {
                    "vital_reading_id": reading["id"],
                    "severity": candidate.severity,
                    "message": candidate.message,
                    "rule_version": POLICY_VERSION,
                    "evidence": evidence,
                    "last_seen_at": now,
                    "occurrence_count": alert["occurrence_count"] + 1,
                    "updated_at": now,
                }
            )
            return existing_id
        alert_id = _demo_id("alert", f"{reading['patient_id']}:{candidate.dedupe_key}:{reading['id']}")
        alert = {
            "id": alert_id,
            "hospital_id": self.hospital["id"],
            "patient_id": reading["patient_id"],
            "vital_reading_id": reading["id"],
            "severity": candidate.severity,
            "status": "open",
            "alert_type": candidate.rule_id,
            "message": candidate.message,
            "triggered_at": now,
            "rule_id": candidate.rule_id,
            "rule_version": POLICY_VERSION,
            "dedupe_key": candidate.dedupe_key,
            "evidence": evidence,
            "last_seen_at": now,
            "occurrence_count": 1,
            "updated_at": now,
            "acknowledged_by": None,
            "acknowledged_at": None,
            "escalated_by": None,
            "escalated_at": None,
            "escalation_note": None,
            "resolved_by": None,
            "resolved_at": None,
            "resolution_note": None,
        }
        self._alerts[alert_id] = alert
        self._alert_episode[episode_key] = alert_id
        return alert_id

    def _patient(self, patient_id: str) -> dict[str, Any]:
        patient = self._patients.get(str(patient_id))
        if not patient or patient["hospital_id"] != self.hospital["id"] or not patient["is_active"]:
            raise DemoNotFoundError("Patient was not found in this hospital")
        return patient

    def _device_for_patient(self, patient_id: str) -> dict[str, Any] | None:
        matches = [
            device
            for device in self._devices.values()
            if device["assigned_patient_id"] == patient_id and device["status"] == "assigned"
        ]
        return max(matches, key=lambda device: device["last_seen_at"] or "", default=None)

    def _latest_reading(self, patient_id: str) -> dict[str, Any] | None:
        readings = self._readings_by_patient.get(patient_id, [])
        return readings[-1] if readings else None

    def _active_alerts(self, patient_id: str) -> list[dict[str, Any]]:
        return [
            alert
            for alert in self._alerts.values()
            if alert["patient_id"] == patient_id and alert["status"] in ACTIVE_ALERT_STATUSES
        ]

    def _patient_status(self, patient_id: str) -> str:
        active = self._active_alerts(patient_id)
        return max((alert["severity"] for alert in active), key=SEVERITY_RANK.get, default="normal")

    def _patient_summary(self, patient: dict[str, Any]) -> dict[str, Any]:
        latest = self._latest_reading(patient["id"])
        device = self._device_for_patient(patient["id"])
        active = self._active_alerts(patient["id"])
        return {
            "id": patient["id"],
            "medical_record_number": patient["medical_record_number"],
            "full_name": patient["full_name"],
            "preferred_language": patient["preferred_language"],
            "delivery_date": patient["delivery_date"],
            "status": self._patient_status(patient["id"]),
            "active_alert_count": len(active),
            "latest_vital": self._vital_public(latest) if latest else None,
            "device": self._device_public(device) if device else None,
        }

    def _vital_public(self, reading: dict[str, Any] | None) -> dict[str, Any] | None:
        if reading is None:
            return None
        fields = (
            "captured_at",
            "received_at",
            "device_id",
            "source_event_id",
            "source_sequence",
            "heart_rate_bpm",
            "spo2_percent",
            "temperature_c",
            "ambient_temperature_c",
            "ambient_humidity_percent",
            "systolic_bp",
            "diastolic_bp",
            "battery_percent",
            "blood_loss_ml",
            "bleeding_reported",
            "motion",
        )
        return {field: _json_copy(reading[field]) for field in fields}

    def _live_vital(self, reading: dict[str, Any]) -> dict[str, Any]:
        vital = self._vital_public(reading) or {}
        vital["assessment_state"] = "rule_evaluated"
        vital["status"] = self._patient_status(reading["patient_id"])
        return {
            "hospital_id": self.hospital["id"],
            "patient_id": reading["patient_id"],
            "reading": vital,
        }

    def _device_public(self, device: dict[str, Any] | None) -> dict[str, Any] | None:
        if device is None:
            return None
        fields = ("id", "serial_number", "firmware_version", "last_seen_at", "status", "assigned_patient_id")
        return {field: device[field] for field in fields}

    def _alert_public(self, alert: dict[str, Any], *, include_patient: bool = False) -> dict[str, Any]:
        fields = (
            "id",
            "hospital_id",
            "patient_id",
            "severity",
            "status",
            "alert_type",
            "message",
            "triggered_at",
            "last_seen_at",
            "occurrence_count",
            "rule_version",
            "updated_at",
            "acknowledged_at",
            "escalated_at",
            "resolved_at",
        )
        value = {field: _json_copy(alert[field]) for field in fields}
        if include_patient:
            patient = self._patients[alert["patient_id"]]
            value.update({"full_name": patient["full_name"], "medical_record_number": patient["medical_record_number"]})
        return value

    def _latest_screening(self, patient_id: str) -> dict[str, Any] | None:
        values = self._screenings_by_patient.get(patient_id, [])
        return max(values, key=lambda item: item["submitted_at"], default=None)

    def _aggregate_vitals(self, readings: list[dict[str, Any]], resolution: str) -> list[dict[str, Any]]:
        buckets: dict[datetime, list[dict[str, Any]]] = defaultdict(list)
        for reading in readings:
            captured = _as_datetime(reading["captured_at"])
            if resolution == "5m":
                bucket = captured.replace(minute=(captured.minute // 5) * 5, second=0, microsecond=0)
            else:
                bucket = captured.replace(minute=0, second=0, microsecond=0)
            buckets[bucket].append(reading)
        numeric_fields = (
            "heart_rate_bpm",
            "spo2_percent",
            "temperature_c",
            "ambient_temperature_c",
            "ambient_humidity_percent",
            "systolic_bp",
            "diastolic_bp",
            "battery_percent",
        )
        values = []
        for bucket, bucket_readings in sorted(buckets.items()):
            item: dict[str, Any] = {"captured_at": _iso(bucket), "sample_count": len(bucket_readings)}
            for field in numeric_fields:
                points = [reading[field] for reading in bucket_readings if reading.get(field) is not None]
                item[field] = round(sum(points) / len(points), 2) if points else None
            blood_loss = [reading["blood_loss_ml"] for reading in bucket_readings if reading.get("blood_loss_ml") is not None]
            item["blood_loss_ml"] = max(blood_loss) if blood_loss else None
            values.append(item)
        return values


# Routes may import this singleton in DEMO_MODE.  Tests can create their own
# ``DemoStore`` to avoid state sharing.
demo_store = DemoStore()
