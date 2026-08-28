import json
import re
from pathlib import Path

COLOR_MAPPINGS = {
    "white": "SSD1306_WHITE",
    "black": "SSD1306_BLACK",
    "inverse": "SSD1306_INVERSE",
}


def to_macro_name(key):
    cleaned = re.sub(r"[^A-Za-z0-9]+", "_", key.strip()).upper()
    return cleaned.strip("_")


def format_macro_value(value):
    if isinstance(value, str):
        if value.upper() in {"SSD1306_WHITE", "SSD1306_BLACK", "SSD1306_INVERSE"}:
            return value.upper()
        return f'"{value}"'
    if isinstance(value, bool):
        return "1" if value else "0"
    return str(value)


def generate_constants():
    project_root = Path(__file__).resolve().parent.parent
    config_path = project_root / "config.json"
    output_path = project_root / "HardwareBridge" / "Constants.h"

    with config_path.open("r", encoding="utf-8") as f:
        config = json.load(f)

    generated = {
        "BAUD_RATE": config.get("baud_rate", 9600),
        "SCREEN_WIDTH": config.get("screen_width", 128),
        "SCREEN_HEIGHT": config.get("screen_height", 64),
        "TEXT_SIZE": config.get("text_size", 1),
        "TEXT_COLOR": COLOR_MAPPINGS.get(str(config.get("text_color", "white")).lower(), "SSD1306_WHITE"),
        "NUM_BEEPS": config.get("num_beeps", 3),
        "NOTIFICATION_DURATION": int(config.get("notification_duration", 60)) * 1000,
        "BUZZER_PIN": config.get("buzzer_pin", 8),
        "BUTTON_PIN": config.get("button_pin", 7),
        "OLED_RESET": -1,
        "CMD_BUFFER_SIZE": 128,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)

    with output_path.open("w", encoding="utf-8") as f:
        f.write("// Auto-generated from config.json - DO NOT EDIT MANUALLY\n")
        f.write("#pragma once\n\n")
        for key, value in generated.items():
            f.write(f"#define {key} {format_macro_value(value)}\n")

    return output_path


if __name__ == "__main__":
    generate_constants()