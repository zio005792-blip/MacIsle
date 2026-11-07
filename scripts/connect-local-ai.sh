#!/bin/zsh
# Runs the MacIsle local-AI gateway in the background at login (a LaunchAgent).
# The model itself only loads on demand and unloads after 5 idle minutes.
#   scripts/connect-local-ai.sh          install / update
#   scripts/connect-local-ai.sh --undo   remove
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.macisle"
PLIST="$HOME/Library/LaunchAgents/com.macisle.llm-gateway.plist"
LABEL="com.macisle.llm-gateway"

if [[ "${1:-}" == "--undo" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "local AI gateway removed"
  exit 0
fi

mkdir -p "$DEST" "$HOME/Library/LaunchAgents"
cp "$HERE/local-ai/macisle-llm-gateway.py" "$DEST/"
PY="$HOME/.local/share/Qwen36-MLX/py312/bin/python"
[[ -x "$PY" ]] || PY=/usr/bin/python3
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$PY</string><string>$DEST/macisle-llm-gateway.py</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardErrorPath</key><string>$DEST/llm-gateway.log</string>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 1
curl -s http://127.0.0.1:8737/health && echo && echo "local AI gateway running on 127.0.0.1:8737"
