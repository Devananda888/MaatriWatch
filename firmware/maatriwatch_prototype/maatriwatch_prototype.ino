/*
  MaatriWatch prototype firmware — ESP32 + MAX30102 + DHT11 + SSD1306 OLED.

  Arduino Library Manager dependencies:
    - WiFiManager by tzapu
    - SparkFun MAX3010x Pulse and Proximity Sensor Library
    - DHT sensor library by Adafruit (+ Adafruit Unified Sensor)
    - Adafruit SSD1306 and Adafruit GFX Library
    - ArduinoJson

  The first boot (or a failed Wi-Fi connection) starts a Wi-Fi access point
  named MaatriWatch-Setup. A hospital worker uses its captive portal to enter
  Wi-Fi credentials. This is Wi-Fi provisioning, not patient pairing.
*/

#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <HTTPClient.h>
#include <MAX30105.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <WiFiManager.h>
#include <Wire.h>
#include "heartRate.h"

#include "secrets.h"

constexpr uint8_t PIN_DHT = 4;
constexpr uint8_t PIN_SOS = 27;
constexpr uint8_t I2C_SDA = 21;
constexpr uint8_t I2C_SCL = 22;
constexpr uint32_t UPLOAD_INTERVAL_MS = 15000;
constexpr uint32_t OLED_INTERVAL_MS = 500;
constexpr uint32_t SOS_HOLD_MS = 1200;
constexpr uint32_t MIN_IR_FOR_FINGER = 50000;

Adafruit_SSD1306 display(128, 64, &Wire, -1);
DHT dht(PIN_DHT, DHT11);
MAX30105 max3010x;

float bpm = NAN;
float airTemperature = NAN;
float humidity = NAN;
uint32_t lastBeatAt = 0;
uint32_t lastUploadAt = 0;
uint32_t lastDisplayAt = 0;
uint32_t lastDhtAt = 0;
uint32_t sosPressedAt = 0;
uint32_t sequence = 0;
bool fingerPresent = false;
bool sosSentForPress = false;
bool maxReady = false;

String isoTimestamp() {
  time_t now = time(nullptr);
  if (now < 1700000000) return "";  // Wait for NTP rather than invent a clinical timestamp.
  struct tm timeInfo;
  gmtime_r(&now, &timeInfo);
  char value[25];
  strftime(value, sizeof(value), "%Y-%m-%dT%H:%M:%SZ", &timeInfo);
  return String(value);
}

String eventId() {
  char id[64];
  snprintf(id, sizeof(id), "esp32-%llx-%lu", ESP.getEfuseMac(), ++sequence);
  return String(id);
}

bool postTelemetry(bool sosPressed) {
  if (WiFi.status() != WL_CONNECTED) return false;
  const String capturedAt = isoTimestamp();
  if (capturedAt.isEmpty()) return false;

  StaticJsonDocument<384> payload;
  payload["event_id"] = eventId();
  payload["source_sequence"] = sequence;
  payload["captured_at"] = capturedAt;
  // Do not upload DHT11 as maternal temperature: it is ambient-air data.
  if (fingerPresent && !isnan(bpm) && bpm >= 20 && bpm <= 260) payload["heart_rate_bpm"] = (int)round(bpm);
  JsonObject motion = payload["motion"].to<JsonObject>();
  if (sosPressed) motion["sos_pressed"] = true;

  String body;
  serializeJson(payload, body);
  HTTPClient http;
  int status = -1;
  if (String(API_URL).startsWith("https://")) {
    WiFiClientSecure client;
    client.setCACert(API_CA_CERT);
    http.begin(client, API_URL);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("X-Device-Id", DEVICE_ID);
    http.addHeader("X-Device-Key", DEVICE_KEY);
    status = http.POST(body);
  } else {
    // Local-LAN development only. Do not use HTTP outside an isolated test network.
    http.begin(API_URL);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("X-Device-Id", DEVICE_ID);
    http.addHeader("X-Device-Key", DEVICE_KEY);
    status = http.POST(body);
  }
  Serial.printf("Telemetry status: %d\n", status);
  http.end();
  return status >= 200 && status < 300;
}

void readHeartRate() {
  if (!maxReady) return;
  const long ir = max3010x.getIR();
  fingerPresent = ir > MIN_IR_FOR_FINGER;
  if (!fingerPresent) { bpm = NAN; return; }
  if (checkForBeat(ir)) {
    const uint32_t now = millis();
    if (lastBeatAt != 0) {
      const float candidate = 60.0f / ((now - lastBeatAt) / 1000.0f);
      if (candidate >= 35 && candidate <= 220) bpm = isnan(bpm) ? candidate : 0.75f * bpm + 0.25f * candidate;
    }
    lastBeatAt = now;
  }
}

void updateDisplay() {
  if (millis() - lastDisplayAt < OLED_INTERVAL_MS) return;
  lastDisplayAt = millis();
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.print("MaatriWatch");
  display.setCursor(0, 14);
  display.print(WiFi.status() == WL_CONNECTED ? "Wi-Fi: connected" : "Wi-Fi: reconnecting");
  display.setCursor(0, 28);
  display.print("Pulse: ");
  if (fingerPresent && !isnan(bpm)) display.printf("%.0f bpm", bpm); else display.print("place finger");
  display.setCursor(0, 42);
  display.print("Air: ");
  if (!isnan(airTemperature)) display.printf("%.0fC  %.0f%%", airTemperature, humidity); else display.print("DHT unavailable");
  display.setCursor(0, 56);
  display.print("Hold button for SOS");
  display.display();
}

void handleSosButton() {
  const bool pressed = digitalRead(PIN_SOS) == LOW;
  if (!pressed) { sosPressedAt = 0; sosSentForPress = false; return; }
  if (sosPressedAt == 0) sosPressedAt = millis();
  if (!sosSentForPress && millis() - sosPressedAt >= SOS_HOLD_MS) {
    sosSentForPress = true;
    postTelemetry(true);
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_SOS, INPUT_PULLUP);
  Wire.begin(I2C_SDA, I2C_SCL);
  dht.begin();
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) while (true) delay(1000);
  display.clearDisplay(); display.setTextColor(SSD1306_WHITE); display.setCursor(0, 0); display.print("MaatriWatch booting"); display.display();

  if (!max3010x.begin(Wire, I2C_SPEED_FAST)) {
    display.setCursor(0, 16); display.print("MAX30102 not found"); display.display();
  } else {
    maxReady = true;
    // power, sample average, LED mode, sample rate, pulse width, ADC range
    max3010x.setup(60, 4, 2, 100, 411, 4096);
    max3010x.setPulseAmplitudeRed(0x1F);
    max3010x.setPulseAmplitudeIR(0x1F);
  }

  WiFi.mode(WIFI_STA);
  WiFiManager portal;
  portal.setConfigPortalTimeout(180);
  if (!portal.autoConnect("MaatriWatch-Setup", PROVISIONING_PASSWORD)) ESP.restart();
  configTime(0, 0, "pool.ntp.org", "time.google.com");
}

void loop() {
  readHeartRate();
  handleSosButton();
  if (millis() - lastDhtAt > 1800) {
    lastDhtAt = millis();
    airTemperature = dht.readTemperature();
    humidity = dht.readHumidity();
  }
  if (millis() - lastUploadAt >= UPLOAD_INTERVAL_MS) {
    lastUploadAt = millis();
    postTelemetry(false);
  }
  updateDisplay();
  delay(8);
}
