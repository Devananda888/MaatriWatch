# Backend handoff and deployment

This guide is for a teammate starting from a fresh clone. It does not contain
secrets; use the deployment platform's secret/environment-variable settings.

## 1. Prerequisites

- Python 3.11+
- A managed PostgreSQL database (Supabase Postgres is supported)
- A Firebase project with **Authentication** and **Realtime Database** enabled
- Two deployment processes: one web API and one outbox worker

## 2. Local verification

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
```

Set every required value in `.env`, then apply the schema:

```powershell
python scripts\apply_migrations.py
flask --app "app:create_app()" run --host 127.0.0.1 --port 8000
```

In a second terminal, with the same environment active:

```powershell
python -m app.realtime_worker
```

`python scripts\seed_demo.py` is optional and must only be used with a
non-production database.

## 3. Firebase setup

1. Create or select the Firebase project.
2. Enable **Email/Password** sign-in in Firebase Authentication.
3. Create a Realtime Database in locked/production mode.
4. Create a service account key in Firebase project settings. Put its complete
   JSON in the deployment secret `FIREBASE_SERVICE_ACCOUNT_JSON` as one JSON
   string—never commit the file.
5. Set `FIREBASE_PROJECT_ID` and `FIREBASE_DATABASE_URL`.
6. Deploy the database rules in `backend/firebase/database.rules.json` after
   reviewing them for the production project. Server code writes the live
   projections; browser clients must never receive the service-account key.

## 4. Required environment variables

| Variable | Value |
| --- | --- |
| `DATABASE_URL` | Managed Postgres connection string, with SSL required by the provider. |
| `SECRET_KEY` | New, high-entropy random secret. |
| `FIREBASE_PROJECT_ID` | Firebase project ID. |
| `FIREBASE_DATABASE_URL` | Exact RTDB URL. |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Complete service-account JSON, stored as a platform secret. |
| `CORS_ALLOWED_ORIGINS` | Comma-separated exact HTTPS origins for the dashboard and patient web app; never `*`. |
| `DEMO_MODE` | `false` in every non-demo environment. |
| `DEMO_IN_MEMORY` | `false` in every non-demo environment. |
| `REALTIME_OUTBOX_POLL_SECONDS` | `5` is a reasonable initial value. |

Do not send these values in chat or commit `.env`/service-account files. Share
them through the deployment platform's secret manager or an approved password
manager.

## 5. Deploy

The repository's `backend/Procfile` defines the processes:

```text
web: gunicorn --bind 0.0.0.0:$PORT "app:create_app()"
worker: python -m app.realtime_worker
```

For Render/Railway/Fly, create **two services from `backend/`** using the same
environment variables:

- Web service start command: `gunicorn --bind 0.0.0.0:$PORT "app:create_app()"`
- Worker start command: `python -m app.realtime_worker`

Run `scripts/apply_migrations.py` once as a controlled release job before the
first web deployment and before deploying any migration that changes schema.

## 6. Bootstrap real accounts

Firebase Auth proves identity, but the application database decides hospital
access. A hospital administrator must provision a matching `app_users` row and
an active `hospital_memberships` row for each Firebase UID. Create a patient
row with `patients.user_id` set to the matching patient application user. Do
this with an audited admin tool or a reviewed SQL runbook; do not let browsers
choose their own hospital, role, or patient ID.

Before issuing a watch, the hospital administrator must:

1. Register its serial number through `POST /api/v1/hospitals/{hospitalId}/devices`.
2. Securely record the one-time returned `device_id` and `device_key`.
3. Flash those values into the watch's uncommitted `secrets.h`.
4. Assign it using `PATCH /api/v1/hospitals/{hospitalId}/devices/{deviceId}/assignment`.

The backend rejects device uploads while a device is unassigned. On return,
unassign it and use `POST .../rotate-key` before reissuing it.

## 7. Connect Flutter builds

Build the dashboard with its API and Firebase public web configuration:

```text
flutter build web \
  --dart-define=API_BASE_URL=https://api.example.com/api/v1 \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_AUTH_DOMAIN=your-project.firebaseapp.com \
  --dart-define=FIREBASE_DATABASE_URL=https://your-project-default-rtdb.firebaseio.com
```

The API URL must be HTTPS and match `CORS_ALLOWED_ORIGINS`. Public Firebase web
configuration is expected in a browser build; the Firebase service-account JSON
is server-only.

## 8. Production release gate

Before enrolling real patients: verify migration backup/rollback, Firebase
rules, alert delivery/acknowledgement, device secret rotation, HTTPS/TLS, logs,
database backups, consent workflow, and clinical escalation ownership. This is
not a substitute for clinical validation, security assessment, or regulatory
approval.
