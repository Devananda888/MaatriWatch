"""Pure, versioned telemetry risk-rule evaluation.

These rules deliberately emit *risk signals*, not diagnoses.  They are a
server-side baseline that must be clinically approved for each deployment.
Keeping them pure makes every alert reproducible from the stored evidence.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping


POLICY_VERSION = "baseline-2026-08-14"

# This policy is intentionally small and explicit.  Do not move values into a
# Flutter client or a device: clinical policy must be centrally controlled and
# versioned with the resulting alert evidence.
POLICY: dict[str, dict[str, float]] = {
    "postpartum_hypertension": {
        "elevated_systolic_mm_hg": 140,
        "elevated_diastolic_mm_hg": 90,
        "severe_systolic_mm_hg": 160,
        "severe_diastolic_mm_hg": 110,
    },
    "postpartum_hemorrhage": {
        # A bleeding measurement/report is required. Vitals alone are not a
        # safe basis for labelling a patient as having a postpartum haemorrhage.
        "early_blood_loss_ml": 300,
        "critical_blood_loss_ml": 1000,
        "tachycardia_bpm": 100,
        "low_systolic_mm_hg": 90,
        "shock_index": 1.0,
    },
    "fall": {
        "impact_g": 2.5,
        "orientation_change_degrees": 60,
        "post_impact_immobile_seconds": 30,
    },
}


@dataclass(frozen=True)
class AlertCandidate:
    """An immutable risk signal generated for a single telemetry reading."""

    rule_id: str
    severity: str
    message: str
    evidence: dict[str, Any]

    @property
    def dedupe_key(self) -> str:
        # One unresolved episode per rule and patient. Policy version is stored
        # separately so a policy rollout does not open duplicate active alerts.
        return self.rule_id


def evaluate_alerts(reading: Mapping[str, Any]) -> list[AlertCandidate]:
    """Return risk signals for a normalized, current device reading.

    `reading` contains only validated numeric fields plus the optional motion
    and bleeding inputs. Missing values make a particular rule not evaluable;
    they are never silently treated as normal.
    """

    candidates: list[AlertCandidate] = []
    candidates.extend(_evaluate_postpartum_hypertension(reading))
    candidates.extend(_evaluate_postpartum_hemorrhage(reading))
    candidates.extend(_evaluate_fall(reading))
    return candidates


def _evaluate_postpartum_hypertension(reading: Mapping[str, Any]) -> list[AlertCandidate]:
    systolic = reading.get("systolic_bp")
    diastolic = reading.get("diastolic_bp")
    if systolic is None and diastolic is None:
        return []

    policy = POLICY["postpartum_hypertension"]
    evidence = {"systolic_bp": systolic, "diastolic_bp": diastolic}
    is_severe = (
        (systolic is not None and systolic >= policy["severe_systolic_mm_hg"])
        or (diastolic is not None and diastolic >= policy["severe_diastolic_mm_hg"])
    )
    if is_severe:
        return [
            AlertCandidate(
                # Severe and non-severe readings belong to one alert episode;
                # the database upsert escalates the existing warning instead
                # of opening a second, competing BP alert.
                rule_id="postpartum_hypertension_risk",
                severity="critical",
                message="Severely elevated blood pressure: urgent clinical assessment is required.",
                evidence=evidence,
            )
        ]

    is_elevated = (
        (systolic is not None and systolic >= policy["elevated_systolic_mm_hg"])
        or (diastolic is not None and diastolic >= policy["elevated_diastolic_mm_hg"])
    )
    if is_elevated:
        return [
            AlertCandidate(
                rule_id="postpartum_hypertension_risk",
                severity="warning",
                message="Elevated blood pressure: assess for a postpartum hypertensive disorder.",
                evidence=evidence,
            )
        ]
    return []


def _evaluate_postpartum_hemorrhage(reading: Mapping[str, Any]) -> list[AlertCandidate]:
    blood_loss = reading.get("blood_loss_ml")
    bleeding_reported = reading.get("bleeding_reported", False)
    if blood_loss is None and not bleeding_reported:
        return []

    policy = POLICY["postpartum_hemorrhage"]
    heart_rate = reading.get("heart_rate_bpm")
    systolic = reading.get("systolic_bp")
    shock_index = heart_rate / systolic if heart_rate is not None and systolic not in (None, 0) else None
    abnormal_vitals = (
        (heart_rate is not None and heart_rate >= policy["tachycardia_bpm"])
        or (systolic is not None and systolic <= policy["low_systolic_mm_hg"])
        or (shock_index is not None and shock_index >= policy["shock_index"])
    )
    is_critical_loss = blood_loss is not None and blood_loss >= policy["critical_blood_loss_ml"]
    is_early_loss_with_instability = (
        blood_loss is not None
        and blood_loss >= policy["early_blood_loss_ml"]
        and abnormal_vitals
    )
    is_reported_bleeding_with_instability = bleeding_reported and abnormal_vitals
    if not (is_critical_loss or is_early_loss_with_instability or is_reported_bleeding_with_instability):
        return []
    return [
        AlertCandidate(
            rule_id="postpartum_hemorrhage_risk",
            severity="critical",
            message="Possible postpartum haemorrhage: urgent clinical assessment is required.",
            evidence={
                "blood_loss_ml": blood_loss,
                "bleeding_reported": bleeding_reported,
                "heart_rate_bpm": heart_rate,
                "systolic_bp": systolic,
                "shock_index": round(shock_index, 3) if shock_index is not None else None,
            },
        )
    ]


def _evaluate_fall(reading: Mapping[str, Any]) -> list[AlertCandidate]:
    motion = reading.get("motion") or {}
    if not isinstance(motion, Mapping):
        return []
    if motion.get("fall_detected") is True:
        return [
            AlertCandidate(
                rule_id="fall_detected",
                severity="critical",
                message="Possible fall detected: contact the mother and assess urgently.",
                evidence={"source": "device_classifier", "motion": dict(motion)},
            )
        ]

    policy = POLICY["fall"]
    impact = motion.get("impact_g")
    orientation = motion.get("orientation_change_degrees")
    immobile_seconds = motion.get("post_impact_immobile_seconds")
    has_raw_fall_pattern = (
        impact is not None
        and orientation is not None
        and immobile_seconds is not None
        and impact >= policy["impact_g"]
        and orientation >= policy["orientation_change_degrees"]
        and immobile_seconds >= policy["post_impact_immobile_seconds"]
    )
    if not has_raw_fall_pattern:
        return []
    return [
        AlertCandidate(
            rule_id="fall_detected",
            severity="critical",
            message="Possible fall detected: contact the mother and assess urgently.",
            evidence={"source": "impact_orientation_immobility", "motion": dict(motion)},
        )
    ]


def highest_severity(candidates: list[AlertCandidate]) -> str | None:
    """Return the most urgent candidate severity without relying on enum order."""
    severity_order = {"critical": 3, "warning": 2, "info": 1}
    return max((candidate.severity for candidate in candidates), key=severity_order.get, default=None)
