// Copy this file to secrets.h. Never commit secrets.h.
#pragma once

// Backend endpoint. Use HTTPS for every real deployment.
#define API_URL "https://your-api.example/api/v1/ingest/telemetry"

// Generated once by the hospital during device registration. Do not give these
// values to the patient and do not reuse them on another watch.
#define DEVICE_ID "00000000-0000-0000-0000-000000000000"
#define DEVICE_KEY "replace-with-the-once-shown-device-key"

// Password used by the hospital technician to open the first-boot Wi-Fi setup
// portal. Change it before flashing each device.
#define PROVISIONING_PASSWORD "change-this-setup-password"

// PEM root CA for the API certificate. Keep it empty only for an HTTP local-LAN
// development endpoint; production firmware must use a certificate chain.
static const char API_CA_CERT[] = R"EOF(
-----BEGIN CERTIFICATE-----
replace-with-your-root-ca
-----END CERTIFICATE-----
)EOF";
