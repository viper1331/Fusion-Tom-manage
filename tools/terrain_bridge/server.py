from __future__ import annotations

import json
import os
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse, unquote

ROOT = Path(__file__).resolve().parent / "data"
COMMANDS = ROOT / "commands"
RESULTS = ROOT / "results"
REPORTS = ROOT / "reports"
PUBLISH = ROOT / "publish"
LOG_FILE = ROOT / "bridge.log"
ACTIVITY_FILE = ROOT / "activity.json"
LOCK = threading.Lock()

for path in (COMMANDS, RESULTS, REPORTS, PUBLISH):
    path.mkdir(parents=True, exist_ok=True)


def read_json(path: Path):
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def write_json(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def now_text():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def log_event(event: str, **context):
    parts = [f"[{now_text()}]", event]
    for key, value in context.items():
        parts.append(f"{key}={value}")
    line = " ".join(parts)
    with LOCK:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with LOG_FILE.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")


def read_activity():
    data = read_json(ACTIVITY_FILE)
    if isinstance(data, dict):
        return data
    return {}


def update_activity(mutator):
    with LOCK:
        data = read_activity()
        if not isinstance(data.get("polls"), dict):
            data["polls"] = {}
        if not isinstance(data.get("results"), dict):
            data["results"] = {}
        if not isinstance(data.get("reports"), dict):
            data["reports"] = {}
        data["updatedAt"] = now_text()
        mutator(data)
        write_json(ACTIVITY_FILE, data)


def record_command_poll(computer: str, command_id: str, command_name: str):
    def mutator(data):
        stamp = now_text()
        data["lastCommandPoll"] = {
            "computer": computer,
            "id": command_id,
            "command": command_name,
            "at": stamp,
        }
        data["polls"][computer] = stamp

    update_activity(mutator)
    log_event("command_poll", computer=computer, id=command_id, command=command_name)


def record_result(computer: str, command_id: str, status: str):
    def mutator(data):
        stamp = now_text()
        data["lastResult"] = {
            "computer": computer,
            "id": command_id,
            "status": status,
            "at": stamp,
        }
        data["results"][computer] = stamp

    update_activity(mutator)
    log_event("result_post", computer=computer, id=command_id, status=status)


def record_report(computer: str, label: str):
    def mutator(data):
        stamp = now_text()
        data["lastReport"] = {
            "computer": computer,
            "label": label,
            "at": stamp,
        }
        data["reports"][computer] = stamp

    update_activity(mutator)
    log_event("report_post", computer=computer, label=label)


def record_ack(computer: str, command_id: str, ok: bool, detail: str):
    def mutator(data):
        data["lastAck"] = {
            "computer": computer,
            "id": command_id,
            "ok": bool(ok),
            "detail": detail,
            "at": now_text(),
        }

    update_activity(mutator)
    log_event("command_ack", computer=computer, id=command_id, ok=ok, detail=detail)


def clear_command(computer: str, expected_id: str):
    target = COMMANDS / f"{computer}.json"
    payload = read_json(target)
    if payload is None:
        return False, "not_found"
    current_id = str(payload.get("id", ""))
    if expected_id and current_id != expected_id:
        return False, "id_mismatch"
    target.unlink(missing_ok=True)
    return True, "cleared"


class Handler(BaseHTTPRequestHandler):
    server_version = "TerrainBridge/1.0"

    def _send_json(self, payload, status=200):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, path: Path):
        if not path.exists() or not path.is_file():
            self._send_json({"ok": False, "error": "not_found"}, status=404)
            return

        body = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._send_json({"ok": True, "service": "terrain_bridge", "status": "healthy"})
            return

        if parsed.path == "/activity":
            self._send_json(read_activity())
            return

        if parsed.path == "/command":
            params = parse_qs(parsed.query)
            computer = params.get("computer", ["fusion_terrain_01"])[0]
            target = COMMANDS / f"{computer}.json"
            payload = read_json(target) or {"id": "", "command": "noop"}
            command_id = str(payload.get("id", "") or "")
            command_name = str(payload.get("command", "") or "")
            record_command_poll(computer, command_id, command_name)
            self._send_json(payload)
            return

        if parsed.path.startswith("/publish/"):
            relative = parsed.path[len("/publish/"):]
            relative = unquote(relative)
            target = (PUBLISH / relative).resolve()
            if PUBLISH.resolve() not in target.parents and target != PUBLISH.resolve():
                self._send_json({"ok": False, "error": "invalid_path"}, status=400)
                return
            self._send_file(target)
            return

        self._send_json({"ok": True, "service": "terrain_bridge"})

    def do_POST(self):
        parsed = urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length > 0 else b"{}"

        try:
            payload = json.loads(raw.decode("utf-8"))
        except Exception:
            self._send_json({"ok": False, "error": "invalid_json"}, status=400)
            return

        if parsed.path == "/result":
            computer = payload.get("computerName") or payload.get("computer") or "unknown"
            command_id = payload.get("id") or payload.get("commandId") or "no-id"
            target = RESULTS / f"{computer}-{command_id}.json"
            write_json(target, payload)
            status = "ok" if payload.get("ok", False) else "error"
            record_result(str(computer), str(command_id), status)
            self._send_json({"ok": True})
            return

        if parsed.path == "/report":
            computer = payload.get("computerName") or payload.get("computer") or "unknown"
            label = payload.get("label") or payload.get("kind") or "report"
            raw_stamp = payload.get("sentAt") or payload.get("at") or "unknown"
            timestamp = str(raw_stamp).replace(":", "-").replace(" ", "_")
            target = REPORTS / f"{computer}-{label}-{timestamp}.json"
            write_json(target, payload)
            record_report(str(computer), str(label))
            self._send_json({"ok": True})
            return

        if parsed.path == "/command/ack":
            computer = str(payload.get("computer", "fusion_terrain_01"))
            command_id = str(payload.get("id", ""))
            ok, detail = clear_command(computer, command_id)
            status = 200 if ok else 409
            record_ack(computer, command_id, ok, detail)
            self._send_json({"ok": ok, "detail": detail, "computer": computer, "id": command_id}, status=status)
            return

        self._send_json({"ok": False, "error": "unknown_endpoint"}, status=404)


def main():
    host = os.environ.get("TERRAIN_BRIDGE_HOST", "127.0.0.1")
    port = int(os.environ.get("TERRAIN_BRIDGE_PORT", "8765"))
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"Terrain bridge listening on http://{host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
