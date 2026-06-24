#!/usr/bin/env python3
"""Bespoke AniTrack tab-bar glyphs, hand-authored as vectors and rendered crisp via
rsvg-convert into transparent TEMPLATE imagesets (@1x/@2x/@3x). Shared language: solid
rounded forms with negative-space cutouts + rounded corners throughout, so they stay
razor-sharp at ~28pt and tint with the iOS 26 glass bar's selected/unselected states."""
import json, math, os, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
SVGDIR = os.path.join(HERE, "vector")
XCASSETS = os.path.normpath(os.path.join(HERE, "..", "..", "ios", "Resources", "Assets.xcassets"))
PT = 30
SCALES = [1, 2, 3]
RAD = 0.21          # shared corner roundness as a fraction of a form's smaller side
os.makedirs(SVGDIR, exist_ok=True)


def rr(x, y, w, h, r=None):
    """Rounded-rect as a path (so it can join an even-odd cutout group)."""
    if r is None:
        r = RAD * min(w, h)
    return (f"M{x+r},{y} H{x+w-r} A{r},{r} 0 0 1 {x+w},{y+r} V{y+h-r} "
            f"A{r},{r} 0 0 1 {x+w-r},{y+h} H{x+r} A{r},{r} 0 0 1 {x},{y+h-r} "
            f"V{y+r} A{r},{r} 0 0 1 {x+r},{y} Z")


def round_poly(pts, r):
    """Path for a polygon with every corner rounded by radius r (clamped to edges)."""
    n = len(pts)
    seg = []
    for i in range(n):
        v, p, nx = pts[i], pts[(i - 1) % n], pts[(i + 1) % n]
        def unit(a, b):
            dx, dy = a[0] - b[0], a[1] - b[1]
            d = math.hypot(dx, dy) or 1
            return (dx / d, dy / d), d
        (e1, d1), (e2, d2) = unit(p, v), unit(nx, v)
        rr_ = min(r, d1 / 2, d2 / 2)
        entry = (v[0] + e1[0] * rr_, v[1] + e1[1] * rr_)
        exit_ = (v[0] + e2[0] * rr_, v[1] + e2[1] * rr_)
        seg.append((entry, v, exit_))
    d = f"M{seg[0][0][0]:.3f},{seg[0][0][1]:.3f} "
    for i in range(n):
        _, v, ex = seg[i]
        d += f"Q{v[0]:.3f},{v[1]:.3f} {ex[0]:.3f},{ex[1]:.3f} "
        ne = seg[(i + 1) % n][0]
        d += f"L{ne[0]:.3f},{ne[1]:.3f} "
    return d + "Z"


def star(cx, cy, R, k):
    """4-point concave sparkle (the brand 'glint'); k pinches the waist toward center."""
    return (f"M{cx},{cy-R} Q{cx+k},{cy-k} {cx+R},{cy} Q{cx+k},{cy+k} {cx},{cy+R} "
            f"Q{cx-k},{cy+k} {cx-R},{cy} Q{cx-k},{cy-k} {cx},{cy-R} Z")


def mirror_x(pts, axis=12.0):
    return [(2 * axis - x, y) for x, y in pts]


def cross(cx, cy, a, t):
    return [(cx-t, cy-a), (cx+t, cy-a), (cx+t, cy-t), (cx+a, cy-t), (cx+a, cy+t),
            (cx+t, cy+t), (cx+t, cy+a), (cx-t, cy+a), (cx-t, cy+t), (cx-a, cy+t),
            (cx-a, cy-t), (cx-t, cy-t)]


# --- the four glyphs --------------------------------------------------------
# Today: a TV (what's on now) — a filled rounded screen on a center pedestal stand.
TODAY = f'''
  <path fill="#fff" d="{rr(7.6,17.4,8.8,1.9,0.95)}"/>
  <path fill="#fff" d="{round_poly([(10.7,15.5),(13.3,15.5),(14.0,17.8),(10.0,17.8)], 0.5)}"/>
  <path fill="#fff" d="{rr(3.5,4.6,17.0,11.4,2.9)}"/>'''

# Schedule: rounded calendar with binding tabs, header bar and a 3x2 day grid.
# (whole unit nudged down 0.4 so its optical center sits at the box center.)
_cells = " ".join(
    rr(5.5 + c * 5.0, 11.4 + r * 4.0, 3.4, 3.0, 0.95)
    for r in range(2) for c in range(3)
)
SCHEDULE = f'''
  <path fill="#fff" d="{rr(7.7,2.7,2,4,1)}"/>
  <path fill="#fff" d="{rr(14.3,2.7,2,4,1)}"/>
  <path fill="#fff" fill-rule="evenodd" d="
    {rr(3.6,5.4,16.8,15.6,3.4)}
    {rr(6.2,8.8,11.6,1.4,0.7)}
    {_cells}"/>'''

# Library: a solid media card with a rounded play mark, plus a SOLID card peeking
# behind it, separated by a clean transparent gap (mask) so all glyphs share one weight.
_front, _back, _moat = (4.3, 7.6, 12.4, 11.8), (7.3, 4.6, 12.4, 11.8), 0.95
LIBRARY = f'''
  <defs><mask id="libcut" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24">
    <rect x="0" y="0" width="24" height="24" fill="#fff"/>
    <path fill="#000" d="{rr(_front[0]-_moat,_front[1]-_moat,_front[2]+2*_moat,_front[3]+2*_moat,2.6)}"/>
  </mask></defs>
  <path fill="#fff" mask="url(#libcut)" d="{rr(*_back,2.6)}"/>
  <path fill="#fff" fill-rule="evenodd" d="
    {rr(*_front,2.6)}
    {round_poly([(8.9,10.9),(8.9,15.9),(13.6,13.4)], 0.7)}"/>'''

# Add: solid rounded square with a slightly slimmer, longer rounded plus cut out of it.
ADD = f'''
  <path fill="#fff" fill-rule="evenodd" d="
    {rr(4.3,4.3,15.4,15.4,3.4)}
    {round_poly(cross(12,12,4.7,1.4), 0.55)}"/>'''

GLYPHS = {"TabToday": TODAY, "TabSchedule": SCHEDULE, "TabLibrary": LIBRARY, "TabAdd": ADD}


def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">{body}</svg>'


def contents(name):
    return {
        "images": [{"idiom": "universal", "filename": f"{name}@{s}x.png", "scale": f"{s}x"} for s in SCALES],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "template"},
    }


for name, body in GLYPHS.items():
    svgpath = os.path.join(SVGDIR, f"{name}.svg")
    with open(svgpath, "w") as f:
        f.write(svg(body))
    outdir = os.path.join(XCASSETS, f"{name}.imageset")
    os.makedirs(outdir, exist_ok=True)
    for s in SCALES:
        px = PT * s
        subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px),
                        svgpath, "-o", os.path.join(outdir, f"{name}@{s}x.png")], check=True)
    with open(os.path.join(outdir, "Contents.json"), "w") as f:
        json.dump(contents(name), f, indent=2)
    print(f"{name}  ok")
print("done ->", XCASSETS)
