"""Shared drawing kit: signed distances at 1024, colours, the iOS tile."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont
S = 1024
Y, X = np.mgrid[0:S, 0:S].astype(np.float64) + 0.5
FONT = "/Users/shantanusinha/Desktop/workspace/animetracker/ios/Resources/Fonts/"

def aa(d): return np.clip(0.5 - d, 0, 1)
def hexc(h): return np.array([(h >> 16) & 255, (h >> 8) & 255, h & 255]) / 255.0
def rot(x, y, deg, cx=512, cy=512):
    t = math.radians(deg)
    return ((x - cx) * math.cos(t) - (y - cy) * math.sin(t) + cx, (x - cx) * math.sin(t) + (y - cy) * math.cos(t) + cy)
def rbox(x, y, x0, y0, x1, y1, r=0):
    cx, cy, hx, hy = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx, qy = np.abs(x - cx) - hx, np.abs(y - cy) - hy
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r
def circle(x, y, cx, cy, r): return np.hypot(x - cx, y - cy) - r
def seg(x, y, ax, ay, bx, by, r):
    ex, ey = bx - ax, by - ay; wx, wy = x - ax, y - ay
    t = np.clip((wx * ex + wy * ey) / (ex * ex + ey * ey), 0, 1)
    return np.hypot(wx - ex * t, wy - ey * t) - r
def arc(x, y, cx, cy, R, a0, a1, r):
    ang = np.degrees(np.arctan2(y - cy, x - cx)) % 360; a0 %= 360; a1 %= 360
    inside = (ang >= a0) & (ang <= a1) if a0 <= a1 else (ang >= a0) | (ang <= a1)
    ring = np.abs(np.hypot(x - cx, y - cy) - R) - r
    p0 = (cx + R * math.cos(math.radians(a0)), cy + R * math.sin(math.radians(a0)))
    p1 = (cx + R * math.cos(math.radians(a1)), cy + R * math.sin(math.radians(a1)))
    caps = np.minimum(np.hypot(x - p0[0], y - p0[1]) - r, np.hypot(x - p1[0], y - p1[1]) - r)
    return np.where(inside, ring, caps)
def poly(x, y, pts):
    pts = np.array(pts, dtype=np.float64); d = np.full(x.shape, np.inf); s = np.ones(x.shape); n = len(pts)
    for i in range(n):
        ax, ay = pts[i]; bx, by = pts[(i + 1) % n]; ex, ey = bx - ax, by - ay; wx, wy = x - ax, y - ay
        t = np.clip((wx * ex + wy * ey) / (ex * ex + ey * ey), 0, 1); dx, dy = wx - ex * t, wy - ey * t
        d = np.minimum(d, dx * dx + dy * dy)
        c1 = y >= ay; c2 = y < by; c3 = ex * wy > ey * wx
        s = np.where((c1 & c2 & c3) | (~c1 & ~c2 & ~c3), -s, s)
    return s * np.sqrt(d)
def polyline(x, y, pts, r):
    d = np.full(x.shape, np.inf)
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        d = np.minimum(d, seg(x, y, ax, ay, bx, by, 0))
    return d - r
def catmull(pts, n=16):
    pts = [pts[0]] + list(pts) + [pts[-1]]; out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = (np.array(p) for p in pts[i - 1:i + 3])
        for t in np.linspace(0, 1, n, endpoint=False):
            out.append(tuple(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)))
    out.append(tuple(pts[-2])); return out
U = np.minimum
def minus(a, b): return np.maximum(a, -b)
def ground(c, fall=0.05):
    return hexc(c)[None, None, :] * np.ones((S, S, 1)) * (1 + fall * (0.5 - Y / S))[..., None]
def paint(base, cov, col):
    col = np.asarray(col)
    if col.ndim == 1: col = col[None, None, :]
    return base * (1 - cov[..., None]) + col * cov[..., None]
def text_mask(txt, font_path, size, cx, cy, index=0):
    im = Image.new("L", (S, S), 0); d = ImageDraw.Draw(im)
    f = ImageFont.truetype(font_path, size, index=index)
    d.text((cx, cy), txt, font=f, fill=255, anchor="mm")
    return np.asarray(im, dtype=np.float64) / 255
def finish(rgb):
    out = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).convert("RGBA")
    m = Image.new("L", (S * 2, S * 2), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, S * 2 - 1, S * 2 - 1], radius=int(S * 2 * 0.2237), fill=255)
    out.putalpha(m.resize((S, S), Image.LANCZOS)); return out
