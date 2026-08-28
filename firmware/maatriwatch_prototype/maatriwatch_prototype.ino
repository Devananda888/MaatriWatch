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
#include "spo2_algorithm.h"

#include "secrets.h"

constexpr uint8_t PIN_DHT = 4;
constexpr uint8_t PIN_SOS = 27;
constexpr uint8_t I2C_SDA = 21;
constexpr uint8_t I2C_SCL = 22;
constexpr uint32_t UPLOAD_INTERVAL_MS = 15000;
constexpr uint32_t OLED_INTERVAL_MS = 500;
constexpr uint32_t SOS_HOLD_MS = 1200;
// A low threshold makes the contact detector work with lower-cost MAX30102
// breakouts.  The red/IR waveform-quality checks below still prevent a value
// from being reported when a real pulse is not present.
constexpr uint32_t MIN_IR_FOR_FINGER = 10000;
constexpr uint8_t FINGER_ON_SAMPLES = 3;
constexpr uint8_t FINGER_OFF_SAMPLES = 25;
constexpr uint8_t SPO2_BUFFER_SIZE = 100;  // Four seconds at 25 samples/second.
constexpr uint32_t HEART_RATE_STALE_MS = 12000;
constexpr uint32_t PULSE_LOSS_TIMEOUT_MS = 3500;
constexpr uint32_t SPO2_STALE_MS = 45000;
constexpr uint32_t DHT_INTERVAL_MS = 2200;
constexpr uint32_t DHT_STALE_MS = 60000;

Adafruit_SSD1306 display(128, 64, &Wire, -1);
DHT dht(PIN_DHT, DHT11);
MAX30105 max3010x;

float bpm = NAN;
float spo2 = NAN;
float airTemperature = NAN;
float humidity = NAN;
uint32_t irBuffer[SPO2_BUFFER_SIZE];
uint32_t redBuffer[SPO2_BUFFER_SIZE];
uint8_t spo2SampleCount = 0;
uint32_t lastUploadAt = 0;
uint32_t lastDisplayAt = 0;
uint32_t lastDhtAt = 0;
uint32_t lastDhtValidAt = 0;
uint32_t lastPpgDiagnosticAt = 0;
uint32_t sosPressedAt = 0;
uint32_t lastBeatAt = 0;
uint32_t lastPulseSignalAt = 0;
uint32_t lastValidHeartRateAt = 0;
uint32_t lastValidSpo2At = 0;
uint32_t sequence = 0;
bool fingerPresent = false;
bool spo2MeasurementValid = false;
bool sosSentForPress = false;
bool maxReady = false;
uint8_t consecutiveFingerSamples = 0;
uint8_t consecutiveNoFingerSamples = 0;
uint32_t lastIr = 0;
uint32_t lastRed = 0;
float ppgPerfusionIndex = NAN;
float pendingBpm = NAN;
uint8_t consistentBeatIntervals = 0;
uint8_t dhtReadFailures = 0;

bool isHeartRateFresh();
bool isSpo2Fresh();
bool isAmbientFresh();

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

  const bool hasHeartRate = fingerPresent && isHeartRateFresh() && !isnan(bpm) && bpm >= 20 && bpm <= 260;
  const bool hasSpo2 = fingerPresent && isSpo2Fresh() && !isnan(spo2) && spo2 >= 70 && spo2 <= 100;
  const bool hasAmbient = isAmbientFresh();
  // The API intentionally rejects events with no observation.  Avoid sending
  // an empty periodic event while the watch is off-wrist; an SOS is still a
  // meaningful event and must always be uploaded.
  if (!hasHeartRate && !hasSpo2 && !hasAmbient && !sosPressed) {
    Serial.println("Telemetry skipped: waiting for a valid sensor observation.");
    return true;
  }

  StaticJsonDocument<512> payload;
  payload["event_id"] = eventId();
  payload["source_sequence"] = sequence;
  payload["captured_at"] = capturedAt;
  // DHT11 is intentionally reported as ambient only, never as maternal body temperature.
  if (hasHeartRate) payload["heart_rate_bpm"] = (int)round(bpm);
  if (hasSpo2) payload["spo2_percent"] = round(spo2 * 10.0f) / 10.0f;
  if (hasAmbient && !isnan(airTemperature)) payload["ambient_temperature_c"] = round(airTemperature * 10.0f) / 10.0f;
  if (hasAmbient && !isnan(humidity)) payload["ambient_humidity_percent"] = round(humidity * 10.0f) / 10.0f;
  JsonObject motion = payload["motion"].to<JsonObject>();
  if (sosPressed) motion["sos_pressed"] = true;

  String body;
  serializeJson(payload, body);
  HTTPClient http;
  // Free-tier hosts can take longer to wake on the first request.  Keep the
  // device responsive while allowing enough time for that legitimate delay.
  http.setTimeout(20000);
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
  if (status >= 400) {
    Serial.printf("Telemetry response: %s\n", http.getString().c_str());
  }
  http.end();
  return status >= 200 && status < 300;
}

void clearPpgMeasurements() {
  bpm = NAN;
  spo2 = NAN;
  spo2MeasurementValid = false;
  spo2SampleCount = 0;
  lastBeatAt = 0;
  lastPulseSignalAt = 0;
  lastValidHeartRateAt = 0;
  lastValidSpo2At = 0;
  ppgPerfusionIndex = NAN;
  pendingBpm = NAN;
  consistentBeatIntervals = 0;
}

bool isHeartRateFresh() {
  return lastValidHeartRateAt != 0 && lastPulseSignalAt != 0 &&
         millis() - lastValidHeartRateAt <= HEART_RATE_STALE_MS &&
         millis() - lastPulseSignalAt <= PULSE_LOSS_TIMEOUT_MS;
}

bool isSpo2Fresh() {
  return spo2MeasurementValid && lastValidSpo2At != 0 && millis() - lastValidSpo2At <= SPO2_STALE_MS;
}

bool isAmbientFresh() {
  return lastDhtValidAt != 0 && millis() - lastDhtValidAt <= DHT_STALE_MS &&
         !isnan(airTemperature) && !isnan(humidity);
}

void acceptHeartRate(float candidate) {
  if (candidate < 35 || candidate > 220) return;
  // The first accepted value is displayed immediately.  Later values are
  // smoothed just enough to avoid a distracting flicker on the watch face.
  bpm = isnan(bpm) ? candidate : 0.65f * bpm + 0.35f * candidate;
  lastValidHeartRateAt = millis();
}

void processBeatCandidate(float candidate) {
  if (candidate < 35 || candidate > 220) return;
  // A single optical spike can resemble a beat. Require two similarly timed
  // intervals before the value is allowed onto the OLED or dashboard.
  if (isnan(pendingBpm) || fabsf(candidate - pendingBpm) > 18.0f) {
    pendingBpm = candidate;
    consistentBeatIntervals = 1;
    return;
  }
  pendingBpm = 0.65f * pendingBpm + 0.35f * candidate;
  if (consistentBeatIntervals < 255) consistentBeatIntervals++;
  if (consistentBeatIntervals >= 2) acceptHeartRate(pendingBpm);
}

void updateFingerPresence(uint32_t ir) {
  if (ir >= MIN_IR_FOR_FINGER) {
    consecutiveNoFingerSamples = 0;
    if (consecutiveFingerSamples < FINGER_ON_SAMPLES) consecutiveFingerSamples++;
    if (consecutiveFingerSamples >= FINGER_ON_SAMPLES) fingerPresent = true;
    return;
  }

  consecutiveFingerSamples = 0;
  if (consecutiveNoFingerSamples < FINGER_OFF_SAMPLES) consecutiveNoFingerSamples++;
  // Do not discard a valid reading because of one noisy FIFO sample.
  if (consecutiveNoFingerSamples >= FINGER_OFF_SAMPLES) {
    if (fingerPresent) clearPpgMeasurements();
    fingerPresent = false;
  }
}

void readPpg() {
  if (!maxReady) return;
  // `check()` reads all newly available FIFO records.  The MAX30102 is set to
  // 25 SPS below, matching the 100-sample / four-second Maxim SpO2 window.
  // getIR()/getRed() would re-read the latest item and can drop samples here,
  // so consume each FIFO record and advance it exactly once.
  max3010x.check();
  while (max3010x.available()) {
    const uint32_t ir = max3010x.getFIFOIR();
    const uint32_t red = max3010x.getFIFORed();
    lastIr = ir;
    lastRed = red;
    updateFingerPresence(ir);
    if (!fingerPresent) {
      max3010x.nextSample();
      continue;
    }
    // The SparkFun detector uses 16-bit signal maths while MAX30102 emits
    // 18-bit samples. Scaling prevents overflow without losing the pulse.
    if (checkForBeat(static_cast<int32_t>(ir >> 3))) {
      const uint32_t now = millis();
      if (lastBeatAt != 0) {
        const float candidate = 60.0f / ((now - lastBeatAt) / 1000.0f);
        if (candidate >= 35 && candidate <= 220) {
          processBeatCandidate(candidate);
          if (consistentBeatIntervals >= 2) lastPulseSignalAt = now;
        }
      }
      lastBeatAt = now;
    }
    irBuffer[spo2SampleCount] = static_cast<uint32_t>(ir);
    redBuffer[spo2SampleCount] = static_cast<uint32_t>(red);
    spo2SampleCount++;
    if (spo2SampleCount == SPO2_BUFFER_SIZE) {
      int32_t calculatedSpo2 = 0;
      int32_t calculatedHeartRate = 0;
      int8_t validSpo2 = 0;
      int8_t validHeartRate = 0;
      // Maxim's reference algorithm uses red/IR PPG ratio-of-ratios across a
      // buffered window. It is an experimental prototype value, not clinical SpO2.
      maxim_heart_rate_and_oxygen_saturation(
          irBuffer, SPO2_BUFFER_SIZE, redBuffer,
          &calculatedSpo2, &validSpo2, &calculatedHeartRate, &validHeartRate);
      uint32_t minIr = irBuffer[0];
      uint32_t maxIr = irBuffer[0];
      uint64_t irTotal = 0;
      for (uint8_t index = 0; index < SPO2_BUFFER_SIZE; ++index) {
        const uint32_t value = irBuffer[index];
        if (value < minIr) minIr = value;
        if (value > maxIr) maxIr = value;
        irTotal += value;
      }
      const float meanIr = static_cast<float>(irTotal) / SPO2_BUFFER_SIZE;
      ppgPerfusionIndex = meanIr > 0 ? (maxIr - minIr) * 100.0f / meanIr : NAN;
      const bool hasPulseWave = !isnan(ppgPerfusionIndex) && ppgPerfusionIndex >= 0.15f;
      // The four-second reference result also refreshes a confirmed pulse.
      if (validHeartRate && hasPulseWave) {
        lastPulseSignalAt = millis();
        acceptHeartRate(static_cast<float>(calculatedHeartRate));
      }
      const bool validWindow = validSpo2 && hasPulseWave && calculatedSpo2 >= 70 && calculatedSpo2 <= 100;
      if (validWindow) {
        const float candidate = static_cast<float>(calculatedSpo2);
        spo2 = isnan(spo2) ? candidate : 0.8f * spo2 + 0.2f * candidate;
        spo2MeasurementValid = true;
        lastValidSpo2At = millis();
      }
      // A single motion-corrupted window must not blank a good value that was
      // just acquired.  It becomes unavailable automatically after 45 seconds
      // or immediately when finger contact is lost.
      spo2SampleCount = 0;
    }
    max3010x.nextSample();
  }

  // This compact diagnostic makes a wiring/contact problem visible without
  // exposing device credentials. It is useful only in the Arduino Serial
  // Monitor and is deliberately rate-limited.
  if (millis() - lastPpgDiagnosticAt >= 2000) {
    lastPpgDiagnosticAt = millis();
    Serial.printf("PPG ir=%lu red=%lu contact=%s samples=%u bpm=%.1f hrFresh=%s beats=%u spo2=%.1f pi=%.2f dhtFailures=%u\n",
                  lastIr, lastRed, fingerPresent ? "yes" : "no",
                  spo2SampleCount, bpm, isHeartRateFresh() ? "yes" : "no", consistentBeatIntervals,
                  spo2, ppgPerfusionIndex, dhtReadFailures);
  }
}

void readAmbientSensor() {
  const float nextTemperature = dht.readTemperature();
  const float nextHumidity = dht.readHumidity();
  if (!isnan(nextTemperature) && !isnan(nextHumidity)) {
    airTemperature = nextTemperature;
    humidity = nextHumidity;
    lastDhtValidAt = millis();
    dhtReadFailures = 0;
    return;
  }
  if (dhtReadFailures < 255) dhtReadFailures++;
  Serial.println("DHT11 read failed; keeping the last fresh ambient reading.");
}

void drawHeart(int16_t x, int16_t y, uint8_t radius) {
  // A small, pulsing heart gives reassurance without delaying sensor reads.
  display.fillCircle(x - radius / 2, y, radius / 2, SSD1306_WHITE);
  display.fillCircle(x + radius / 2, y, radius / 2, SSD1306_WHITE);
  display.fillTriangle(x - radius, y, x + radius, y, x, y + radius + 2, SSD1306_WHITE);
}

void drawCalmAnimation() {
  const uint32_t cycle = !isnan(bpm) && bpm >= 35 && bpm <= 180
                             ? static_cast<uint32_t>(60000.0f / bpm)
                             : 1200;
  const float phase = static_cast<float>(millis() % cycle) / cycle;
  const uint8_t heartSize = 6 + static_cast<uint8_t>(3.0f * (0.5f + 0.5f * sinf(phase * TWO_PI)));
  drawHeart(117, 7, heartSize);
  if (phase < 0.30f) display.drawCircle(117, 7, heartSize + 3, SSD1306_WHITE);
}

void updateDisplay() {
  if (millis() - lastDisplayAt < OLED_INTERVAL_MS) return;
  lastDisplayAt = millis();
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.print("MaatriWatch");
  drawCalmAnimation();
  // A watch face should be readable in one glance. Environmental readings
  // continue to upload to the dashboard but stay off this small display.
  display.setCursor(0, 13);
  display.print("PULSE");
  display.setTextSize(2);
  display.setCursor(47, 10);
  if (fingerPresent && isHeartRateFresh() && !isnan(bpm)) display.printf("%.0f", bpm); else display.print("--");
  display.setTextSize(1);
  display.setCursor(82, 16);
  display.print("bpm");

  display.setCursor(0, 34);
  display.print("SpO2");
  display.setTextSize(2);
  display.setCursor(47, 31);
  if (fingerPresent && isSpo2Fresh() && !isnan(spo2)) display.printf("%.0f%%", spo2); else display.print("--");
  display.setTextSize(1);
  display.setCursor(0, 56);
  if (!fingerPresent) display.print("Place finger on sensor");
  else if (!isHeartRateFresh()) display.print("Keep still, finding pulse");
  else if (!isSpo2Fresh()) display.printf("SpO2 settling %u%%", (spo2SampleCount * 100) / SPO2_BUFFER_SIZE);
  else display.print("Reading updated");
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
    // power, sample average, LED mode, sample rate, pulse width, ADC range.
    // The 25 SPS rate is intentional: the Maxim algorithm receives exactly
    // four seconds of PPG per 100-sample evaluation window.
    max3010x.setup(80, 4, 2, 25, 411, 4096);
    max3010x.setPulseAmplitudeRed(0x3F);
    max3010x.setPulseAmplitudeIR(0x3F);
    max3010x.setPulseAmplitudeGreen(0);
  }

  WiFi.mode(WIFI_STA);
  WiFiManager portal;
  portal.setConfigPortalTimeout(180);
  if (!portal.autoConnect("MaatriWatch-Setup", PROVISIONING_PASSWORD)) ESP.restart();
  configTime(0, 0, "pool.ntp.org", "time.google.com");
}

void loop() {
  readPpg();
  handleSosButton();
  if (millis() - lastDhtAt >= DHT_INTERVAL_MS) {
    lastDhtAt = millis();
    readAmbientSensor();
  }
  if (millis() - lastUploadAt >= UPLOAD_INTERVAL_MS) {
    lastUploadAt = millis();
    postTelemetry(false);
  }
  updateDisplay();
  delay(8);
}
