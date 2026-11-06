#!/bin/zsh
# Connects Claude Code, Codex and zsh to the Boring Notch island.
#   scripts/connect-workflow.sh          install (backs up every file it touches)
#   scripts/connect-workflow.sh --undo   restore the backups
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.boring-island"
STAMP="$(date +%Y%m%d-%H%M%S)"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CODEX_CONFIG="$HOME/.codex/config.toml"
ZSHRC="$HOME/.zshrc"

if [[ "${1:-}" == "--undo" ]]; then
  for f in "$CLAUDE_SETTINGS" "$CODEX_CONFIG" "$ZSHRC"; do
    latest=$(ls -t "$f".island-backup-* 2>/dev/null | head -1 || true)
    if [[ -n "$latest" ]]; then cp "$latest" "$f"; echo "restored $f"; fi
  done
  exit 0
fi

mkdir -p "$DEST"
cp "$HERE/island-hooks/island-notify.py" "$HERE/island-hooks/codex-notify.sh" "$HERE/island-hooks/island.zsh" "$DEST/"
chmod +x "$DEST/island-notify.py" "$DEST/codex-notify.sh"

# 1) Claude Code hooks (merged into existing settings)
if [[ -f "$CLAUDE_SETTINGS" ]]; then
  cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.island-backup-$STAMP"
  /usr/bin/python3 - "$CLAUDE_SETTINGS" "$DEST/island-notify.py" <<'PY'
import json, sys
path, script = sys.argv[1], sys.argv[2]
data = json.load(open(path))
hooks = data.setdefault("hooks", {})
cmd = f"/usr/bin/python3 '{script}' claude"
for event in ("UserPromptSubmit", "Notification", "Stop"):
    groups = hooks.setdefault(event, [])
    if any(h.get("command") == cmd for g in groups for h in g.get("hooks", [])):
        continue
    groups.append({"hooks": [{"type": "command", "command": cmd, "timeout": 5}]})
json.dump(data, open(path, "w"), indent=2, ensure_ascii=False)
print("Claude Code hooks added")
PY
fi

# 2) Codex notify (keeps the existing notifier by chaining it)
if [[ -f "$CODEX_CONFIG" ]]; then
  cp "$CODEX_CONFIG" "$CODEX_CONFIG.island-backup-$STAMP"
  /usr/bin/python3 - "$CODEX_CONFIG" "$DEST" <<'PY'
import json, re, sys
path, dest = sys.argv[1], sys.argv[2]
text = open(path).read()
wrapper = [ "/bin/zsh", f"{dest}/codex-notify.sh" ]
m = re.search(r'^notify\s*=\s*(\[.*?\])\s*$', text, re.M)
if m:
    try:
        original = json.loads(m.group(1))
    except Exception:
        original = []
    if original != wrapper:
        open(f"{dest}/codex-original-notify", "w").write("\n".join(original))
        text = text[:m.start()] + "notify = " + json.dumps(wrapper) + text[m.end():]
else:
    # notify must be a top-level key: put it before the first [table]
    first_table = re.search(r'^\[', text, re.M)
    line = "notify = " + json.dumps(wrapper) + "\n"
    text = (text[:first_table.start()] + line + text[first_table.start():]) if first_table else (text + "\n" + line)
open(path, "w").write(text)
print("Codex notify chained")
PY
fi

# 3) zsh long-command + codex tracking
touch "$ZSHRC"
if ! grep -q "boring-island/island.zsh" "$ZSHRC"; then
  cp "$ZSHRC" "$ZSHRC.island-backup-$STAMP"
  printf '\n# Boring Notch island\n[[ -f ~/.boring-island/island.zsh ]] && source ~/.boring-island/island.zsh\n' >> "$ZSHRC"
  echo "zsh hook added (new terminal windows pick it up)"
fi
echo "done – run with --undo to restore the backups"
