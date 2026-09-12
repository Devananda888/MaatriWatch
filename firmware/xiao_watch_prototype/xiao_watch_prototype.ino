/*
  MaatriWatch XIAO ESP32-S3 wearable firmware

  Fixed wiring
    D4/GPIO5  -> SDA on OLED, MAX30102, TMP117, MPU6050
    D5/GPIO6  -> SCL on OLED, MAX30102, TMP117, MPU6050
    D0/GPIO1  -> momentary SOS button; other button terminal -> GND
    BAT+/BAT- -> protected 3.7 V LiPo (positive passes through slide switch)

  Required Library Manager libraries:
    WiFiManager by tzapu; Adafruit GFX; Adafruit SSD1306; Adafruit TMP117;
    Adafruit MPU6050; Adafruit Unified Sensor; SparkFun MAX3010x Pulse and
    Proximity Sensor Library.

  Clinical boundary: this build uploads only PPG-derived HR/SpO2 (when fresh),
  TMP117 skin-adjacent/device temperature, non-diagnostic motion context, and
  a deliberate SOS. It has no blood-pressure or diagnosis algorithm.
*/

#include <ArduinoOTA.h>
#include <ctype.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <WiFiManager.h>
#include <Wire.h>
#include <time.h>

#include <Adafruit_GFX.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_TMP117.h>
#include <MAX30105.h>
#include <heartRate.h>
#include <spo2_algorithm.h>

#include "secrets.h"

#ifndef TELEMETRY_TRANSPORT_FIREBASE
#define TELEMETRY_TRANSPORT_FIREBASE 0
#endif

#ifndef WIFI_SSID
#error "Create secrets.h from secrets.example.h and set WIFI_SSID."
#endif
#ifndef WIFI_PASSWORD
#error "Create secrets.h from secrets.example.h and set WIFI_PASSWORD."
#endif
#ifndef DEVICE_ID
#error "Create secrets.h from secrets.example.h and set DEVICE_ID."
#endif
#ifndef PROVISIONING_PASSWORD
#error "Set PROVISIONING_PASSWORD in secrets.h."
#endif

#if TELEMETRY_TRANSPORT_FIREBASE
#ifndef FIREBASE_WEB_API_KEY
#error "Set FIREBASE_WEB_API_KEY in secrets.h when direct Firebase transport is enabled."
#endif
#ifndef FIREBASE_DATABASE_URL
#error "Set FIREBASE_DATABASE_URL in secrets.h when direct Firebase transport is enabled."
#endif
#ifndef FIREBASE_DEVICE_EMAIL
#error "Set FIREBASE_DEVICE_EMAIL in secrets.h when direct Firebase transport is enabled."
#endif
#ifndef FIREBASE_DEVICE_PASSWORD
#error "Set FIREBASE_DEVICE_PASSWORD in secrets.h when direct Firebase transport is enabled."
#endif
#ifndef FIREBASE_HOSPITAL_ID
#error "Set FIREBASE_HOSPITAL_ID in secrets.h when direct Firebase transport is enabled."
#endif
#ifndef FIREBASE_PATIENT_ID
#error "Set FIREBASE_PATIENT_ID in secrets.h when direct Firebase transport is enabled."
#endif
#else
#ifndef API_URL
#error "Create secrets.h from secrets.example.h and set API_URL."
#endif
#ifndef DEVICE_KEY
#error "Create secrets.h from secrets.example.h and set DEVICE_KEY."
#endif
#endif

constexpr char FIRMWARE_VERSION[] = "mw-xiao-1.1.0";
constexpr uint8_t SDA_PIN = D4;
constexpr uint8_t SCL_PIN = D5;
constexpr uint8_t SOS_BUTTON_PIN = D0;
constexpr uint8_t OLED_ADDRESS = 0x3C;
constexpr uint8_t TMP117_ADDRESS = 0x48;
constexpr uint8_t MAX30102_ADDRESS = 0x57;
constexpr uint8_t MPU6050_PRIMARY = 0x68;
constexpr uint8_t MPU6050_SECONDARY = 0x69;

constexpr uint32_t OLED_INTERVAL_MS = 250;
constexpr uint32_t TEMP_INTERVAL_MS = 2000;
constexpr uint32_t MOTION_INTERVAL_MS = 200;
constexpr uint32_t TELEMETRY_INTERVAL_MS = 15000;
constexpr uint32_t WIFI_RETRY_INTERVAL_MS = 30000;
constexpr uint32_t SOS_HOLD_MS = 2000;
constexpr uint32_t BUTTON_DEBOUNCE_MS = 35;
constexpr uint32_t TAP_MAX_MS = 500;
constexpr uint32_t TAP_WINDOW_MS = 3500;
constexpr uint8_t PORTAL_TAP_COUNT = 5;
constexpr uint32_t HR_FRESH_MS = 12000;
constexpr uint32_t SPO2_FRESH_MS = 12000;
constexpr uint32_t SPO2_SAMPLE_INTERVAL_MS = 40;  // 100 values over 4 s
constexpr uint8_t SPO2_WINDOW_SAMPLES = 100;
constexpr uint8_t HR_AVERAGE_BEATS = 5;
constexpr uint32_t MIN_IR_CONTACT = 10000;
constexpr float MIN_PI_PERCENT = 0.20f;

Adafruit_SSD1306 display(128, 64, &Wire, -1);
Adafruit_TMP117 tmp117;
Adafruit_MPU6050 mpu;
MAX30105 max30102;
WiFiClientSecure apiClient;
#if TELEMETRY_TRANSPORT_FIREBASE
WiFiClientSecure firebaseClient;
String firebaseIdToken, firebaseRefreshToken;
uint32_t firebaseTokenReceivedAt = 0, firebaseTokenLifetimeMs = 0;
#endif
Preferences preferences;

bool oledReady = false, tmpReady = false, mpuReady = false, maxReady = false;
bool fingerContact = false, otaReady = false, sosQueued = false, sosSentForPress = false;
bool lastButtonRaw = false, buttonPressed = false;
float skinTemperatureC = NAN, dynamicAccelerationG = NAN, orientationDelta = NAN;
float previousPitch = NAN, ppgQuality = 0.0f, perfusionIndex = NAN;
float heartRateBpm = NAN, spo2Percent = NAN;
uint32_t lastTempAt = 0, lastMotionAt = 0, lastOledAt = 0, lastUploadAt = 0;
uint32_t lastWifiRetryAt = 0, lastNtpAttemptAt = 0, buttonChangedAt = 0, buttonDownAt = 0;
uint32_t lastTapAt = 0, lastBeatAt = 0, lastHrAt = 0, lastSpo2At = 0, lastSpo2StoreAt = 0;
uint32_t bootNonce = 0, sourceSequence = 0;
uint8_t tapCount = 0, ppgCount = 0, hrCount = 0, hrIndex = 0;
uint32_t irBuffer[SPO2_WINDOW_SAMPLES] = {};
uint32_t redBuffer[SPO2_WINDOW_SAMPLES] = {};
float hrBuffer[HR_AVERAGE_BEATS] = {};
String statusLine = "Starting";

bool isPlaceholder(const char *value) {
  if (value == nullptr || !value[0]) return true;
  String text(value); text.toLowerCase();
  return text.indexOf("replace") >= 0 || text.indexOf("your-") >= 0 ||
         text.indexOf("example") >= 0 || text.indexOf("change-me") >= 0;
}

bool cloudConfigIsSafe() {
#if TELEMETRY_TRANSPORT_FIREBASE
  return String(FIREBASE_DATABASE_URL).startsWith("https://") &&
         !isPlaceholder(FIREBASE_DATABASE_URL) &&
         !isPlaceholder(FIREBASE_WEB_API_KEY) &&
         !isPlaceholder(FIREBASE_DEVICE_EMAIL) &&
         !isPlaceholder(FIREBASE_DEVICE_PASSWORD) &&
         !isPlaceholder(FIREBASE_HOSPITAL_ID) && !isPlaceholder(FIREBASE_PATIENT_ID) &&
         !isPlaceholder(DEVICE_ID) &&
         strstr(FIREBASE_CA_CERT, "BEGIN CERTIFICATE") != nullptr &&
         strstr(FIREBASE_CA_CERT, "replace-with") == nullptr;
#else
  return String(API_URL).startsWith("https://") && !isPlaceholder(API_URL) &&
         !isPlaceholder(DEVICE_ID) && !isPlaceholder(DEVICE_KEY) &&
         strstr(API_CA_CERT, "BEGIN CERTIFICATE") != nullptr &&
         strstr(API_CA_CERT, "replace-with") == nullptr;
#endif
}

bool i2cPresent(uint8_t address) {
  Wire.beginTransmission(address);
  return Wire.endTransmission() == 0;
}

void bootScreen(const char *first, const char *second = "") {
  if (!oledReady) return;
  display.clearDisplay(); display.setTextColor(SSD1306_WHITE); display.setTextSize(1);
  display.setCursor(0, 0); display.println("MaatriWatch"); display.println(FIRMWARE_VERSION);
  display.println(); display.println(first); display.println(second); display.display();
}

void scanI2c() {
  Serial.println("I2C scan:");
  for (uint8_t address = 1; address < 127; ++address) {
    if (i2cPresent(address)) Serial.printf("  found 0x%02X\n", address);
  }
}

void initialiseSensors() {
  if (i2cPresent(OLED_ADDRESS)) {
    oledReady = display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS);
    if (oledReady) bootScreen("Initialising sensors");
  }
  if (i2cPresent(TMP117_ADDRESS)) tmpReady = tmp117.begin(TMP117_ADDRESS, &Wire);
  const uint8_t mpuAddress = i2cPresent(MPU6050_PRIMARY) ? MPU6050_PRIMARY : MPU6050_SECONDARY;
  if (i2cPresent(mpuAddress)) {
    mpuReady = mpu.begin(mpuAddress, &Wire, 0);
    if (mpuReady) {
      mpu.setAccelerometerRange(MPU6050_RANGE_4_G);
      mpu.setGyroRange(MPU6050_RANGE_500_DEG);
      mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
    }
  }
  if (i2cPresent(MAX30102_ADDRESS)) {
    maxReady = max30102.begin(Wire, I2C_SPEED_FAST);
    if (maxReady) {
      // Conservative LED current, Red+IR mode, 100 samples/sec.
      max30102.setup(0x24, 4, 2, 100, 411, 4096);
      max30102.setPulseAmplitudeGreen(0);
    }
  }
  Serial.printf("OLED=%s TMP117=%s MPU6050=%s MAX30102=%s\n",
                oledReady ? "ok" : "missing", tmpReady ? "ok" : "missing",
                mpuReady ? "ok" : "missing", maxReady ? "ok" : "missing");
}

bool waitForWifi(uint32_t timeout) {
  const uint32_t started = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - started < timeout) delay(50);
  return WiFi.status() == WL_CONNECTED;
}

bool startWifiPortal() {
  WiFiManager manager;
  manager.setConfigPortalTimeout(180);
  manager.setConnectTimeout(20);
  const String name = "MaatriWatch-" + String((uint32_t)(ESP.getEfuseMac() & 0xFFFFFF), HEX);
  statusLine = "WiFi setup"; bootScreen("WiFi setup", name.c_str());
  const bool connected = manager.startConfigPortal(name.c_str(), PROVISIONING_PASSWORD);
  if (connected) {
    preferences.begin("mw-watch", false); preferences.remove("forcePortal"); preferences.end();
    Serial.printf("WiFi connected: %s\n", WiFi.localIP().toString().c_str());
  }
  return connected;
}

void initialiseWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  preferences.begin("mw-watch", true);
  const bool forcePortal = preferences.getBool("forcePortal", false);
  preferences.end();
  if (forcePortal) { startWifiPortal(); return; }
  // Prefer a network entered through the captive portal, then the initial
  // hospital credential stored in secrets.h.
  WiFi.begin();
  if (waitForWifi(8000)) return;
  if (!isPlaceholder(WIFI_SSID) && !isPlaceholder(WIFI_PASSWORD)) {
    WiFi.disconnect(false, false); WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    if (waitForWifi(12000)) return;
  }
  startWifiPortal();
}

bool clockReady() { return time(nullptr) > 1700000000; }

void ensureClock() {
  if (WiFi.status() != WL_CONNECTED || clockReady() || millis() - lastNtpAttemptAt < 15000) return;
  lastNtpAttemptAt = millis();
  configTime(0, 0, "time.cloudflare.com", "pool.ntp.org", "time.nist.gov");
  statusLine = "Syncing time";
}

String timestampUtc() {
  time_t now = time(nullptr); struct tm value; gmtime_r(&now, &value);
  char result[25]; strftime(result, sizeof(result), "%Y-%m-%dT%H:%M:%SZ", &value);
  return String(result);
}

void initialiseOta() {
  if (otaReady || WiFi.status() != WL_CONNECTED) return;
#if defined(OTA_PASSWORD)
  if (strlen(OTA_PASSWORD) < 12 || isPlaceholder(OTA_PASSWORD)) {
    Serial.println("OTA disabled: set a unique 12+ character OTA_PASSWORD.");
    return;
  }
  const String host = "maatriwatch-" + String((uint32_t)(ESP.getEfuseMac() & 0xFFFFFF), HEX);
  ArduinoOTA.setHostname(host.c_str()); ArduinoOTA.setPassword(OTA_PASSWORD);
  ArduinoOTA.onStart([]() { statusLine = "OTA updating"; Serial.println("OTA started"); });
  ArduinoOTA.onEnd([]() { Serial.println("OTA complete; restarting"); });
  ArduinoOTA.onError([](ota_error_t error) { Serial.printf("OTA error %u\n", error); });
  ArduinoOTA.begin(); otaReady = true;
  Serial.printf("OTA: %s.local / %s\n", host.c_str(), WiFi.localIP().toString().c_str());
#else
  Serial.println("OTA disabled: add OTA_PASSWORD to secrets.h.");
#endif
}

void readTemperature() {
  if (!tmpReady) return;
  sensors_event_t event; tmp117.getEvent(&event);
  if (!isnan(event.temperature) && event.temperature > -40 && event.temperature < 125) skinTemperatureC = event.temperature;
}

void readMotion() {
  if (!mpuReady) return;
  sensors_event_t acceleration, gyro, unusedTemperature;
  mpu.getEvent(&acceleration, &gyro, &unusedTemperature);
  const float ax = acceleration.acceleration.x / SENSORS_GRAVITY_STANDARD;
  const float ay = acceleration.acceleration.y / SENSORS_GRAVITY_STANDARD;
  const float az = acceleration.acceleration.z / SENSORS_GRAVITY_STANDARD;
  dynamicAccelerationG = fabsf(sqrtf(ax * ax + ay * ay + az * az) - 1.0f);
  const float pitch = atan2f(-ax, sqrtf(ay * ay + az * az)) * 180.0f / PI;
  if (!isnan(previousPitch)) orientationDelta = fabsf(pitch - previousPitch);
  previousPitch = pitch;
}

void clearPpg() {
  ppgCount = 0; hrCount = 0; hrIndex = 0; lastBeatAt = 0; lastHrAt = 0; lastSpo2At = 0;
  lastSpo2StoreAt = 0; heartRateBpm = NAN; spo2Percent = NAN; perfusionIndex = NAN; ppgQuality = 0;
}

void recordHeartRate(float bpm) {
  hrBuffer[hrIndex] = bpm; hrIndex = (hrIndex + 1) % HR_AVERAGE_BEATS;
  if (hrCount < HR_AVERAGE_BEATS) ++hrCount;
  float total = 0; for (uint8_t i = 0; i < hrCount; ++i) total += hrBuffer[i];
  heartRateBpm = total / hrCount; lastHrAt = millis();
}

void computeSpo2() {
  uint64_t total = 0; uint32_t minimum = UINT32_MAX, maximum = 0;
  for (uint8_t i = 0; i < SPO2_WINDOW_SAMPLES; ++i) {
    total += irBuffer[i]; minimum = min(minimum, irBuffer[i]); maximum = max(maximum, irBuffer[i]);
  }
  const float mean = (float)total / SPO2_WINDOW_SAMPLES;
  perfusionIndex = mean > 0 ? 100.0f * ((float)(maximum - minimum) / (2.0f * mean)) : NAN;
  ppgQuality = isnan(perfusionIndex) ? 0 : constrain(perfusionIndex / 1.0f, 0.0f, 1.0f);
  int32_t spo2 = 0, algorithmHr = 0; int8_t spo2Valid = 0, algorithmHrValid = 0;
  maxim_heart_rate_and_oxygen_saturation(irBuffer, SPO2_WINDOW_SAMPLES, redBuffer,
                                         &spo2, &spo2Valid, &algorithmHr, &algorithmHrValid);
  if (spo2Valid == 1 && spo2 >= 70 && spo2 <= 100 && perfusionIndex >= MIN_PI_PERCENT) {
    spo2Percent = (float)spo2; lastSpo2At = millis();
  }
  // The same Maxim PPG window produces a heart-rate estimate. It is used only
  // when the library marks it valid and is inside the signal plausibility gate.
  // This is a fallback when the beat-edge helper has not accumulated enough
  // intervals yet; it remains a PPG-derived prototype value.
  if (algorithmHrValid == 1 && algorithmHr >= 40 && algorithmHr <= 220 &&
      perfusionIndex >= MIN_PI_PERCENT) {
    heartRateBpm = (float)algorithmHr;
    hrCount = HR_AVERAGE_BEATS;
    lastHrAt = millis();
  }
  Serial.printf("PPG window: spo2=%ld valid=%d hr=%ld valid=%d pi=%.2f\n",
                (long)spo2, spo2Valid, (long)algorithmHr, algorithmHrValid,
                perfusionIndex);
  ppgCount = 0;
}

void readPpg() {
  if (!maxReady) return;
  max30102.check();
  while (max30102.available()) {
    const uint32_t ir = max30102.getIR(), red = max30102.getRed(), now = millis();
    if (ir < MIN_IR_CONTACT) {
      if (fingerContact) { Serial.println("PPG contact lost"); clearPpg(); }
      fingerContact = false; max30102.nextSample(); continue;
    }
    if (!fingerContact) { fingerContact = true; clearPpg(); Serial.println("PPG stabilising"); }
    if (checkForBeat(ir)) {
      if (lastBeatAt) {
        const uint32_t interval = now - lastBeatAt;
        if (interval >= 270 && interval <= 1500) {
          const float bpm = 60000.0f / interval;
          if (bpm >= 40 && bpm <= 220) recordHeartRate(bpm);
        }
      }
      lastBeatAt = now;
    }
    if (now - lastSpo2StoreAt >= SPO2_SAMPLE_INTERVAL_MS) {
      lastSpo2StoreAt = now;
      irBuffer[ppgCount] = ir; redBuffer[ppgCount] = red;
      if (++ppgCount == SPO2_WINDOW_SAMPLES) computeSpo2();
    }
    max30102.nextSample();
  }
}

bool freshHr() { return fingerContact && hrCount >= 3 && !isnan(heartRateBpm) && millis() - lastHrAt <= HR_FRESH_MS; }
bool freshSpo2() { return fingerContact && !isnan(spo2Percent) && millis() - lastSpo2At <= SPO2_FRESH_MS; }

const char *healthState() {
  // MPU6050 movement context is optional and non-clinical. Do not turn a
  // working PPG/temperature watch into a sensor_error merely because motion
  // context is unavailable; the backend would correctly suppress PPG values
  // for a real optical/temperature sensor failure.
  if (!tmpReady || !maxReady) return "sensor_error";
  if (!fingerContact) return "contact_lost";
  return freshHr() && freshSpo2() ? "ok" : "unavailable";
}

void requestSetupPortal() {
  preferences.begin("mw-watch", false); preferences.putBool("forcePortal", true); preferences.end();
  statusLine = "WiFi reset"; bootScreen("WiFi setup next", "Restarting"); delay(250); ESP.restart();
}

void setSosQueued(bool value) {
  sosQueued = value;
  // A brief network outage or battery restart must not silently discard a
  // deliberate request for help. The next successful telemetry upload clears it.
  preferences.begin("mw-watch", false);
  if (value) preferences.putBool("pendingSos", true);
  else preferences.remove("pendingSos");
  preferences.end();
}

void serviceButton() {
  const uint32_t now = millis(); const bool rawPressed = digitalRead(SOS_BUTTON_PIN) == LOW;
  if (rawPressed != lastButtonRaw) { lastButtonRaw = rawPressed; buttonChangedAt = now; }
  if (now - buttonChangedAt >= BUTTON_DEBOUNCE_MS && rawPressed != buttonPressed) {
    buttonPressed = rawPressed;
    if (buttonPressed) { buttonDownAt = now; sosSentForPress = false; }
    else {
      const uint32_t held = now - buttonDownAt;
      if (!sosSentForPress && held <= TAP_MAX_MS) {
        if (now - lastTapAt > TAP_WINDOW_MS) tapCount = 0;
        lastTapAt = now;
        if (++tapCount >= PORTAL_TAP_COUNT) requestSetupPortal();
      } else tapCount = 0;
    }
  }
  if (buttonPressed && !sosSentForPress && now - buttonDownAt >= SOS_HOLD_MS) {
    sosSentForPress = true; setSosQueued(true); statusLine = "SOS queued";
    Serial.println("SOS held; request queued.");
  }
}

String numberOrNull(float value, unsigned int precision) {
  return isnan(value) ? "null" : String(value, precision);
}

String makeTelemetry(bool sos, const String &eventId, uint32_t sequence) {
  String body; body.reserve(720);
  body += "{\"event_id\":\"" + eventId + "\",\"source_sequence\":" + String(sequence);
  body += ",\"captured_at\":\"" + timestampUtc() + "\",\"heart_rate_bpm\":";
  body += freshHr() ? String((int)lroundf(heartRateBpm)) : "null";
  body += ",\"spo2_percent\":"; body += freshSpo2() ? String(spo2Percent, 1) : "null";
  body += ",\"temperature_c\":" + numberOrNull(skinTemperatureC, 2);
  body += ",\"contact_detected\":" + String(fingerContact ? "true" : "false");
  body += ",\"signal_quality\":" + String(ppgQuality, 2);
  body += ",\"sensor_status\":\"" + String(healthState()) + "\"";
  body += ",\"measurement_sources\":{\"heart_rate\":\"wearable_ppg\",\"spo2\":\"wearable_ppg\",\"temperature\":\"wearable_skin_adjacent\"}";
  body += ",\"motion\":{\"activity_state\":\"unknown\"";
  if (!isnan(dynamicAccelerationG)) body += ",\"impact_g\":" + String(constrain(dynamicAccelerationG, 0.0f, 20.0f), 2);
  if (!isnan(orientationDelta)) body += ",\"orientation_change_degrees\":" + String(constrain(orientationDelta, 0.0f, 180.0f), 1);
  if (sos) body += ",\"sos_pressed\":true";
  return body + "}}";
}

#if TELEMETRY_TRANSPORT_FIREBASE
String jsonEscape(const String &value) {
  String escaped; escaped.reserve(value.length() + 12);
  for (size_t index = 0; index < value.length(); ++index) {
    const char character = value[index];
    if (character == '"' || character == '\\') escaped += '\\';
    if (character == '\n') escaped += "\\n";
    else if (character == '\r') escaped += "\\r";
    else if (character == '\t') escaped += "\\t";
    else if (character != '\n' && character != '\r' && character != '\t') escaped += character;
  }
  return escaped;
}

String urlEncode(const String &value) {
  static const char hex[] = "0123456789ABCDEF";
  String encoded; encoded.reserve(value.length() * 3);
  for (size_t index = 0; index < value.length(); ++index) {
    const uint8_t character = static_cast<uint8_t>(value[index]);
    if ((character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') ||
        (character >= '0' && character <= '9') || character == '-' || character == '_' || character == '.' || character == '~') {
      encoded += static_cast<char>(character);
    } else {
      encoded += '%'; encoded += hex[(character >> 4) & 0x0F]; encoded += hex[character & 0x0F];
    }
  }
  return encoded;
}

String jsonStringValue(const String &body, const char *name) {
  const String key = "\"" + String(name) + "\"";
  int cursor = body.indexOf(key);
  if (cursor < 0) return "";
  cursor = body.indexOf(':', cursor + key.length());
  if (cursor < 0) return "";
  ++cursor;
  while (cursor < (int)body.length() && isspace(static_cast<unsigned char>(body[cursor]))) ++cursor;
  if (cursor >= (int)body.length() || body[cursor] != '"') return "";
  ++cursor;
  String value;
  for (; cursor < (int)body.length(); ++cursor) {
    const char character = body[cursor];
    if (character == '\\' && cursor + 1 < (int)body.length()) {
      value += body[++cursor];
    } else if (character == '"') {
      return value;
    } else {
      value += character;
    }
  }
  return "";
}

bool firebasePost(const String &url, const String &body, const char *contentType, String &response) {
  firebaseClient.setCACert(FIREBASE_CA_CERT);
  HTTPClient request; request.setTimeout(15000);
  if (!request.begin(firebaseClient, url)) return false;
  request.addHeader("Content-Type", contentType);
  const int status = request.POST(body);
  response = status > 0 ? request.getString() : "";
  request.end();
  return status >= 200 && status < 300;
}

bool firebaseSignIn() {
  String response;
  const String url = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" + String(FIREBASE_WEB_API_KEY);
  const String body = "{\"email\":\"" + jsonEscape(FIREBASE_DEVICE_EMAIL) +
                      "\",\"password\":\"" + jsonEscape(FIREBASE_DEVICE_PASSWORD) +
                      "\",\"returnSecureToken\":true}";
  if (!firebasePost(url, body, "application/json", response)) {
    Serial.println("Firebase sign-in failed"); return false;
  }
  firebaseIdToken = jsonStringValue(response, "idToken");
  firebaseRefreshToken = jsonStringValue(response, "refreshToken");
  const uint32_t seconds = jsonStringValue(response, "expiresIn").toInt();
  if (firebaseIdToken.isEmpty() || firebaseRefreshToken.isEmpty() || seconds < 60) {
    Serial.println("Firebase sign-in returned no usable token"); return false;
  }
  firebaseTokenReceivedAt = millis();
  firebaseTokenLifetimeMs = seconds > 3600 ? 3540000UL : (seconds - 60) * 1000UL;
  Serial.println("Firebase device session established");
  return true;
}

bool firebaseRefreshSession() {
  if (firebaseRefreshToken.isEmpty()) return firebaseSignIn();
  String response;
  const String url = "https://securetoken.googleapis.com/v1/token?key=" + String(FIREBASE_WEB_API_KEY);
  const String body = "grant_type=refresh_token&refresh_token=" + urlEncode(firebaseRefreshToken);
  if (!firebasePost(url, body, "application/x-www-form-urlencoded", response)) {
    firebaseIdToken = ""; firebaseRefreshToken = ""; return firebaseSignIn();
  }
  firebaseIdToken = jsonStringValue(response, "id_token");
  firebaseRefreshToken = jsonStringValue(response, "refresh_token");
  const uint32_t seconds = jsonStringValue(response, "expires_in").toInt();
  if (firebaseIdToken.isEmpty() || firebaseRefreshToken.isEmpty() || seconds < 60) return false;
  firebaseTokenReceivedAt = millis();
  firebaseTokenLifetimeMs = seconds > 3600 ? 3540000UL : (seconds - 60) * 1000UL;
  Serial.println("Firebase device session refreshed");
  return true;
}

bool ensureFirebaseSession() {
  if (firebaseIdToken.isEmpty()) return firebaseSignIn();
  if (millis() - firebaseTokenReceivedAt >= firebaseTokenLifetimeMs) return firebaseRefreshSession();
  return true;
}

String makeFirebaseLiveReading(bool sos, const String &eventId, uint32_t sequence) {
  const String observed = timestampUtc();
  String body; body.reserve(720);
  body += "{\"device_id\":\"" + String(DEVICE_ID) + "\"";
  body += ",\"source_event_id\":\"" + jsonEscape(eventId) + "\"";
  body += ",\"source_sequence\":" + String(sequence);
  body += ",\"captured_at\":\"" + observed + "\"";
  body += ",\"observed_at\":\"" + observed + "\"";
  body += ",\"received_at\":\"" + observed + "\"";
  body += ",\"heart_rate_bpm\":" + (freshHr() ? String((int)lroundf(heartRateBpm)) : "null");
  body += ",\"spo2_percent\":" + (freshSpo2() ? String(spo2Percent, 1) : "null");
  body += ",\"skin_adjacent_temperature_c\":" + numberOrNull(skinTemperatureC, 2);
  body += ",\"contact_detected\":" + String(fingerContact ? "true" : "false");
  body += ",\"signal_quality\":" + String(ppgQuality, 2);
  body += ",\"sensor_status\":\"" + String(healthState()) + "\"";
  body += ",\"heart_rate_source\":\"wearable_ppg\"";
  body += ",\"spo2_source\":\"wearable_ppg\"";
  body += ",\"temperature_source\":\"wearable_skin_adjacent\"";
  body += ",\"freshness\":\"" + String((freshHr() && freshSpo2()) ? "current" : "unavailable") + "\"";
  body += ",\"motion\":{\"activity_state\":\"unknown\"";
  if (!isnan(dynamicAccelerationG)) body += ",\"impact_g\":" + String(constrain(dynamicAccelerationG, 0.0f, 20.0f), 2);
  if (!isnan(orientationDelta)) body += ",\"orientation_change_degrees\":" + String(constrain(orientationDelta, 0.0f, 180.0f), 1);
  if (sos) body += ",\"sos_pressed\":true";
  return body + "}}";
}

bool sendFirebaseTelemetry(bool sos, const String &eventId, uint32_t sequence) {
  if (!ensureFirebaseSession()) { statusLine = "Firebase auth failed"; return false; }
  String base(FIREBASE_DATABASE_URL);
  while (base.endsWith("/")) base.remove(base.length() - 1);
  const String url = base + "/live_vitals/" + String(FIREBASE_HOSPITAL_ID) + "/" +
                     String(FIREBASE_PATIENT_ID) + ".json?auth=" + urlEncode(firebaseIdToken);
  firebaseClient.setCACert(FIREBASE_CA_CERT);
  HTTPClient request; request.setTimeout(15000);
  if (!request.begin(firebaseClient, url)) { statusLine = "Firebase offline"; return false; }
  request.addHeader("Content-Type", "application/json");
  const int status = request.PUT(makeFirebaseLiveReading(sos, eventId, sequence));
  const String response = status > 0 ? request.getString() : "";
  request.end();
  if (status >= 200 && status < 300) {
    statusLine = sos ? "SOS sent to Firebase" : "Firebase synced";
    Serial.printf("Firebase telemetry %d: %s\n", status, eventId.c_str());
    return true;
  }
  statusLine = status > 0 ? "Firebase " + String(status) : "Firebase offline";
  Serial.printf("Firebase telemetry failed %d: %s\n", status, response.c_str());
  return false;
}
#endif

bool sendTelemetry(bool sos) {
  if (WiFi.status() != WL_CONNECTED || !clockReady() || !cloudConfigIsSafe()) return false;
  const uint32_t sequence = ++sourceSequence;
  const String eventId = String(DEVICE_ID) + ":" + String(bootNonce, HEX) + ":" + String(sequence);
#if TELEMETRY_TRANSPORT_FIREBASE
  return sendFirebaseTelemetry(sos, eventId, sequence);
#else
  apiClient.setCACert(API_CA_CERT);
  HTTPClient request; request.setTimeout(15000);
  if (!request.begin(apiClient, API_URL)) { statusLine = "API unavailable"; return false; }
  request.addHeader("Content-Type", "application/json");
  request.addHeader("X-Device-Id", DEVICE_ID); request.addHeader("X-Device-Key", DEVICE_KEY);
  request.addHeader("User-Agent", FIRMWARE_VERSION);
  const int result = request.POST(makeTelemetry(sos, eventId, sequence));
  const String response = result > 0 ? request.getString() : "";
  request.end();
  if (result == 200 || result == 201) {
    statusLine = sos ? "SOS delivered" : "Cloud synced";
    Serial.printf("Telemetry %d: %s\n", result, eventId.c_str()); return true;
  }
  statusLine = result > 0 ? "Upload " + String(result) : "Cloud offline";
  Serial.printf("Telemetry failed %d: %s\n", result, response.c_str()); return false;
#endif
}

void serviceNetwork() {
  if (WiFi.status() == WL_CONNECTED) { ensureClock(); initialiseOta(); if (otaReady) ArduinoOTA.handle(); return; }
  if (millis() - lastWifiRetryAt >= WIFI_RETRY_INTERVAL_MS) {
    lastWifiRetryAt = millis(); WiFi.reconnect(); statusLine = "Reconnecting"; Serial.println("WiFi reconnect requested");
  }
}

void maybeUpload() {
  const uint32_t now = millis();
  if (!sosQueued && now - lastUploadAt < TELEMETRY_INTERVAL_MS) return;
  if (!cloudConfigIsSafe()) { statusLine = "Config error"; return; }
  if (WiFi.status() != WL_CONNECTED) { statusLine = "WiFi offline"; return; }
  if (!clockReady()) { statusLine = "Syncing time"; return; }
  const bool sendingSos = sosQueued; lastUploadAt = now;
  if (sendTelemetry(sendingSos) && sendingSos) setSosQueued(false);
}

void drawHeart(int16_t x, int16_t y, bool full) {
  if (full) {
    display.fillCircle(x - 3, y, 3, SSD1306_WHITE); display.fillCircle(x + 3, y, 3, SSD1306_WHITE);
    display.fillTriangle(x - 6, y + 1, x + 6, y + 1, x, y + 9, SSD1306_WHITE);
  } else {
    display.drawCircle(x - 3, y, 3, SSD1306_WHITE); display.drawCircle(x + 3, y, 3, SSD1306_WHITE);
    display.drawLine(x - 6, y + 2, x, y + 9, SSD1306_WHITE); display.drawLine(x + 6, y + 2, x, y + 9, SSD1306_WHITE);
  }
}

void drawWatchFace() {
  if (!oledReady) return;
  display.clearDisplay(); display.setTextColor(SSD1306_WHITE); display.setTextSize(1);
  drawHeart(8, 4, freshHr() && ((millis() / 500) % 2 == 0));
  display.setCursor(18, 0); display.print("MaatriWatch "); display.println(WiFi.status() == WL_CONNECTED ? "WiFi" : "offline");
  display.setCursor(0, 12); display.print("PPG HR: "); freshHr() ? display.printf("%3d bpm", (int)lroundf(heartRateBpm)) : display.print("--");
  display.setCursor(0, 22); display.print("SpO2  : "); freshSpo2() ? display.printf("%3d %%", (int)lroundf(spo2Percent)) : display.print("--");
  display.setCursor(0, 32); display.print("Skin  : "); !isnan(skinTemperatureC) ? display.printf("%.1f C", skinTemperatureC) : display.print("--");
  display.setCursor(0, 42);
  if (!fingerContact) display.print("Place finger on sensor");
  else if (!freshHr() || !freshSpo2()) display.print("Keep still: stabilising");
  else display.printf("PPG quality: %d%%", (int)lroundf(ppgQuality * 100));
  display.setCursor(0, 53);
  if (buttonPressed && !sosSentForPress) {
    const uint32_t held = millis() - buttonDownAt;
    const uint32_t remaining = held >= SOS_HOLD_MS ? 0 : SOS_HOLD_MS - held;
    display.printf("Hold SOS: %lus", (unsigned long)((remaining + 999) / 1000));
  } else if (sosQueued) display.print("SOS awaiting network");
  else display.print(statusLine);
  display.display();
}

void printDiagnostics() {
  static uint32_t lastAt = 0; if (millis() - lastAt < 5000) return; lastAt = millis();
  Serial.printf("state=%s contact=%s hr=%s spo2=%s temp=%s q=%.2f pi=%.2f wifi=%s time=%s\n",
      healthState(), fingerContact ? "yes" : "no", freshHr() ? String(heartRateBpm, 1).c_str() : "--",
      freshSpo2() ? String(spo2Percent, 1).c_str() : "--", isnan(skinTemperatureC) ? "--" : String(skinTemperatureC, 2).c_str(),
      ppgQuality, perfusionIndex, WiFi.status() == WL_CONNECTED ? "connected" : "offline", clockReady() ? "synced" : "waiting");
}

void setup() {
  pinMode(SOS_BUTTON_PIN, INPUT_PULLUP); Serial.begin(115200); delay(400); bootNonce = esp_random();
  preferences.begin("mw-watch", true); sosQueued = preferences.getBool("pendingSos", false); preferences.end();
  Wire.begin(SDA_PIN, SCL_PIN); Wire.setClock(400000); scanI2c(); initialiseSensors();
  if (!cloudConfigIsSafe()) Serial.println("Cloud upload disabled: verify HTTPS endpoint, device key, and CA certificate.");
  initialiseWifi(); ensureClock(); initialiseOta();
  statusLine = WiFi.status() == WL_CONNECTED ? "Connected" : "WiFi setup needed";
  Serial.printf("%s ready; OTA=%s\n", FIRMWARE_VERSION, otaReady ? "enabled" : "disabled");
}

void loop() {
  serviceNetwork(); serviceButton();
  const uint32_t now = millis();
  if (now - lastTempAt >= TEMP_INTERVAL_MS) { lastTempAt = now; readTemperature(); }
  if (now - lastMotionAt >= MOTION_INTERVAL_MS) { lastMotionAt = now; readMotion(); }
  readPpg(); maybeUpload();
  if (now - lastOledAt >= OLED_INTERVAL_MS) { lastOledAt = now; drawWatchFace(); }
  printDiagnostics();
}
