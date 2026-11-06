#!/usr/bin/env python3
"""Send an event to the MacIsle without stealing focus.

Usage:
  island-notify.py claude            (Claude Code hook: JSON on stdin)
  island-notify.py codex <json>      (Codex `notify`: JSON as last argument)
  island-notify.py shell <event> <title> [status] [duration]
"""
import json, os, subprocess, sys, urllib.parse

def send(**params):
    params = {k: str(v) for k, v in params.items() if v not in (None, "")}
    params.setdefault("app", os.environ.get("TERM_PROGRAM", "") or ("claude-desktop" if os.environ.get("CLAUDE_CODE_ENTRYPOINT") == "claude-desktop" else ""))
    url = "macisle://agent?" + urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
    subprocess.run(["/usr/bin/open", "-g", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

STATE_DIR = os.path.expanduser("~/.macisle/state")

def changed(session, event, heartbeat=60):
    """True if this session's last reported event differs, or the last report is older than
    `heartbeat` seconds (so a long-running task keeps proving it's alive)."""
    import time
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        path = os.path.join(STATE_DIR, "".join(c for c in session if c.isalnum() or c in "-_")[:80] or "default")
        last, ts = "", 0.0
        if os.path.exists(path):
            parts = open(path).read().split("|")
            last = parts[0]
            ts = float(parts[1]) if len(parts) > 1 else 0.0
        now = time.time()
        if last == event and now - ts < heartbeat:
            return False
        open(path, "w").write(f"{event}|{now}")
    except Exception:
        pass
    return True

def short(text, n=40):
    text = " ".join((text or "").split())
    return text if len(text) <= n else text[: n - 1] + "…"

def claude():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    event = data.get("hook_event_name", "")
    cwd = data.get("cwd") or os.getcwd()
    title = os.path.basename(cwd.rstrip("/")) or "Claude Code"
    sid = data.get("session_id", title)
    if event == "UserPromptSubmit":
        changed(sid, "start")
        send(tool="claude", event="start", id=sid, title=title, detail=short(data.get("prompt", ""), 30))
    elif event == "Notification":
        msg = data.get("message", "")
        # Idle reminders are noise; permission / input requests are what matter.
        if "waiting for your input" in msg.lower():
            return
        changed(sid, "attention")
        send(tool="claude", event="attention", id=sid, title=title, detail=short(msg, 30))
    elif event in ("PostToolUse", "PreToolUse"):
        # Fires after you approve a permission request: back to "running" (once).
        if changed(sid, "start"):
            send(tool="claude", event="start", id=sid, title=title)
    elif event == "Stop":
        changed(sid, "done")
        send(tool="claude", event="done", id=sid, title=title)

def codex(args):
    if not args:
        return
    try:
        data = json.loads(args[-1])
    except Exception:
        return
    if data.get("type") != "agent-turn-complete":
        return
    cwd = data.get("cwd") or os.getcwd()
    title = os.path.basename(cwd.rstrip("/")) or "Codex"
    send(tool="codex", event="done", id=title, title=title, detail=short(data.get("last-assistant-message", ""), 30))

def shell(args):
    event, title = (args + ["done", "命令"])[:2]
    status = args[2] if len(args) > 2 else "0"
    duration = args[3] if len(args) > 3 else ""
    if title == "codex":
        # Same id as Codex's own turn-complete notification (project folder name).
        project = os.path.basename(os.getcwd().rstrip("/")) or "Codex"
        send(tool="codex", event=event, id=project, title=project)
        return
    send(tool="shell", event=event, id=f"shell.{title}", title=title, status=status, duration=duration)

if __name__ == "__main__":
    kind = sys.argv[1] if len(sys.argv) > 1 else ""
    rest = sys.argv[2:]
    if kind == "claude":
        claude()
    elif kind == "codex":
        codex(rest)
    elif kind == "shell":
        shell(rest)
