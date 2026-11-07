#!/usr/bin/env python3
"""MacIsle local-AI gateway.

A tiny always-on proxy (a few MB) in front of `mlx_lm.server`. The 35B model is loaded
only when MacIsle actually asks something, and unloaded after IDLE_MINUTES without use,
so ~19 GB of memory isn't held all day.

  GET  /health                 -> {"backend": "stopped|loading|ready", "model": "..."}
  POST /v1/chat/completions    -> proxied (streaming supported) to the model server

Environment:
  MACISLE_MODEL       model folder   (default ~/.local/share/Qwen36-MLX/model)
  MACISLE_MLX_SERVER  mlx_lm.server  (default ~/.local/share/Qwen36-MLX/py312/bin/mlx_lm.server)
  MACISLE_PORT        gateway port   (default 8737)
  MACISLE_IDLE_MIN    unload after   (default 5)
"""
import http.client, http.server, json, os, socketserver, subprocess, threading, time

HOME = os.path.expanduser("~")
MODEL = os.environ.get("MACISLE_MODEL", f"{HOME}/.local/share/Qwen36-MLX/model")
SERVER = os.environ.get("MACISLE_MLX_SERVER", f"{HOME}/.local/share/Qwen36-MLX/py312/bin/mlx_lm.server")
PORT = int(os.environ.get("MACISLE_PORT", "8737"))
BACKEND_PORT = PORT + 1
IDLE = float(os.environ.get("MACISLE_IDLE_MIN", "5")) * 60

lock = threading.Lock()
proc = None
state = "stopped"
last_used = time.time()
active = 0


def backend_alive():
    try:
        c = http.client.HTTPConnection("127.0.0.1", BACKEND_PORT, timeout=1)
        c.request("GET", "/v1/models")
        ok = c.getresponse().status == 200
        c.close()
        return ok
    except Exception:
        return False


def ensure_backend():
    """Start mlx_lm.server if needed and wait until it answers."""
    global proc, state
    with lock:
        if proc is None or proc.poll() is not None:
            env = dict(os.environ, HF_HUB_OFFLINE="1", HF_HUB_DISABLE_TELEMETRY="1")
            proc = subprocess.Popen([SERVER, "--model", MODEL, "--host", "127.0.0.1", "--port", str(BACKEND_PORT)],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
            state = "loading"
    for _ in range(240):
        if backend_alive():
            if state != "ready":
                state = "warming"
            return True
        if proc.poll() is not None:
            state = "stopped"
            return False
        time.sleep(0.5)
    return False


def reaper():
    """Unload the model after a period of inactivity."""
    global proc, state
    while True:
        time.sleep(20)
        with lock:
            if proc and proc.poll() is None and active == 0 and time.time() - last_used > IDLE:
                proc.terminate()
                try:
                    proc.wait(10)
                except Exception:
                    proc.kill()
                proc, state = None, "stopped"


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/health"):
            running = proc is not None and proc.poll() is None
            self._json(200, {"backend": state if running else "stopped", "model": os.path.basename(os.path.dirname(MODEL)) or MODEL,
                             "idle_minutes": IDLE / 60, "installed": os.path.exists(SERVER) and os.path.exists(MODEL)})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        global last_used, active, state
        if not self.path.startswith("/v1/"):
            return self._json(404, {"error": "not found"})
        body = self.rfile.read(int(self.headers.get("Content-Length", "0") or 0))
        active += 1
        last_used = time.time()
        try:
            if not ensure_backend():
                return self._json(503, {"error": "model failed to start"})
            c = http.client.HTTPConnection("127.0.0.1", BACKEND_PORT, timeout=600)
            c.request("POST", self.path, body, {"Content-Type": "application/json"})
            r = c.getresponse()
            self.send_response(r.status)
            self.send_header("Content-Type", r.getheader("Content-Type", "application/json"))
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            while True:
                chunk = r.read1(4096) if hasattr(r, "read1") else r.read(4096)
                if not chunk:
                    break
                self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
            state = "ready"
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            active -= 1
            last_used = time.time()


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    threading.Thread(target=reaper, daemon=True).start()
    Server(("127.0.0.1", PORT), Handler).serve_forever()
