import unittest

from app import create_app
from app.patient_workflows import (
    activity_entry_input,
    care_message_input,
    clinical_profile_input,
    extract_supported_values,
    lab_result_input,
    validation_observation_input,
    wellbeing_checkin_input,
)
from werkzeug.exceptions import BadRequest


class PatientWorkflowInputTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app({"TESTING": True})

    def test_gdm_requires_complete_confirmed_75g_values(self):
        with self.app.test_request_context("/", method="POST"):
            value = lab_result_input({
                "category": "gestational_diabetes", "test_type": "75g_ogtt",
                "values": {"fasting": 94, "one_hour": 171, "two_hour": 142},
                "units": {"fasting": "mg/dL", "one_hour": "mg/dL", "two_hour": "mg/dL"},
                "trimester": 2,
            })
        self.assertEqual(value["extraction_method"], "patient_confirmed")
        self.assertEqual(value["values"]["fasting"], 94.0)

    def test_gdm_unknown_test_type_is_not_interpreted(self):
        with self.app.test_request_context("/", method="POST"):
            with self.assertRaises(BadRequest):
                lab_result_input({
                    "category": "gestational_diabetes", "test_type": "random_glucose",
                    "values": {}, "units": {},
                })

    def test_thyroid_requires_tsh_unit(self):
        with self.app.test_request_context("/", method="POST"):
            with self.assertRaises(BadRequest):
                lab_result_input({
                    "category": "thyroid", "test_type": "thyroid_function",
                    "values": {"tsh": 2.1}, "units": {"tsh": "mg/dL"},
                })

    def test_text_extraction_is_confirmation_only(self):
        with self.app.test_request_context("/", method="POST"):
            value = extract_supported_values(
                "gestational_diabetes", "Fasting: 94 mg/dL; 1 hour: 171 mg/dL; 2 hour: 142 mg/dL"
            )
        self.assertTrue(value["requires_confirmation"])
        self.assertEqual(value["values"]["one_hour"], 171.0)

    def test_five_item_checkin_is_not_a_score(self):
        with self.app.test_request_context("/", method="POST"):
            value = wellbeing_checkin_input({
                "answers": {
                    "mood": "some_days", "enjoyment": "never", "overwhelmed": "often",
                    "support": "some_days", "safety": "no",
                },
                "guardian_notification_consent": False,
            })
        self.assertFalse(value["immediate_safety_concern"])
        self.assertNotIn("score", value)

    def test_positive_safety_answer_marks_urgent_human_review(self):
        with self.app.test_request_context("/", method="POST"):
            value = wellbeing_checkin_input({
                "answers": {
                    "mood": "often", "enjoyment": "often", "overwhelmed": "often",
                    "support": "often", "safety": "yes",
                },
                "guardian_notification_consent": True,
            })
        self.assertTrue(value["immediate_safety_concern"])

    def test_profile_is_patient_reported_and_requires_boolean_history_fields(self):
        with self.app.test_request_context("/", method="PUT"):
            profile = clinical_profile_input({
                "pregnancy_stage": "second_trimester",
                "history": {
                    "previous_hypertension": False,
                    "gdm_or_diabetes_history": True,
                    "other_conditions": ["Anaemia"],
                },
                "current_medications": ["Iron supplement"],
            })
        self.assertEqual(profile["pregnancy_stage"], "second_trimester")
        self.assertTrue(profile["history"]["gdm_or_diabetes_history"])

        with self.app.test_request_context("/", method="PUT"):
            with self.assertRaises(BadRequest):
                clinical_profile_input({"history": {"previous_hypertension": "yes"}})

    def test_activity_is_a_bounded_patient_report(self):
        with self.app.test_request_context("/", method="POST"):
            entry = activity_entry_input(
                {"activity_type": "walking", "session_part": "morning", "minutes": 30}
            )
        self.assertEqual(entry["minutes"], 30)
        with self.app.test_request_context("/", method="POST"):
            with self.assertRaises(BadRequest):
                activity_entry_input({"activity_type": "walking", "session_part": "morning", "minutes": 0})

    def test_message_and_validation_inputs_are_bounded(self):
        with self.app.test_request_context("/", method="POST"):
            message = care_message_input({"body": "Could you clarify my next appointment?"})
            observation = validation_observation_input({
                "metric": "heart_rate_bpm", "wearable_value": 79,
                "reference_value": 77, "reference_device_label": "Reference pulse oximeter",
                "observation_time": "2025-01-01T10:00:00+00:00",
            })
        self.assertEqual(message["body"], "Could you clarify my next appointment?")
        self.assertEqual(observation["metric"], "heart_rate_bpm")


if __name__ == "__main__":
    unittest.main()
