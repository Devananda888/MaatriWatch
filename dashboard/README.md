# MaatriWatch clinician dashboard

Flutter web/tablet dashboard for clinician-only workflows. It uses Firebase
email/password authentication, Flask for authoritative patient records and
actions, and Firebase RTDB only for live vital/alert overlays. The browser
never receives a Firebase service-account credential and never writes RTDB.

## Run locally

Install a current Flutter SDK, then from this directory run:

```text
flutter pub get
flutter run -d chrome \
  --dart-define=API_BASE_URL=http://localhost:8000/api/v1 \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_AUTH_DOMAIN=your-project.firebaseapp.com \
  --dart-define=FIREBASE_DATABASE_URL=https://your-project-default-rtdb.firebaseio.com
```

Enable Firebase Auth email/password sign-in for clinician accounts. Provision
the matching Firebase UID in Postgres `app_users` and give it one or more
active `clinician` rows in `hospital_memberships`. The hospital selector is
intentional: a clinician may belong to more than one hospital.

Set the backend `CORS_ALLOWED_ORIGINS` to the exact local/deployed dashboard
origin, never `*`. Configure the RTDB access entitlement records described in
`../firebase/database.rules.json`; if RTDB cannot connect, the UI retains the
last Flask-loaded data and exposes an explicit retry rather than treating it as
authoritative.

## Build and host

```text
flutter build web \
  --dart-define=API_BASE_URL=https://your-api.example/api/v1 \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_AUTH_DOMAIN=your-project.firebaseapp.com \
  --dart-define=FIREBASE_DATABASE_URL=https://your-project-default-rtdb.firebaseio.com
firebase deploy --only hosting --config firebase.json
```

`firebase.json` targets `build/web`. Firebase public web options are normal
browser configuration values; the backend service-account JSON must remain
server-side only.

## Accessibility and low-connectivity behavior

- `lib/core/design_tokens.dart` is the single source of colors, spacing,
  controls, type scale, focus color, and regional Noto font fallbacks.
- `assets/fonts/README.md` lists the offline Noto family bundle expected for
  scripts across the 22-language target. No runtime font fetch is used.
- Status always combines icon, text, and color; red is reserved for critical
  alerts.
- RTDB updates modify rows in place. Only an explicit clinician sort or refresh
  changes patient-list order, so live data cannot jump the scrolling cursor.
- Failed live sync falls back to REST-loaded state with a visible notice.
