# MaatriWatch XIAO ESP32-S3 final watch firmware

This is the single integrated firmware for the enclosed XIAO ESP32-S3 watch.
It uploads through the existing MaatriWatch backend; the patient and clinician
apps receive readings through that backend, not through a direct Bluetooth
connection to the patient phone.

## Fixed wiring

| XIAO ESP32-S3 | Connection |
| --- | --- |
| D4 / GPIO5 | SDA on OLED, MAX30102, TMP117, and MPU6050 |
| D5 / GPIO6 | SCL on OLED, MAX30102, TMP117, and MPU6050 |
| 3V3 | VCC/VIN on all I2C modules |
| GND | GND on all I2C modules and one push-button terminal |
| D0 / GPIO1 | Other push-button terminal |
| BAT+ | LiPo positive through the ON side of the slide switch |
| BAT- | LiPo negative directly |

Leave MAX30102 `INT`, TMP117 `ALERT`, and MPU6050 `INT` open. Do not connect
the LiPo to `3V3`, `5V`, or a sensor rail.

## Final flash

1. Select **Seeed XIAO ESP32S3** in Arduino IDE and install the seven libraries
   named at the top of the sketch.
2. Keep your existing `secrets.h` values for Wi-Fi, API URL, device ID, device
   key, and API root certificate. Add `OTA_PASSWORD` and replace the current
   weak `PROVISIONING_PASSWORD` with a unique password of at least 12
   characters. The two passwords must differ.
3. Upload once by USB, open Serial Monitor at **115200 baud**, and test all
   functions before closing the enclosure.

## Expected behaviour

- The OLED displays PPG HR, SpO2, skin-adjacent temperature, one concise
  status, and a small heartbeat animation once PPG is fresh.
- `--` is intentional: it means there is no recent quality-gated estimate.
  Removing the finger clears PPG HR/SpO2 promptly.
- The watch sends HTTPS telemetry every 15 seconds. It sends no battery
  percentage because no battery-voltage measurement is wired to the XIAO.
- Hold the button for two seconds to queue an SOS. It is delivered as soon as
  the watch is online and is a request for help, not a diagnosis.

## Wireless service after sealing the enclosure

- **Wi-Fi recovery/change:** if no saved network connects, the watch opens a
  protected `MaatriWatch-xxxxxx` Wi-Fi setup portal for three minutes. To
  force that portal while the watch is still connected to an old network,
  press and release the button **five times within 3.5 seconds**. This does
  not send an SOS.
- **Firmware updates:** on the same Wi-Fi network, Arduino IDE discovers
  `maatriwatch-xxxxxx.local` as a network port. Upload using `OTA_PASSWORD`.
  This is local wireless maintenance, not a remotely managed clinical update
  system. A production fleet needs signed releases and server-side rollout
  controls before remote updates are enabled.

## Optional direct Firebase prototype transport

The default transport remains the MaatriWatch API. It is the only path that
creates durable Postgres history, REST/dashboard refresh data, alert workflow,
and the patient-detail trend graph.

For a short presentation prototype, the firmware can instead write the newest
reading directly to Firebase Realtime Database. This can drive the dashboard's
existing live patient-row subscription, but it is **not** a replacement for the
API path: it writes no history, creates no clinical alerts, and cannot power
the detailed trend graph.

To enable it safely:

1. In Firebase Authentication, create one Email/Password user used only by
   this physical watch. Do not reuse a patient or clinician account.
2. In Firebase Realtime Database, deploy
   `backend/firebase/direct_device.rules.json` in place of the current rules.
   This keeps public access disabled and permits a watch only at the hospital
   and patient assigned to its Firebase Auth UID.
3. In the Firebase Database console, add this admin-managed mapping at
   `device_assignments/<watch-auth-uid>`:

   ```json
   {
     "hospital_id": "<existing hospital UUID>",
     "patient_id": "<existing patient UUID>",
     "device_id": "<the existing DEVICE_ID UUID>"
   }
   ```

4. In the ignored local `secrets.h`, set
   `TELEMETRY_TRANSPORT_FIREBASE` to `1`, then set
   `FIREBASE_WEB_API_KEY`, `FIREBASE_DATABASE_URL`,
   `FIREBASE_DEVICE_EMAIL`, `FIREBASE_DEVICE_PASSWORD`,
   `FIREBASE_HOSPITAL_ID`, and `FIREBASE_PATIENT_ID`. Paste the Google Trust
   Services root certificate into `FIREBASE_CA_CERT`.
5. Upload by USB or OTA. Serial Monitor should print
   `Firebase device session established`, then `Firebase telemetry 200`.

Never place a Firebase service-account key in `secrets.h`, disable Firebase
rules, or use `setInsecure()` for TLS.

## Safety boundary

MAX30102 values are prototype PPG-derived estimates only. TMP117 is reported
as skin-adjacent/device temperature, not core body temperature. The firmware
does not calculate blood pressure, claim falls, diagnose conditions, or replace
emergency services and clinician assessment.
