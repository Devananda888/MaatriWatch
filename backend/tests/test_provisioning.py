import unittest

from werkzeug.exceptions import BadRequest, Forbidden

from app import create_app
from app.auth import require_hospital_role
from app.provisioning import _invitation_input


class InvitationInputTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app({"TESTING": True})

    def test_invitation_requires_identifying_fields_and_normalises_email(self):
        with self.app.test_request_context("/", method="POST"):
            result = _invitation_input(
                {
                    "medical_record_number": "MRN-100",
                    "full_name": "Test Patient",
                    "email": " PATIENT@EXAMPLE.ORG ",
                    "preferred_language": "ml",
                }
            )
        self.assertEqual(result["email"], "patient@example.org")
        self.assertEqual(result["preferred_language"], "ml")

    def test_invitation_rejects_malformed_email(self):
        with self.app.test_request_context("/", method="POST"):
            with self.assertRaises(BadRequest):
                _invitation_input(
                    {"medical_record_number": "MRN-100", "full_name": "Test", "email": "not-an-email"}
                )


class InvitationRbacTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app({"TESTING": True, "DEMO_MODE": True, "DEMO_IN_MEMORY": True})

    def test_patient_demo_role_cannot_use_clinician_provisioning_scope(self):
        @require_hospital_role("clinician", "hospital_admin")
        def protected(hospital_id):
            return "allowed"

        with self.app.test_request_context(
            "/", headers={"X-Demo-Role": "patient"}
        ):
            with self.assertRaises(Forbidden):
                protected(hospital_id="00000000-0000-0000-0000-000000000001")


if __name__ == "__main__":
    unittest.main()
