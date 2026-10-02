"""Loopback native-app visual preview using a read-only real catalogue snapshot.

Empty-account and read-only real-library snapshots can be selected for scouting.
The app signs into a loopback shell without production credentials. Writes are
refused except the inert local visit handshake, which has no effect. This server has no database connection and makes no upstream calls.
"""
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

CATALOG = json.loads((Path(__file__).parent / "catalog-snapshot.json").read_text())
SCOUT = Path(__file__).parent / "scout"

def library():
    mode = (SCOUT / "preview-mode.txt").read_text().strip() if (SCOUT / "preview-mode.txt").exists() else "empty"
    path = SCOUT / "library-snapshot.local.json"
    return json.loads(path.read_text()) if mode == "populated" and path.exists() else {}

class Handler(BaseHTTPRequestHandler):
    def reply(self, value, status=200):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        request = urlsplit(self.path)
        source = parse_qs(request.query).get("source", [None])[0]
        key = request.path + (f"?source={source}" if source else "")
        real = library()
        if request.path in real:
            return self.reply(real[request.path])
        if key in CATALOG:
            return self.reply(CATALOG[key])
        if request.path == "/me/library":
            return self.reply({"franchises": [], "prevOpenedAt": 0})
        if request.path == "/me/recommendations":
            return self.reply({"items": [], "generatedAt": int(time.time() * 1000)})
        if request.path == "/me/feed":
            tab = parse_qs(request.query).get("tab", ["following"])[0]
            if f"/me/feed?tab={tab}" in real:
                return self.reply(real[f"/me/feed?tab={tab}"])
            return self.reply({"tab": tab, "generatedAt": int(time.time() * 1000), "prevOpenedAt": 0,
                               "capabilities": {"comments": False}, "franchises": [], "posts": [], "trending": []})
        if request.path == "/me/profile":
            return self.reply({"userId": "artwork-preview-local", "handle": None, "displayName": None,
                               "currentTermsVersion": "2026-09-03", "canComment": False})
        if request.path in ("/me/hides", "/me/saved", "/me/blocks"):
            return self.reply({"items": [], "franchises": []})
        if request.path == "/me/reminders":
            return self.reply({"items": [], "franchises": []})
        if request.path == "/me/notifications":
            return self.reply({"items": [], "unread": 0})
        return self.reply({"error": "Route outside artwork preview"}, 404)

    def do_POST(self):
        if urlsplit(self.path).path == "/me/opened":
            return self.reply({"lastOpenedAt": int(time.time() * 1000), "prevOpenedAt": 0})
        return self.reply({"error": "Artwork preview refuses writes"}, 405)

    def do_PUT(self):
        self.reply({"error": "Artwork preview refuses writes"}, 405)

    do_DELETE = do_PUT
    do_PATCH = do_PUT

print("Real-catalogue artwork preview: http://localhost:18789", flush=True)
ThreadingHTTPServer(("127.0.0.1", 18789), Handler).serve_forever()
