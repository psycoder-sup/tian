#!/usr/bin/env python3
"""Live dashboard server for the project-kit context docs.

Serves `docs/pm/` (the parent of this folder) over HTTP so the dashboard can
fetch the JSON sources, and pushes a live-reload event over Server-Sent Events
whenever any JSON under `docs/pm/` changes on disk.

Stdlib only — no pip installs. Run it and a browser opens on the dashboard:

    python3 docs/pm/dashboard/serve.py
    python3 docs/pm/dashboard/serve.py --port 9000   # pick a port
    python3 docs/pm/dashboard/serve.py --no-open      # don't open a browser
"""

import argparse
import json
import os
import sys
import threading
import time
import webbrowser
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

# Document root = docs/pm/ (the parent of this dashboard/ folder). Everything is
# served relative to it: /dashboard/index.html, /status.json, /decisions/*.json …
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Files the dashboard knows how to render at the docs/pm root.
KNOWN_DOCS = {"status": "status.json", "summary": "project-summary.json", "prd": "prd.json"}


def iter_json_files():
    """Every *.json under ROOT (used both for the manifest and the mtime watch)."""
    for dirpath, _dirs, files in os.walk(ROOT):
        for name in files:
            if name.endswith(".json"):
                yield os.path.join(dirpath, name)


def snapshot_mtimes():
    """Map of json path -> mtime, for change detection."""
    snap = {}
    for path in iter_json_files():
        try:
            snap[path] = os.path.getmtime(path)
        except OSError:
            pass
    return snap


def build_manifest():
    """Describe what exists so the dashboard can discover docs and ADRs."""
    docs = {key: os.path.isfile(os.path.join(ROOT, fname)) for key, fname in KNOWN_DOCS.items()}

    decisions = []
    dec_dir = os.path.join(ROOT, "decisions")
    if os.path.isdir(dec_dir):
        for name in sorted(os.listdir(dec_dir)):
            if not name.endswith(".json") or name.startswith("_"):
                continue
            rel = "decisions/" + name
            entry = {"file": rel, "number": None, "title": name, "status": ""}
            try:
                with open(os.path.join(dec_dir, name), encoding="utf-8") as fh:
                    data = json.load(fh)
                entry["number"] = data.get("number")
                entry["title"] = data.get("title", name)
                entry["status"] = data.get("status", "")
            except (OSError, ValueError):
                pass
            decisions.append(entry)
        decisions.sort(key=lambda d: (d["number"] is None, d["number"] or 0))

    return {"docs": docs, "decisions": decisions}


class Handler(SimpleHTTPRequestHandler):
    # Quieter logging — one line per request is noisy for a dashboard poller.
    def log_message(self, fmt, *args):
        if "/events" not in (self.path or ""):
            sys.stderr.write("  %s\n" % (fmt % args))

    def do_GET(self):
        if self.path == "/":
            self.send_response(302)
            self.send_header("Location", "/dashboard/")
            self.end_headers()
            return
        if self.path.split("?")[0] == "/api/index":
            self._send_json(build_manifest())
            return
        if self.path.split("?")[0] == "/events":
            self._stream_events()
            return
        super().do_GET()

    def _send_json(self, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _stream_events(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        last = snapshot_mtimes()
        try:
            self.wfile.write(b": connected\n\n")
            self.wfile.flush()
            while True:
                time.sleep(1)
                current = snapshot_mtimes()
                if current != last:
                    last = current
                    self.wfile.write(b"data: reload\n\n")
                else:
                    # Comment line as a keep-alive so proxies don't time out.
                    self.wfile.write(b": ping\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            return  # client closed the tab — nothing to clean up


def serve(port, open_browser):
    handler = partial(Handler, directory=ROOT)
    last_err = None
    for candidate in range(port, port + 20):
        try:
            httpd = ThreadingHTTPServer(("127.0.0.1", candidate), handler)
        except OSError as err:
            last_err = err
            continue
        url = "http://127.0.0.1:%d/dashboard/" % candidate
        print("project-kit dashboard serving %s" % ROOT)
        print("  -> %s   (Ctrl-C to stop)" % url)
        if open_browser:
            threading.Timer(0.4, lambda: webbrowser.open(url)).start()
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped.")
        finally:
            httpd.server_close()
        return
    raise SystemExit("could not bind a port in range %d-%d: %s" % (port, port + 19, last_err))


def main():
    parser = argparse.ArgumentParser(description="Live dashboard for project-kit context docs.")
    parser.add_argument("--port", type=int, default=8787, help="port to serve on (default 8787; auto-bumps if busy)")
    parser.add_argument("--no-open", action="store_true", help="do not open a browser window")
    args = parser.parse_args()
    serve(args.port, open_browser=not args.no_open)


if __name__ == "__main__":
    main()
