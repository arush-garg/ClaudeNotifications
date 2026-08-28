import json
import os
import sys

import serial

HOOK_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(HOOK_DIR)
sys.path.insert(0, os.path.join(PROJECT_ROOT, "notifications-server"))

import main as notif_main

SERIAL_TIMEOUT = 2


def main():
    stdin_data = sys.stdin.read()

    if not stdin_data:
        return

    try:
        data = json.loads(stdin_data)
    except json.JSONDecodeError:
        return

    tool_name = data.get("tool_name", "")
    if tool_name != "AskUserQuestion":
        return

    questions = data.get("tool_input", {}).get("questions", [])
    if not questions:
        return

    parts = []
    for q in questions[:3]:
        header = q.get("header", "")
        question_text = q.get("question", "")
        if header and question_text:
            parts.append(f"{header}: {question_text}")
        elif question_text:
            parts.append(question_text)

    if not parts:
        return

    message = " | ".join(parts)
    msg = (message[:80] + "...") if len(message) > 80 else message

    try:
        notif_main.send_notification(msg)
    except Exception:
        pass


if __name__ == "__main__":
    main()