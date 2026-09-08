# MaatriWatch patient companion

Android-first patient application for a hospital-provisioned MaatriWatch
account. It uses Firebase Authentication and the Flask API. It does not start
with a demo patient or a localhost service fallback.

## Safety boundary

- MAX30102 values are presented only as wearable heart-rate and SpO2 readings.
- A wearable temperature is labelled skin-adjacent/device temperature. It is
  not body temperature and does not indicate fever.
- Blood pressure is shown only when the API identifies a validated cuff,
  clinician-entered, or other validated-device source.
- An SOS asks the configured care team for help. It is not a substitute for
  calling local emergency services.

## Local development

Run flutter pub get from this folder. Supply public Firebase client settings
and an API_BASE_URL as dart defines when running Flutter.

Required settings: API_BASE_URL, FIREBASE_API_KEY, FIREBASE_PROJECT_ID,
FIREBASE_MESSAGING_SENDER_ID, FIREBASE_ANDROID_APP_ID,
FIREBASE_AUTH_DOMAIN, and FIREBASE_DATABASE_URL. Web testing additionally
uses FIREBASE_WEB_APP_ID; iOS builds use FIREBASE_IOS_APP_ID.

For a release build, API_BASE_URL must use HTTPS. The required Android app ID
is the Firebase Android application's public app ID, not a service-account
credential. Never place a Firebase Admin JSON file, API secret, or backend
database URL in this application.

The account must be provisioned in Firebase Auth and linked by a hospital
administrator to an active patient record in PostgreSQL. Email verification is
required before the patient home can open.

## Build commands

For local Android testing, use an HTTPS deployment URL when testing a real
release path (a local HTTP URL is accepted only by a debug build):

```text
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1 --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_MESSAGING_SENDER_ID=... --dart-define=FIREBASE_ANDROID_APP_ID=... --dart-define=FIREBASE_AUTH_DOMAIN=... --dart-define=FIREBASE_DATABASE_URL=...
```

For an Android release artifact, supply public Firebase client values and an
HTTPS API URL with the same defines:

```text
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.production-domain.tld/api/v1 --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_MESSAGING_SENDER_ID=... --dart-define=FIREBASE_ANDROID_APP_ID=... --dart-define=FIREBASE_AUTH_DOMAIN=... --dart-define=FIREBASE_DATABASE_URL=...
```
