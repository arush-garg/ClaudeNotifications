#include <SPI.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <ArduinoJson.h>

#include "Constants.h"

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

char cmdBuffer[CMD_BUFFER_SIZE];
uint16_t cmdBufferIndex = 0;
bool cmdReady = false;

unsigned long notificationStartTime = 0;
unsigned long notificationDuration = 0;
bool notificationActive = false;
uint8_t beepsRemaining = 0;
bool buzzerState = false;
unsigned long lastBeepTime = 0;
bool displayReady = false;
const unsigned long BEEP_INTERVAL = 200;
const unsigned long BEEP_DURATION = 100;

void setup() {
  Serial.begin(BAUD_RATE);
  delay(100);

  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  pinMode(BUTTON_PIN, INPUT_PULLUP);

  displayReady = initDisplay();

  if (displayReady) {
    Serial.println(F("{\"status\":\"ready\"}"));
  } else {
    Serial.println(F("{\"status\":\"ready_no_display\"}"));
  }
}

void loop() {
  handleSerialInput();
  handleNotification();

  if(digitalRead(BUTTON_PIN) == LOW) {
    // Button pressed, clear display and stop notification
    if (displayReady) {
      display.clearDisplay();
      display.display();
    }
    notificationActive = false;
    noTone(BUZZER_PIN);
  }
}

void handleSerialInput() {
  while (Serial.available() > 0) {
    char c = Serial.read();

    if (c == '\n' || c == '\r') {
      if (cmdBufferIndex > 0) {
        cmdBuffer[cmdBufferIndex] = '\0';
        cmdReady = true;
        cmdBufferIndex = 0;
      }
      continue;
    }

    if (cmdBufferIndex < CMD_BUFFER_SIZE - 1) {
      cmdBuffer[cmdBufferIndex++] = c;
    }
  }

  if (cmdReady) {
    processCommand(cmdBuffer);
    cmdReady = false;
  }
}

void processCommand(const char* json) {
  StaticJsonDocument<CMD_BUFFER_SIZE> doc;
  DeserializationError error = deserializeJson(doc, json);

  if (error) {
    sendResponse("err", "JSON parse failed");
    return;
  }

  const char* cmd = doc["cmd"] | "";

  if (strcmp(cmd, "notify") == 0) {
    handleNotify(doc);
  } else if (strcmp(cmd, "ping") == 0) {
    sendResponse("ok", "pong");
  } else if (strcmp(cmd, "clear") == 0) {
    display.clearDisplay();
    display.display();
    sendResponse("ok", "cleared");
  } else {
    sendResponse("err", "Unknown command");
  }
}

void handleNotify(JsonDocument& doc) {
  const char* message = doc["msg"] | "";
  uint8_t beeps = doc["beeps"] | NUM_BEEPS;
  notificationDuration = (doc["duration"] | (NOTIFICATION_DURATION / 1000)) * 1000UL;

  if (strlen(message) == 0) {
    sendResponse("err", "Empty message");
    return;
  }

  if (displayReady) {
    displayText(message);
  }

  notificationActive = true;
  notificationStartTime = millis();
  beepsRemaining = beeps;
  buzzerState = false;
  lastBeepTime = 0;

  sendResponse("ok", "notification started");
}

void handleNotification() {
  if (!notificationActive) return;

  unsigned long now = millis();

  if (beepsRemaining > 0) {
    if (!buzzerState && (now - lastBeepTime >= BEEP_INTERVAL)) {
      tone(BUZZER_PIN, 2000);
      buzzerState = true;
      lastBeepTime = now;
    } else if (buzzerState && (now - lastBeepTime >= BEEP_DURATION)) {
      noTone(BUZZER_PIN);
      buzzerState = false;
      beepsRemaining--;
      lastBeepTime = now;
    }
  }

  // Stop buzzing after the notification duration has passed
  if (now - notificationStartTime >= notificationDuration) {
    noTone(BUZZER_PIN);
    buzzerState = false;
    beepsRemaining = 0;
  }
}

void sendResponse(const char* status, const char* message) {
  Serial.print(F("{\"status\":\""));
  Serial.print(status);
  Serial.print(F("\",\"msg\":\""));
  Serial.print(message);
  Serial.println(F("\"}"));
}
