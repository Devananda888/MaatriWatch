# Hackathon demo runbook

This is the time-boxed first-prototype mode. It preserves the production
Flask/Postgres/Firebase code paths, but enables a local in-memory fixture when
the supplied Supabase hostname is unreachable from the demo machine.

## Start the demo

Terminal 1, from `C:\MaatriWatch`:

```text
python -m flask --app app run --host 127.0.0.1 --port 8000 --no-reload
```

Terminal 2:

```text
python -m http.server 3000 --directory dashboard\build\web
```

Open `http://localhost:3000`. The role picker offers:

- **Doctor** — real Flask clinician routes with seven seeded patients,
  trend history, status chips, alert acknowledgement/resolution, and notes.
- **Patient** — simplified vitals, SOS confirmation, and a three-question
  EPDS-style check-in.
- **Hospital Admin** — a concise prototype hospital/device overview.

## Demo centerpiece: trigger a live risk signal

Keep Doctor open on the patient or alert view, then run this in Terminal 3:

```text
python scripts\trigger_demo_alert.py --scenario fall
```

Repeat with the other real Phase 2 rule paths:

```text
python scripts\trigger_demo_alert.py --scenario hypertension
python scripts\trigger_demo_alert.py --scenario pph
```

Each command posts a new HTTP device event to `/api/v1/ingest/telemetry`. In
`DEMO_IN_MEMORY=true`, that route uses the same `app.alerting.evaluate_alerts`
threshold engine as the Postgres path; the dashboard polls the Flask API every
two seconds and updates existing rows without reordering the patient list.

## When Supabase becomes reachable

Set `DEMO_IN_MEMORY=false` in the ignored `.env`, then run:

```text
python scripts\apply_migrations.py
python scripts\seed_demo.py
```

The same trigger script then uses the real Supabase-backed ingestion/outbox
workflow.

## Firebase note

The supplied web Firebase config is in `.env`, but it is not a server credential.
Secure server-to-RTDB delivery requires `FIREBASE_SERVICE_ACCOUNT_JSON` (or
valid Google application-default credentials). Do **not** enable unauthenticated
RTDB writes to work around this. Once a service account is provided, disable the
in-memory fallback and the existing transactional outbox will project live
vitals/alerts to Firebase RTDB.

## Roadmap intentionally skipped for this prototype

Twilio WhatsApp/SMS, Bhashini translation, feature-phone offline behavior,
production OTP/password enforcement, animations, and non-essential edge cases.
