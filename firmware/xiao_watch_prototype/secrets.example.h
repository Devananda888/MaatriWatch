// Copy this file to secrets.h. secrets.h is ignored by Git.
#pragma once

// First-boot Wi-Fi fallback. If no saved Wi-Fi works, the watch creates a
// protected MaatriWatch-xxxxxx setup network.
#define WIFI_SSID "hospital-wifi-name"
#define WIFI_PASSWORD "replace-with-wifi-password"

// Select exactly one telemetry path:
//   0 = the existing authenticated MaatriWatch API (recommended)
//   1 = direct Firebase Realtime Database prototype transport
//
// Direct Firebase mode is a presentation/prototype transport only. It writes
// the latest live reading; it does not create the durable Postgres history,
// clinician REST records, alert workflow, or patient-detail trend graph.
#define TELEMETRY_TRANSPORT_FIREBASE 0

// Stable, non-secret ID issued to this physical watch. Keep it the same when
// changing the transport. It must not be a patient name, email, or phone.
#define DEVICE_ID "00000000-0000-0000-0000-000000000000"

#if TELEMETRY_TRANSPORT_FIREBASE
// Create one Firebase Email/Password account PER watch. Store that account's
// credentials only in this ignored local file. Never put a Firebase service
// account JSON/private key in an ESP32 firmware image.
#define FIREBASE_WEB_API_KEY "replace-with-firebase-web-api-key"
#define FIREBASE_DATABASE_URL "https://your-project-default-rtdb.region.firebasedatabase.app"
#define FIREBASE_DEVICE_EMAIL "replace-with-watch-account@example.invalid"
#define FIREBASE_DEVICE_PASSWORD "replace-with-unique-watch-password"

// These are UUIDs, not secrets. They select the existing live dashboard node.
// Firebase rules must also bind the signed-in device account to this exact
// hospital/patient/device assignment before permitting a write.
#define FIREBASE_HOSPITAL_ID "00000000-0000-0000-0000-000000000000"
#define FIREBASE_PATIENT_ID "00000000-0000-0000-0000-000000000000"

// Paste the Google Trust Services root CA used by the Firebase endpoints.
// Keep TLS validation enabled; never call WiFiClientSecure::setInsecure().
static const char FIREBASE_CA_CERT[] = R"EOF(
-----BEGIN CERTIFICATE-----
replace-with-google-trust-services-root-ca
-----END CERTIFICATE-----
)EOF";
#else
// Existing deployed MaatriWatch ingestion endpoint and this watch's unique
// hospital-issued credentials. Never reuse DEVICE_KEY on another watch.
#define API_URL "https://your-api.example/api/v1/ingest/telemetry"
#define DEVICE_KEY "replace-with-once-shown-device-key"

// Paste the PEM root CA that validates API_URL. Certificate validation remains
// enabled; never replace it with WiFiClientSecure::setInsecure().
static const char API_CA_CERT[] = R"EOF(
-----BEGIN CERTIFICATE-----
replace-with-api-root-ca
-----END CERTIFICATE-----
)EOF";
#endif

// Use separate, unique, 12+ character passwords. The first protects the
// Wi-Fi setup portal; the second protects local-network firmware uploads.
#define PROVISIONING_PASSWORD "replace-with-setup-password"
#define OTA_PASSWORD "replace-with-ota-password"
