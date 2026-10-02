"""Read-only audit fixtures. No database, credentials, real accounts or upstream calls.

Run: python3 fixture-server.py
Set fixture-mode.txt to empty or populated. Bind only to loopback.
All dates/counts are synthetic; these captures prove rendering, not live catalogue accuracy.
"""
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

HERE = Path(__file__).parent
NOW = int(time.time() * 1000)
DAY = 86400000

def title(fid, name, source, mid, progress, releasing):
    part = dict(mediaId=mid, kind="season", sequence=1, label="Season 1",
                title=name, format="TV", status="RELEASING" if releasing else "FINISHED",
                isReleasing=releasing, totalEpisodes=12, airedEpisodes=8 if releasing else 12,
                progress=progress, genres=["Adventure"], studios=["Audit fixture"], year=2026,
                episodes=[dict(number=n, title=f"Episode {n}", overview="Synthetic audit data.") for n in range(1, 13)],
                airings=[dict(episode=8, at=NOW-DAY), dict(episode=9, at=NOW+DAY)] if releasing else [])
    if releasing:
        part.update(nextEpisodeNumber=9, nextAiringAt=NOW+DAY, lastAiredAt=NOW-DAY,
                    release=dict(precision="exact", at=NOW+DAY))
    return dict(id=fid, title=name, source=source, parts=[part], year=2026,
                isReleasing=releasing, genres=["Adventure"], studios=["Audit fixture"],
                status="watching", behind=max(0, part["airedEpisodes"]-progress), newParts=0,
                subscription=dict(status="watching", addedAt=NOW-30*DAY),
                synopsis="Synthetic audit fixture. No live account or catalogue data.")

LIBRARY = [title("audit-anime", "Audit Anime", "anilist", 10001, 7, True),
           title("audit-tv", "Audit TV", "tmdb", 10002, 4, False)]

def current_library():
    mode = (HERE / "fixture-mode.txt").read_text().strip() if (HERE / "fixture-mode.txt").exists() else "empty"
    return LIBRARY if mode == "populated" else []

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)

    def handle_request(self):
        parsed = urlparse(self.path)
        path, query = parsed.path, parse_qs(parsed.query)
        library = current_library()
        code = 200
        body = {"ok": True}
        if path == "/me/library":
            body = dict(franchises=library, prevOpenedAt=NOW-3*DAY)
        elif path == "/me/opened":
            body = dict(prevOpenedAt=NOW-3*DAY)
        elif path == "/me/recommendations":
            body = dict(items=[], generatedAt=NOW)
        elif path == "/me/feed":
            posts = [dict(id="audit-post", franchiseId="audit-anime", kind="dated", origin="catalogue",
                          installment="Season 2", fresh=True, discoveredAt=NOW,
                          time=dict(at=NOW, dateOnly=False, basis="catalogue"),
                          premiere=dict(at=NOW+30*DAY, precision="exact"),
                          sources=[], viewer={}, counts={})] if library else []
            body = dict(tab=query.get("tab", ["following"])[0], generatedAt=NOW,
                        prevOpenedAt=NOW-3*DAY, capabilities=dict(comments=False),
                        franchises=library, posts=posts, trending=[])
        elif path == "/me/profile":
            body = dict(userId="audit-user", handle=None, displayName=None,
                        currentTermsVersion="audit", canComment=False)
        elif path in ["/me/hides", "/me/saves", "/me/blocks"]:
            body = dict(items=[], franchises=[])
        elif path == "/me/reminders":
            body = dict(items=[], franchises=[])
        elif path == "/me/notifications":
            body = dict(items=[], unread=0)
        elif path in ["/franchises/trending", "/search"] or path.startswith("/discover/genres/"):
            body = dict(franchises=LIBRARY, sources=dict(anilist="ok", tmdb="ok"))
        elif path == "/discover/genres":
            body = dict(genres=[dict(key="adventure", name="Adventure", count=2, posters=[])], generatedAt=NOW)
        elif path.startswith("/franchises/"):
            if path.endswith("/watch-providers"):
                body = dict(country="IN", providers=[], link=None)
            else:
                body = next((f for f in LIBRARY if f["id"] == path.split("/")[2]), LIBRARY[0])
        elif path == "/me" and self.command == "DELETE":
            code, body = 405, dict(error="Audit harness never performs account deletion")
        elif self.command not in ["GET", "POST"]:
            code, body = 405, dict(error="Read-only fixture harness")
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = handle_request
    do_POST = handle_request
    do_PUT = handle_request
    do_PATCH = handle_request
    do_DELETE = handle_request

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8799), Handler).serve_forever()
