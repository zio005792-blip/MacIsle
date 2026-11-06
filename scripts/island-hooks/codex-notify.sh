#!/bin/zsh
# Codex `notify` wrapper: keeps the previously configured notifier, then tells the island.
# The original command is stored in ~/.macisle/codex-original-notify (one argument per line).
ORIG="$HOME/.macisle/codex-original-notify"
if [[ -f "$ORIG" ]]; then
  cmd=("${(@f)$(<"$ORIG")}")
  [[ ${#cmd} -gt 0 ]] && "${cmd[@]}" "$@" >/dev/null 2>&1 &
fi
/usr/bin/python3 "$HOME/.macisle/island-notify.py" codex "$@"
wait
