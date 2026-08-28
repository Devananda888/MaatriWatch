"""MaatriWatch Flask application factory."""

from __future__ import annotations

import os

import click

from flask import Flask, jsonify, request

from .auth import auth_bp
from .clinician import clinician_bp
from .config import Config
from .db import close_db, init_db
from .firebase import init_firebase
from .ingestion import ingestion_bp
from .patient import patient_bp
from .devices import devices_bp
from .outbox import deliver_pending_outbox


def create_app(test_config: dict | None = None) -> Flask:
    app = Flask(__name__)
    app.config.from_object(Config)
    if test_config:
        app.config.update(test_config)

    init_db(app)
    init_firebase(app)
    app.teardown_appcontext(close_db)
    app.register_blueprint(auth_bp, url_prefix="/api/v1")
    app.register_blueprint(clinician_bp, url_prefix="/api/v1")
    app.register_blueprint(ingestion_bp, url_prefix="/api/v1")
    app.register_blueprint(patient_bp, url_prefix="/api/v1")
    app.register_blueprint(devices_bp, url_prefix="/api/v1")

    @app.after_request
    def protect_api_responses(response):
        """Do not cache PHI, and permit only configured dashboard origins."""
        if request.path.startswith("/api/v1/"):
            response.headers["Cache-Control"] = "no-store, max-age=0"
        origin = request.headers.get("Origin", "").rstrip("/")
        if origin and origin in app.config.get("CORS_ALLOWED_ORIGINS", ()):
            response.headers["Access-Control-Allow-Origin"] = origin
            response.headers["Access-Control-Allow-Methods"] = "GET, POST, PATCH, PUT, OPTIONS"
            response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, X-Demo-Role"
            response.headers["Access-Control-Max-Age"] = "600"
            response.headers.add("Vary", "Origin")
        return response

    @app.get("/healthz")
    def healthz():
        return jsonify({"service": "maatriwatch-api", "status": "ok"})

    @app.errorhandler(400)
    def bad_request(error):
        return jsonify({"error": "bad_request", "message": str(error.description)}), 400

    @app.errorhandler(401)
    def unauthorised(error):
        return jsonify({"error": "unauthorised", "message": str(error.description)}), 401

    @app.errorhandler(403)
    def forbidden(error):
        return jsonify({"error": "forbidden", "message": str(error.description)}), 403

    @app.errorhandler(404)
    def not_found(_error):
        return jsonify({"error": "not_found"}), 404

    @app.errorhandler(409)
    def conflict(error):
        return jsonify({"error": "conflict", "message": str(error.description)}), 409

    @app.errorhandler(413)
    def payload_too_large(_error):
        return jsonify({"error": "payload_too_large", "message": "The telemetry payload is too large"}), 413

    @app.errorhandler(503)
    def service_unavailable(error):
        return jsonify({"error": "service_unavailable", "message": str(error.description)}), 503

    @app.cli.command("drain-realtime-outbox")
    @click.option("--limit", default=100, show_default=True, type=click.IntRange(1, 1000))
    def drain_realtime_outbox(limit):
        """Deliver queued Firebase projections; run this as a separate worker process."""
        result = deliver_pending_outbox(limit)
        click.echo(f"delivered={result['delivered']} pending={result['pending']}")

    if not app.config.get("FIREBASE_AUTH_READY") and not app.config.get("DEMO_MODE"):
        app.logger.warning("Firebase Auth verification is unavailable; authenticated endpoints will reject requests.")
    if not app.config.get("FIREBASE_RTDB_READY") and not app.config.get("DEMO_MODE"):
        app.logger.warning("Firebase RTDB live sync is unavailable; durable API actions remain available when Auth is configured.")
    if not app.config.get("DATABASE_URL"):
        app.logger.warning("DATABASE_URL is not configured; database-backed endpoints will reject requests.")
    return app


# Required by `flask --app app run` and gunicorn's application factory expression.
app = create_app() if os.environ.get("FLASK_EAGER_APP") == "1" else None
