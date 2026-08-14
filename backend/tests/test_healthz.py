import unittest

from app import create_app


class HealthEndpointTest(unittest.TestCase):
    def test_healthz_is_available_without_external_services(self):
        app = create_app({"TESTING": True})
        response = app.test_client().get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"service": "maatriwatch-api", "status": "ok"})


if __name__ == "__main__":
    unittest.main()
