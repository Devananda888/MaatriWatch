import unittest

from app.alerting import evaluate_alerts, highest_severity
from app.firebase import _is_newer, _is_newer_alert


class AlertRuleTest(unittest.TestCase):
    def test_severe_bp_is_a_critical_hypertension_risk_signal(self):
        alerts = evaluate_alerts({"systolic_bp": 165, "diastolic_bp": 95})
        self.assertEqual(len(alerts), 1)
        self.assertEqual(alerts[0].rule_id, "postpartum_hypertension_risk")
        self.assertEqual(alerts[0].severity, "critical")

    def test_elevated_bp_is_warning_not_a_preeclampsia_diagnosis(self):
        alerts = evaluate_alerts({"systolic_bp": 142, "diastolic_bp": 88})
        self.assertEqual(len(alerts), 1)
        self.assertEqual(alerts[0].rule_id, "postpartum_hypertension_risk")
        self.assertEqual(alerts[0].severity, "warning")

    def test_vitals_without_a_bleeding_signal_do_not_claim_pph(self):
        alerts = evaluate_alerts({"heart_rate_bpm": 120, "systolic_bp": 85})
        self.assertFalse(any(alert.rule_id == "postpartum_hemorrhage_risk" for alert in alerts))

    def test_reported_bleeding_plus_instability_creates_pph_risk(self):
        alerts = evaluate_alerts(
            {"blood_loss_ml": 350, "heart_rate_bpm": 110, "systolic_bp": 90, "bleeding_reported": True}
        )
        pph_alert = next(alert for alert in alerts if alert.rule_id == "postpartum_hemorrhage_risk")
        self.assertEqual(pph_alert.severity, "critical")
        self.assertEqual(pph_alert.evidence["blood_loss_ml"], 350)

    def test_raw_motion_pattern_creates_fall_alert(self):
        alerts = evaluate_alerts(
            {
                "motion": {
                    "impact_g": 2.8,
                    "orientation_change_degrees": 80,
                    "post_impact_immobile_seconds": 35,
                }
            }
        )
        self.assertEqual(alerts[0].rule_id, "fall_detected")
        self.assertEqual(alerts[0].severity, "critical")

    def test_explicit_device_fall_event_is_accepted(self):
        alerts = evaluate_alerts({"motion": {"fall_detected": True}})
        self.assertEqual(alerts[0].rule_id, "fall_detected")

    def test_highest_severity_uses_explicit_order(self):
        alerts = evaluate_alerts({"systolic_bp": 165, "motion": {"fall_detected": True}})
        self.assertEqual(highest_severity(alerts), "critical")


class FirebaseProjectionOrderingTest(unittest.TestCase):
    def test_older_outbox_reading_cannot_replace_newer_live_projection(self):
        older = {"captured_at": "2026-08-14T10:12:00+00:00", "source_event_id": "boot:1"}
        newer = {"captured_at": "2026-08-14T10:12:05+00:00", "source_event_id": "boot:2"}
        self.assertFalse(_is_newer(older, newer))
        self.assertTrue(_is_newer(newer, older))

    def test_event_id_breaks_timestamp_ties_stably(self):
        first = {"captured_at": "2026-08-14T10:12:00+00:00", "source_event_id": "boot:1"}
        second = {"captured_at": "2026-08-14T10:12:00+00:00", "source_event_id": "boot:2"}
        self.assertTrue(_is_newer(second, first))

    def test_source_sequence_wins_a_same_timestamp_tie(self):
        first = {"captured_at": "2026-08-14T10:12:00+00:00", "source_event_id": "boot:9", "source_sequence": 9}
        second = {"captured_at": "2026-08-14T10:12:00+00:00", "source_event_id": "boot:10", "source_sequence": 10}
        self.assertTrue(_is_newer(second, first))

    def test_older_alert_projection_cannot_replace_newer_observation(self):
        first = {"last_seen_at": "2026-08-14T10:12:00+00:00", "occurrence_count": 1}
        second = {"last_seen_at": "2026-08-14T10:12:05+00:00", "occurrence_count": 2}
        self.assertTrue(_is_newer_alert(second, first))
        self.assertFalse(_is_newer_alert(first, second))


if __name__ == "__main__":
    unittest.main()
