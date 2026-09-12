import unittest

from app import create_app
from app.ai_chat import _message_input, _needs_urgent_help, _output_text
from werkzeug.exceptions import BadRequest


class AssistantInputTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app({"TESTING": True})

    def test_message_is_trimmed_and_bounded(self):
        with self.app.test_request_context("/", method="POST"):
            self.assertEqual(_message_input({"message": "  Can I ask a question?  "}), "Can I ask a question?")
            with self.assertRaises(BadRequest):
                _message_input({"message": ""})
            with self.assertRaises(BadRequest):
                _message_input({"message": "x" * 801})

    def test_urgent_terms_use_the_local_safety_response(self):
        self.assertTrue(_needs_urgent_help("I have heavy bleeding and need help"))
        self.assertFalse(_needs_urgent_help("How do I prepare for my next visit?"))

    def test_response_text_uses_only_text_message_parts(self):
        payload = {
            "output": [
                {"type": "reasoning", "content": []},
                {"type": "message", "content": [
                    {"type": "output_text", "text": "A safe answer."}
                ]},
            ]
        }
        self.assertEqual(_output_text(payload), "A safe answer.")


if __name__ == "__main__":
    unittest.main()
