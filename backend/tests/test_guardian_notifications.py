import unittest

from app.guardian_notifications import send_guardian_support_request


class GuardianNotificationTest(unittest.TestCase):
    def test_does_not_send_without_complete_twilio_configuration(self):
        self.assertEqual(
            send_guardian_support_request({}, phone="+919876543210", patient_name="Test Patient"),
            "not_configured",
        )

    def test_rejects_unusable_guardian_phone_before_network_call(self):
        config = {
            "TWILIO_ACCOUNT_SID": "AC123",
            "TWILIO_AUTH_TOKEN": "token",
            "TWILIO_WHATSAPP_FROM": "whatsapp:+15551234567",
        }
        self.assertEqual(
            send_guardian_support_request(config, phone="not-a-phone", patient_name="Test Patient"),
            "failed",
        )


if __name__ == "__main__":
    unittest.main()
