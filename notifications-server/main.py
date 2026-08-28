import json
import subprocess
import sys
import time
from pathlib import Path

import serial as pyserial
from mcp.server.mcpserver import MCPServer

import generate_constants

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ARDUINO_SKETCH = PROJECT_ROOT / "HardwareBridge"

mcp = MCPServer(name="notifications-server")

CONFIG_PATH = Path(__file__).resolve().parent.parent / "config.json"

try:
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
except (FileNotFoundError, json.JSONDecodeError) as exc:
    print(f"Failed to read config: {exc}", file=sys.stderr)
    config = {}

NOTIFY_TEMPLATE = {
    "cmd": "notify",
    "msg": "",
    "beeps": 3,
    "duration": 60,
}

serial = None

def _drain_startup(port):
    time.sleep(1.0)
    for _ in range(20):
        if port.in_waiting:
            port.read(port.in_waiting)
        time.sleep(0.05)


def get_serial_port():
    global serial
    if serial is not None and serial.is_open:
        return serial

    port_name = config.get("serial_port")
    baud_rate = config.get("baud_rate", 9600)
    if not port_name:
        raise RuntimeError("No serial port configured in config.json")

    try:
        serial = pyserial.Serial()
        serial.port = port_name
        serial.baudrate = baud_rate
        serial.timeout = 1
        serial.dsrdtr = False
        serial.dtr = False
        serial.open()
        _drain_startup(serial)
    except pyserial.SerialException as exc:
        raise RuntimeError(f"Unable to open serial port {port_name}: {exc}") from exc
    return serial


@mcp.tool()
def send_notification(message, beeps=3, duration=60):
    try:
        port = get_serial_port()
    except RuntimeError as exc:
        raise RuntimeError(str(exc)) from exc

    if not message or not message.strip():
        raise ValueError("Message cannot be empty")

    json_data = NOTIFY_TEMPLATE.copy()
    json_data["msg"] = message
    json_data["beeps"] = max(1, min(20, beeps))
    json_data["duration"] = max(1, min(300, duration))
    data = f"{json.dumps(json_data)}\n".encode()
    port.write(data)
    port.flush()
    return {"status": "ok", "msg": "notification sent", "beeps": json_data["beeps"], "duration": json_data["duration"]}


@mcp.tool()
def get_status():
    try:
        port = get_serial_port()
        port.write(b'{"cmd":"ping"}\n')
        response = port.readline().decode(errors="replace").strip()
        if not response:
            return {"status": "ok", "msg": "hardware connected"}
        return json.loads(response)
    except (RuntimeError, TypeError, ValueError, pyserial.SerialException) as exc:
        return {"status": "error", "msg": str(exc)}


@mcp.tool()
def flash_firmware(port=None):
    generate_constants.generate_constants()

    target_port = port or config.get("serial_port")
    if not target_port:
        return {"status": "error", "msg": "No serial port configured in config.json"}

    try:
        result = subprocess.run(
            [
                "arduino-cli", "upload",
                "--port", target_port,
                "--fqbn", "arduino:avr:uno",
                str(ARDUINO_SKETCH),
            ],
            capture_output=True,
            text=True,
            timeout=60,
            cwd=str(PROJECT_ROOT),
        )
        if result.returncode == 0:
            try:
                port = get_serial_port()
                test_msg = NOTIFY_TEMPLATE.copy()
                test_msg["msg"] = "Hello World!"
                test_msg["beeps"] = 3
                test_msg["duration"] = 60
                port.write(f"{json.dumps(test_msg)}\n".encode())
                port.flush()
                time.sleep(1.0)
                return {"status": "ok", "msg": "firmware flashed successfully, notification sent"}
            except Exception as exc:
                return {
                    "status": "ok",
                    "msg": "firmware flashed, but auto-notification failed: %s" % exc,
                }
        return {
            "status": "error",
            "msg": result.stderr.strip() or result.stdout.strip(),
        }
    except subprocess.TimeoutExpired:
        return {"status": "error", "msg": "upload timed out after 60s"}
    except FileNotFoundError:
        return {"status": "error", "msg": "arduino-cli not found"}


if __name__ == "__main__":
    generate_constants.generate_constants()
    mcp.run()