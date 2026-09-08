import unittest

from app import create_app


class HealthEndpointTest(unittest.TestCase):
    def test_healthz_is_available_without_external_services(self):
        app = create_app({"TESTING": True})
        response = app.test_client().get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"service": "maatriwatch-api", "status": "ok"})

    def test_readyz_reports_missing_dependencies_without_secrets(self):
        app = create_app({"TESTING": True})
        response = app.test_client().get("/readyz")
        self.assertEqual(response.status_code, 503)
        self.assertIn("database", response.get_json()["missing"])


if __name__ == "__main__":
    unittest.main()
