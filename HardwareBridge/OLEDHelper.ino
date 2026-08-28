#include <Adafruit_SSD1306.h>
#include "Constants.h"

extern Adafruit_SSD1306 display;
extern bool displayReady;

bool initDisplay() {
  Wire.begin();

  // I2C timeout prevents indefinite hangs on bus
  Wire.setWireTimeout(25000, true);

  if (display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    displayReady = true;
  } else if (display.begin(SSD1306_SWITCHCAPVCC, 0x3D)) {
    displayReady = true;
  } else {
    displayReady = false;
  }

  if (!displayReady) {
    return false;
  }

  display.clearDisplay();
  display.setTextSize(TEXT_SIZE);
  display.setTextColor(TEXT_COLOR);
  display.setCursor(0, 0);
  display.display();
  return true;
}

void displayText(const char* text) {
  if (!displayReady) return;

  display.clearDisplay();
  display.setTextSize(TEXT_SIZE);
  display.setTextColor(TEXT_COLOR);
  display.setCursor(0, 0);

  // 128x32 @ size 1: 5px/char -> 25 chars/line, 2 lines max
  const uint8_t maxCharsPerLine = 25;
  const uint8_t maxLines = 2;
  uint8_t line = 0;
  uint8_t col = 0;
  char buf[32];
  uint8_t bufIdx = 0;

  for (uint16_t i = 0; text[i] != '\0'; ++i) {
    char ch = text[i];

    if (ch == ' ') {
      if (bufIdx > 0) {
        buf[bufIdx] = '\0';
        if (line < maxLines) {
          uint8_t need = bufIdx + 1; // word + space
          if (col + need > maxCharsPerLine) {
            display.println();
            line++;
            col = 0;
          }
          display.print(buf);
          display.print(' ');
          col += need;
        }
        bufIdx = 0;
      }
      continue;
    }

    if (ch == '\n' || ch == '\r') {
      if (bufIdx > 0) {
        buf[bufIdx] = '\0';
        if (line < maxLines) {
          display.println(buf);
          line++;
          col = 0;
        }
        bufIdx = 0;
      }
      continue;
    }

    buf[bufIdx++] = ch;
    if (bufIdx >= maxCharsPerLine) {
      buf[bufIdx] = '\0';
      if (line < maxLines) {
        display.println(buf);
        line++;
        col = 0;
      }
      bufIdx = 0;
    }
  }

  if (bufIdx > 0 && line < maxLines) {
    buf[bufIdx] = '\0';
    display.println(buf);
  }

  display.display();
}
