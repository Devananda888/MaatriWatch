import unittest

from app.config import Config


class ProductionConfigTest(unittest.TestCase):
    def test_production_configuration_rejects_development_secret(self):
        original = {
            "IS_PRODUCTION": Config.IS_PRODUCTION,
            "DATABASE_URL": Config.DATABASE_URL,
            "FIREBASE_PROJECT_ID": Config.FIREBASE_PROJECT_ID,
            "FIREBASE_SERVICE_ACCOUNT_JSON": Config.FIREBASE_SERVICE_ACCOUNT_JSON,
            "FIREBASE_DATABASE_URL": Config.FIREBASE_DATABASE_URL,
            "SECRET_KEY": Config.SECRET_KEY,
            "CORS_ALLOWED_ORIGINS": Config.CORS_ALLOWED_ORIGINS,
            "DEMO_MODE": Config.DEMO_MODE,
            "DEMO_IN_MEMORY": Config.DEMO_IN_MEMORY,
        }
        try:
            Config.IS_PRODUCTION = True
            Config.DATABASE_URL = "postgresql://configured"
            Config.FIREBASE_PROJECT_ID = "project"
            Config.FIREBASE_SERVICE_ACCOUNT_JSON = "{}"
            Config.FIREBASE_DATABASE_URL = "https://project.firebaseio.com"
            Config.SECRET_KEY = "development-only-change-me"
            Config.CORS_ALLOWED_ORIGINS = ("https://dashboard.example",)
            Config.DEMO_MODE = False
            Config.DEMO_IN_MEMORY = False
            self.assertIn("SECRET_KEY", Config.production_configuration_errors())
        finally:
            for name, value in original.items():
                setattr(Config, name, value)


if __name__ == "__main__":
    unittest.main()
