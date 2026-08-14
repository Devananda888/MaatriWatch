"""Environment-backed Flask configuration."""

from __future__ import annotations

import os

from dotenv import load_dotenv

# Gunicorn and the standalone outbox worker do not automatically load `.env`.
# Deployment environments still take precedence over this local-development file.
load_dotenv()


class Config:
    SECRET_KEY = os.getenv("SECRET_KEY", "development-only-change-me")
    DATABASE_URL = os.getenv("DATABASE_URL")
    FIREBASE_PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID")
    FIREBASE_DATABASE_URL = os.getenv("FIREBASE_DATABASE_URL")
    FIREBASE_SERVICE_ACCOUNT_JSON = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
    FIREBASE_READY = False
    FIREBASE_AUTH_READY = False
    FIREBASE_RTDB_READY = False
    CORS_ALLOWED_ORIGINS = tuple(
        origin.strip().rstrip("/")
        for origin in os.getenv("CORS_ALLOWED_ORIGINS", "").split(",")
        if origin.strip()
    )
    DEMO_MODE = os.getenv("DEMO_MODE", "false").strip().lower() in {"1", "true", "yes"}
    DEMO_IN_MEMORY = os.getenv("DEMO_IN_MEMORY", "false").strip().lower() in {"1", "true", "yes"}
    JSON_SORT_KEYS = False
    MAX_CONTENT_LENGTH = int(os.getenv("MAX_CONTENT_LENGTH", "16384"))
    REALTIME_OUTBOX_BATCH_SIZE = int(os.getenv("REALTIME_OUTBOX_BATCH_SIZE", "100"))
