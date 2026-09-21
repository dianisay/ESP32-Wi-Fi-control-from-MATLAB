#include <WiFi.h>
#include <Preferences.h>
#include <esp_system.h>

constexpr uint8_t LED_PIN = 2;
constexpr bool LED_ACTIVE_HIGH = true;
constexpr uint8_t SERVO_PIN = 25;
constexpr uint8_t SERVO_CHANNEL = 0;
constexpr uint32_t SERVO_FREQUENCY_HZ = 50;
constexpr uint8_t SERVO_RESOLUTION_BITS = 16;
constexpr int SERVO_SPAN_US = 400;
constexpr uint32_t SERVO_LEASE_MS = 500;
constexpr uint16_t TCP_PORT = 3333;
constexpr uint32_t IDLE_TIMEOUT_MS = 10000;
constexpr size_t MAX_LINE = 80;

WiFiServer server(TCP_PORT);
WiFiClient client;
String ssid;
String password;
char deviceId[13];
bool ledOn = false;
uint32_t lastActivity = 0;
bool servoEnabled = false;
int servoSpeed = 0;
int servoNeutralUs = 1500;
int servoPulseUs = 1500;
uint32_t lastServoCommand = 0;

struct LineBuffer {
  char text[MAX_LINE + 1] = {};
  size_t length = 0;
  bool overflow = false;
};

LineBuffer tcpLine;
LineBuffer usbLine;

void setLed(bool on) {
  ledOn = on;
  digitalWrite(LED_PIN, on == LED_ACTIVE_HIGH ? HIGH : LOW);
}

void writeServoPulse(int pulseUs) {
  const uint32_t duty = (static_cast<uint32_t>(pulseUs) * 65536UL + 10000UL) / 20000UL;
  ledcWrite(SERVO_CHANNEL, duty);
  servoPulseUs = pulseUs;
}

void stopServo() {
  if (servoEnabled && servoPulseUs != servoNeutralUs) {
    writeServoPulse(servoNeutralUs);
  }
  servoSpeed = 0;
  servoPulseUs = servoNeutralUs;
}

bool setServoSpeed(int speed) {
  if (!servoEnabled) {
    if (ledcSetup(SERVO_CHANNEL, SERVO_FREQUENCY_HZ, SERVO_RESOLUTION_BITS) != SERVO_FREQUENCY_HZ) {
      return false;
    }
    writeServoPulse(servoNeutralUs);
    ledcAttachPin(SERVO_PIN, SERVO_CHANNEL);
    servoEnabled = true;
  }
  writeServoPulse(servoNeutralUs + speed * SERVO_SPAN_US / 100);
  servoSpeed = speed;
  lastServoCommand = millis();
  return true;
}

bool parseInteger(const char *text, int minimum, int maximum, int &result) {
  const size_t length = strlen(text);
  const size_t sign = text[0] == '-' ? 1 : 0;
  if (length == 0 || length > 4 || length == sign ||
      strspn(text + sign, "0123456789") != length - sign) {
    return false;
  }
  const long value = strtol(text, nullptr, 10);
  if (value < minimum || value > maximum) {
    return false;
  }
  result = static_cast<int>(value);
  return true;
}

void sendServoInfo() {
  client.printf("OK SERVO GPIO %u NEUTRAL_US %d SPAN_US %d LEASE_MS %lu\n",
                SERVO_PIN, servoNeutralUs, SERVO_SPAN_US,
                static_cast<unsigned long>(SERVO_LEASE_MS));
}

void sendServoState() {
  client.printf("OK SERVO SPEED %d PULSE_US %d ENABLED %u\n",
                servoSpeed, servoPulseUs, servoEnabled ? 1 : 0);
}

void fatal(const char *message) {
  setLed(false);
  stopServo();
  Serial.print("ERROR ");
  Serial.println(message);
  while (true) {
    delay(1000);
  }
}

void sendState() {
  client.printf("OK LED %u LEVEL %u\n", ledOn ? 1 : 0,
                digitalRead(LED_PIN) == HIGH ? 1 : 0);
}

void handleTcp(const char *line) {
  if (strcmp(line, "HELLO") == 0) {
    client.printf("OK ESP32_MATLAB 1 %s GPIO %u ACTIVE_HIGH %u\n",
                  deviceId, LED_PIN, LED_ACTIVE_HIGH ? 1 : 0);
  } else if (strncmp(line, "PING ", 5) == 0) {
    const char *token = line + 5;
    const size_t length = strlen(token);
    if (length == 0 || length > 32 ||
        strspn(token, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-") != length) {
      client.println("ERR BAD_TOKEN");
    } else {
      client.printf("OK PONG %s\n", token);
    }
  } else if (strcmp(line, "LED 1") == 0) {
    setLed(true);
    sendState();
  } else if (strcmp(line, "LED 0") == 0) {
    setLed(false);
    sendState();
  } else if (strcmp(line, "STATE") == 0) {
    sendState();
  } else if (strcmp(line, "SERVO INFO") == 0) {
    sendServoInfo();
  } else if (strcmp(line, "SERVO STATE") == 0) {
    sendServoState();
  } else if (strcmp(line, "SERVO STOP") == 0) {
    stopServo();
    sendServoState();
  } else if (strncmp(line, "SERVO NEUTRAL ", 14) == 0) {
    int neutral;
    if (!parseInteger(line + 14, 1400, 1600, neutral)) {
      client.println("ERR NEUTRAL_RANGE_1400_1600");
    } else if (servoSpeed != 0) {
      client.println("ERR STOP_SERVO_FIRST");
    } else {
      servoNeutralUs = neutral;
      stopServo();
      sendServoInfo();
    }
  } else if (strncmp(line, "SERVO ", 6) == 0) {
    int speed;
    if (!parseInteger(line + 6, -100, 100, speed)) {
      client.println("ERR SERVO_RANGE_MINUS100_100");
    } else if (!setServoSpeed(speed)) {
      client.println("ERR SERVO_PWM_SETUP");
    } else {
      sendServoState();
    }
  } else {
    client.println("ERR BAD_COMMAND");
  }
}

void handleUsb(const char *line) {
  if (strcmp(line, "WIFI") != 0) {
    Serial.println("ERR USB_COMMAND_USE_WIFI");
    return;
  }
  // Credentials are disclosed only over the physical USB connection.
  Serial.printf(
      "{\"ssid\":\"%s\",\"password\":\"%s\",\"host\":\"%s\","
      "\"port\":%u,\"deviceId\":\"%s\",\"ledPin\":%u,\"activeHigh\":%s,"
      "\"servoPin\":%u}\n",
      ssid.c_str(), password.c_str(), WiFi.softAPIP().toString().c_str(),
      TCP_PORT, deviceId, LED_PIN, LED_ACTIVE_HIGH ? "true" : "false", SERVO_PIN);
}

void consume(Stream &stream, LineBuffer &buffer, bool usb) {
  // Limit each pass so a flooding client cannot starve timeout/USB handling.
  for (size_t count = 0; count < 128 && stream.available(); ++count) {
    const int value = stream.read();
    if (value < 0) {
      break;
    }
    const char ch = static_cast<char>(value);
    if (ch == '\n') {
      if (buffer.overflow) {
        stream.println("ERR BAD_LINE");
      } else {
        buffer.text[buffer.length] = '\0';
        if (usb) {
          handleUsb(buffer.text);
        } else {
          lastActivity = millis();
          handleTcp(buffer.text);
        }
      }
      buffer = LineBuffer{};
    } else if (ch != '\r') {
      if (ch < 32 || ch > 126 || buffer.length == MAX_LINE) {
        buffer.overflow = true;
      } else if (!buffer.overflow) {
        buffer.text[buffer.length++] = ch;
      }
    }
  }
}

void setup() {
  Serial.begin(115200);
  digitalWrite(LED_PIN, LED_ACTIVE_HIGH ? LOW : HIGH);
  pinMode(LED_PIN, OUTPUT);
  setLed(false);
  digitalWrite(SERVO_PIN, LOW);
  pinMode(SERVO_PIN, OUTPUT);

  const uint64_t mac = ESP.getEfuseMac();
  snprintf(deviceId, sizeof(deviceId), "%02X%02X%02X%02X%02X%02X",
           static_cast<unsigned>((mac >> 0) & 0xff),
           static_cast<unsigned>((mac >> 8) & 0xff),
           static_cast<unsigned>((mac >> 16) & 0xff),
           static_cast<unsigned>((mac >> 24) & 0xff),
           static_cast<unsigned>((mac >> 32) & 0xff),
           static_cast<unsigned>((mac >> 40) & 0xff));
  ssid = String("ESP32-MATLAB-") + (deviceId + 8);
  if (!WiFi.mode(WIFI_AP)) {
    fatal("Cannot enable Wi-Fi AP mode");
  }

  Preferences preferences;
  if (!preferences.begin("matlab-wifi", false)) {
    fatal("Cannot open credential storage");
  }
  password = preferences.getString("ap-password", "");
  if (password.isEmpty()) {
    char generated[17];
    snprintf(generated, sizeof(generated), "%08lx%08lx",
             static_cast<unsigned long>(esp_random()),
             static_cast<unsigned long>(esp_random()));
    password = generated;
    if (preferences.putString("ap-password", password) != password.length()) {
      fatal("Cannot persist AP password");
    }
  }
  preferences.end();
  if (password.length() < 8 || password.length() > 63) {
    fatal("Invalid stored AP password");
  }

  const IPAddress address(192, 168, 4, 1);
  if (!WiFi.softAPConfig(address, address, IPAddress(255, 255, 255, 0)) ||
      !WiFi.softAP(ssid.c_str(), password.c_str(), 6, false, 1)) {
    fatal("Cannot start access point");
  }
  server.begin();
  server.setNoDelay(true);
  Serial.printf("READY %s %s:%u GPIO%u\n", ssid.c_str(),
                WiFi.softAPIP().toString().c_str(), TCP_PORT, LED_PIN);
}

void loop() {
  // Only a speed command renews motion, not PING, LED or status traffic.
  if (servoSpeed != 0 &&
      static_cast<uint32_t>(millis() - lastServoCommand) >= SERVO_LEASE_MS) {
    stopServo();
  }
  consume(Serial, usbLine, true);
  if (!client || !client.connected()) {
    if (client) {
      client.stop();
    }
    setLed(false);
    stopServo();
    tcpLine = LineBuffer{};
    client = server.available();
    if (client) {
      client.setNoDelay(true);
      lastActivity = millis();
    }
  }
  if (client && client.connected()) {
    if (static_cast<uint32_t>(millis() - lastActivity) >= IDLE_TIMEOUT_MS) {
      setLed(false);
      stopServo();
      client.println("ERR IDLE_TIMEOUT");
      client.stop();
      tcpLine = LineBuffer{};
    } else {
      consume(client, tcpLine, false);
    }
  }
  delay(1);
}
