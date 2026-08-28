#!/usr/bin/env bash
# Setup script for Hardware Notifications MCP Server
# Usage: ./setup.sh [--local]
#   --local : Clone from GitHub and install to current directory
#   (default: clone from GitHub and install to ~/.notifications/)
#
# Examples:
#   ./setup.sh              # Clone from GitHub, install to ~/.notifications/
#   ./setup.sh --local      # Clone from GitHub, install to current directory

set -euo pipefail

# Determine install mode
MODE="global"
if [[ "${1:-}" == "--local" ]]; then
    MODE="local"
fi

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

GH_URL="https://github.com/arush-garg/ClaudeNotifications.git"

# Set paths based on mode
if [[ "$MODE" == "global" ]]; then
    PROJECT_ROOT="$HOME/.notifications"
    if [ -d "$PROJECT_ROOT" ]; then
        echo "⚠️  Already installed at $PROJECT_ROOT. Skipping installation."
        echo "   To reinstall, remove the directory first: rm -rf $PROJECT_ROOT"
        exit 0
    fi

    # Clone from GitHub
    mkdir -p "$PROJECT_ROOT"
    echo "📦 Cloning from GitHub (${GH_URL})..."
    git clone --depth 1 "$GH_URL" "$PROJECT_ROOT"
    cd "$PROJECT_ROOT"
else
    PROJECT_ROOT="$SCRIPT_DIR"

    echo "📦 Cloning from GitHub (${GH_URL})..."
    git clone --depth 1 "$GH_URL" "$PROJECT_ROOT"
    cd "$PROJECT_ROOT"
fi

echo "🔧 Setting up Hardware Notifications MCP Server"
echo "Mode: $MODE"
echo "Project root: $PROJECT_ROOT"

# 1. Check Arduino CLI
if ! command -v arduino-cli &> /dev/null; then
    echo "📦 Installing arduino-cli..."
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh
    export PATH="$PATH:$HOME/bin"
fi
echo "✅ arduino-cli: $(arduino-cli version 2>/dev/null | head -1)"

# 2. Install Arduino libraries
echo "📦 Installing Arduino libraries..."
arduino-cli lib install "Adafruit SSD1306" "Adafruit GFX Library" "ArduinoJson" 2>/dev/null || true

# 3. Check uv
if ! command -v uv &> /dev/null; then
    echo "📦 Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$PATH:$HOME/.local/bin"
fi
echo "✅ uv: $(uv --version)"

# 4. Install Python dependencies
echo "📦 Installing Python dependencies..."
cd "$PROJECT_ROOT/notifications-server"
uv sync

# 5. Generate Constants.h
echo "⚙️  Generating Constants.h from config.json..."
python3 generate_constants.py

# 6. Detect serial port
echo "🔍 Detecting Arduino port..."
PORT=$(arduino-cli board list 2>/dev/null | grep -E "(usbmodem|ttyUSB|ttyACM)" | awk '{print $1}' | head -1) || true
if [ -n "$PORT" ]; then
    echo "✅ Found port: $PORT"
    # Update config.json with detected port
    python3 -c "
import json
with open('$PROJECT_ROOT/config.json') as f:
    config = json.load(f)
config['serial_port'] = '$PORT'
with open('$PROJECT_ROOT/config.json', 'w') as f:
    json.dump(config, f, indent=2)
"
    echo "📝 Updated config.json with serial_port: $PORT"
else
    echo "⚠️  No Arduino detected. Connect board and run again, or edit config.json manually."
fi

# 7. Flash firmware
if [ -n "$PORT" ]; then
    echo "🔥 Flashing firmware..."
    arduino-cli compile --fqbn arduino:avr:uno "$PROJECT_ROOT/HardwareBridge"
    arduino-cli upload -p "$PORT" --fqbn arduino:avr:uno "$PROJECT_ROOT/HardwareBridge"
    echo "✅ Firmware flashed"
fi

# 8. Register MCP server
MCP_ENTRY="{\"type\": \"stdio\", \"command\": \"uv\", \"args\": [\"run\", \"--project\", \"$PROJECT_ROOT/notifications-server\", \"--directory\", \"$PROJECT_ROOT/notifications-server\", \"python\", \"main.py\"], \"env\": {}}"
if [[ "$MODE" == "global" ]]; then
    echo "Global install at: $PROJECT_ROOT"
    SETTINGS_FILE="$HOME/.claude.json"
    if [ -f "$SETTINGS_FILE" ]; then
        python3 - "$SETTINGS_FILE" "$MCP_ENTRY" <<'PY'
import json, sys

settings_path, mcp_entry = sys.argv[1], sys.argv[2]

try:
    with open(settings_path) as f:
        s = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    s = {}

mcp = s.setdefault("mcpServers", {})
try:
    entry = json.loads(mcp_entry)
except json.JSONDecodeError:
    print("⚠️  Failed to parse MCP entry", file=sys.stderr)
    sys.exit(1)

prev = json.dumps(mcp.get("notifications"), sort_keys=True)
mcp["notifications"] = entry
curr = json.dumps(mcp["notifications"], sort_keys=True)
if prev != curr:
    with open(settings_path, "w") as f:
        json.dump(s, f, indent=2)
    print("🪝 Registered MCP server in ~/.claude.json")
else:
    print("ℹ️  MCP server already registered in ~/.claude.json")
PY
    else
        echo "⚠️  ~/.claude.json not found. Add MCP server manually:"
        echo ""
        echo "  {\"mcpServers\": {\"notifications\": $MCP_ENTRY}}"
    fi
else
    echo "Project-scope install at: $PROJECT_ROOT"
    echo "Add to your MCP client config:"
    echo ""
    echo "{ \"mcpServers\": { \"notifications\": $MCP_ENTRY } }"
fi

# 9. Install Claude Code hooks (global mode only)
if [[ "$MODE" == "global" ]]; then
    HOOK_SRC_DIR="$SCRIPT_DIR/hooks"
    HOOK_INSTALL_DIR="$HOME/.notifications/.claude/hooks"
    HOOK_SCRIPT="$HOOK_INSTALL_DIR/ask.py"

    if [ ! -d "$HOOK_SRC_DIR" ]; then
        echo "⚠️  No hooks directory found, skipping hook install"
    else
        mkdir -p "$HOOK_INSTALL_DIR"
        cp "$HOOK_SRC_DIR"/*.py "$HOOK_INSTALL_DIR/" 2>/dev/null || true
        chmod +x "$HOOK_INSTALL_DIR"/*.py 2>/dev/null || true
        echo "🪝 Installed hooks to $HOOK_INSTALL_DIR"

        # Register hook in ~/.claude/settings.json (hooks config lives here)
        SETTINGS_FILE="$HOME/.claude/settings.json"
        python3 - "$SETTINGS_FILE" "$HOOK_SCRIPT" <<'PY'
import json, sys

settings_path, hook_path = sys.argv[1], sys.argv[2]

try:
    with open(settings_path) as f:
        s = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    s = {}

hooks = s.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])
matcher = {"matcher": "AskUserQuestion", "hooks": [{"type": "command", "command": f"python3 {hook_path}"}]}
if not any(h.get("matcher") == "AskUserQuestion" for h in pre):
    pre.append(matcher)
else:
    # Update path if already exists
    for h in pre:
        if h.get("matcher") == "AskUserQuestion":
            h["hooks"][0]["command"] = f"python3 {hook_path}"

with open(settings_path, "w") as f:
    json.dump(s, f, indent=2)
PY
        echo "🪝 Registered AskUserQuestion hook in ~/.claude/settings.json"
    fi
else
    echo "ℹ️  Skipping hook install (--local mode)"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Add the MCP config above to your client"
echo "  2. Restart your MCP client"
echo "  3. Test: call send_notification(\"Hello from MCP!\")"