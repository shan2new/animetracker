#!/usr/bin/env python3
"""Previously. — round seven: the ribbon only.

Everything is a polygon with true offsets and rounded corners (`offset_polygon`, `rounded`), so a
stroke is (outer offset) minus (inner offset) with the corner radii that a real stroke has, and no
corner on any tile is sharp — Aura has no sharp corner anywhere. Same rules as round six: one flat
ramp, no spheres, no glow, identical drawing on cream and night.

    ribbon.py                  # renders every variant into out3/
"""
import argparse
import math
from pathlib import Path

import numpy as np

from make import S, disc, polygon, ramp_color, _grid, Tile, solid, HERE
from make2 import RAMP, CREAM, NIGHT, GHOST_NIGHT, GHOST_CREAM_ALPHA, diag, union

OUT = HERE / "out3"
CORAL = RAMP[-1][1]
CREAM_INK = (0xFF, 0xF8, 0xEE)


# ---------------------------------------------------------------- polygon toolkit

def _area(pts):
    return sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1])) / 2


def _intersect(l1, l2):
    (x1, y1), (x2, y2) = l1
    (x3, y3), (x4, y4) = l2
    den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    if abs(den) < 1e-9:
        return (x2, y2)
    t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
    return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))


def offset_polygon(pts, d):
    """Every edge moved `d` outward (d < 0 inward), consecutive edges re-intersected."""
    n = len(pts)
    def build(sgn):
        lines = []
        for i in range(n):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
            dx, dy = x1 - x0, y1 - y0
            L = math.hypot(dx, dy)
            nx, ny = sgn * dy / L, -sgn * dx / L
            lines.append(((x0 + nx * d, y0 + ny * d), (x1 + nx * d, y1 + ny * d)))
        return [_intersect(lines[i - 1], lines[i]) for i in range(n)]
    a, b = build(1), build(-1)
    grows = abs(_area(a)) > abs(_area(pts))
    return a if (grows == (d > 0)) else b


def convexity(pts):
    """+1 for a convex vertex, -1 for a concave one, given the polygon's own orientation."""
    n = len(pts)
    orient = 1 if _area(pts) > 0 else -1
    out = []
    for i in range(n):
        (px, py), (x, y), (nx_, ny_) = pts[i - 1], pts[i], pts[(i + 1) % n]
        cross = (x - px) * (ny_ - y) - (y - py) * (nx_ - x)
        out.append(1 if cross * orient > 0 else -1)
    return out


def rounded(pts, radii, steps=24):
    """The polygon with each vertex replaced by a tangent arc of its radius (0 keeps it sharp)."""
    n = len(pts)
    out = []
    for i in range(n):
        r = radii[i] if isinstance(radii, (list, tuple)) else radii
        (px, py), (x, y), (qx, qy) = pts[i - 1], pts[i], pts[(i + 1) % n]
        if r <= 0:
            out.append((x, y)); continue
        ux, uy = px - x, py - y; Lu = math.hypot(ux, uy); ux, uy = ux / Lu, uy / Lu
        vx, vy = qx - x, qy - y; Lv = math.hypot(vx, vy); vx, vy = vx / Lv, vy / Lv
        cos_t = max(-1, min(1, ux * vx + uy * vy))
        theta = math.acos(cos_t)                      # interior angle between the two edges
        if theta > math.pi - 1e-3:
            out.append((x, y)); continue
        t = r / math.tan(theta / 2)
        tmax = 0.5 * min(Lu, Lv)
        if t > tmax:
            t = tmax; r = t * math.tan(theta / 2)
        t1 = (x + ux * t, y + uy * t)
        t2 = (x + vx * t, y + vy * t)
        bx, by = ux + vx, uy + vy; Lb = math.hypot(bx, by); bx, by = bx / Lb, by / Lb
        c = (x + bx * r / math.sin(theta / 2), y + by * r / math.sin(theta / 2))
        a1 = math.atan2(t1[1] - c[1], t1[0] - c[0])
        a2 = math.atan2(t2[1] - c[1], t2[0] - c[0])
        da = (a2 - a1 + math.pi) % (2 * math.pi) - math.pi
        for k in range(steps + 1):
            a = a1 + da * k / steps
            out.append((c[0] + r * math.cos(a), c[1] + r * math.sin(a)))
    return out


def fill(pts, radii=0):
    return polygon(rounded(pts, radii))


def stroke(pts, radii, w):
    """A stroke of width w centred on the polygon's edges, with a real stroke's corner radii."""
    conv = convexity(pts)
    r = [radii[i] if isinstance(radii, (list, tuple)) else radii for i in range(len(pts))]
    outer = offset_polygon(pts, w / 2)
    inner = offset_polygon(pts, -w / 2)
    r_out = [max(0, ri + (w / 2 if c > 0 else -w / 2)) for ri, c in zip(r, conv)]
    r_in = [max(0, ri + (-w / 2 if c > 0 else w / 2)) for ri, c in zip(r, conv)]
    return np.clip(fill(outer, r_out) - fill(inner, r_in), 0, 1)


# ---------------------------------------------------------------- the ribbon

def ribbon_pts(x0, y0, w, h, depth):
    """Bookmark polygon, clockwise from the top-left: top edge, right side, tail, apex, tail."""
    return [(x0, y0), (x0 + w, y0), (x0 + w, y0 + h), (x0 + w / 2, y0 + h - depth), (x0, y0 + h)]


def ribbon_radii(w, top=0.20, tip=0.045, apex=0.035):
    return [top * w, top * w, tip * w, apex * w, tip * w]


LIGHT_DIR = math.radians(-135)   # the light sits top-left


def angular(cx, cy, hot=RAMP[0][1], mid=RAMP[1][1], far=RAMP[2][1]):
    """Colour by angle around (cx, cy): `hot` toward the light, `mid` across, `far` away — Aura's ramp."""
    x, y = _grid()
    a = 0.5 + 0.5 * np.cos(np.arctan2(y - cy, x - cx) - LIGHT_DIR)
    return ramp_color(1 - a, RAMP)


def centroid(mask):
    x, y = _grid()
    m = mask.sum()
    return float((x * mask).sum() / m), float((y * mask).sum() / m)


def settle(pts, target_y=0.485 * S):
    """Shift a polygon so its mass centre sits at the tile's optical centre (a notch lifts it)."""
    m = fill(pts)
    _, cy = centroid(m)
    dy = target_y - cy
    return [(x, y + dy) for x, y in pts], dy


def ghost(t, mask, bbox, dark):
    if dark:
        t.paint(mask, solid(GHOST_NIGHT[0]), GHOST_NIGHT[1])
    else:
        t.paint(mask, diag(bbox), GHOST_CREAM_ALPHA)


def v_base(t, dark, ramp="diag"):
    """base — the solid ribbon: rounded tips and apex, mass-centred, the hole at the upper third."""
    w, h = 456, 700
    x0, y0 = 512 - w / 2, 512 - h / 2
    pts, dy = settle(ribbon_pts(x0, y0, w, h, 0.21 * h))
    y0 += dy
    body = fill(pts, ribbon_radii(w))
    hole = disc(512, y0 + 0.27 * h, 86)
    field = diag((x0, y0, x0 + w, y0 + h)) if ramp == "diag" else angular(512, y0 + h / 2)
    t.paint(np.clip(body - hole, 0, 1), field)


def v_dot(t, dark, hole=False, knockout=False):
    """dot — “Ribbon.”: the bookmark followed by its full stop, the way the wordmark ends."""
    w, h = 396, 660
    dot_r, gap = 76, 62
    total = w + gap + 2 * dot_r
    x0 = 512 - total / 2
    y0 = 512 - h / 2
    pts, dy = settle(ribbon_pts(x0, y0, w, h, 0.21 * h), 0.50 * S)
    y0 += dy
    body = fill(pts, ribbon_radii(w))
    if hole:
        body = np.clip(body - disc(x0 + w / 2, y0 + 0.27 * h, 76), 0, 1)
    period = disc(x0 + total - dot_r, y0 + h - dot_r, dot_r)
    if knockout and not dark:
        t.paint(np.ones((S, S), dtype=np.float32), diag((0, 0, S, S)))
        t.paint(union(body, period), solid(CREAM_INK))
        return
    t.paint(body, diag((x0, y0, x0 + w, y0 + h)))
    t.paint(period, solid(CORAL))


def v_taper(t, dark):
    """taper — the ribbon a touch wider at the top than at its tails, so it hangs rather than stands."""
    wt, wb, h = 470, 420, 700
    y0 = 512 - h / 2
    pts = [(512 - wt / 2, y0), (512 + wt / 2, y0), (512 + wb / 2, y0 + h), (512, y0 + h - 0.21 * h), (512 - wb / 2, y0 + h)]
    pts, dy = settle(pts)
    y0 += dy
    body = fill(pts, [0.20 * wt, 0.20 * wt, 0.045 * wb, 0.035 * wb, 0.045 * wb])
    hole = disc(512, y0 + 0.27 * h, 86)
    t.paint(np.clip(body - hole, 0, 1), diag((512 - wt / 2, y0, 512 + wt / 2, y0 + h)))


def v_card_fill(t, dark):
    """card, filled — the still as a quiet plate with the solid ribbon hung over its edge."""
    cw, ch, rad = 700, 400, 96
    cx0, cy0 = 512 - cw / 2, 552 - ch / 2
    card = fill([(cx0, cy0), (cx0 + cw, cy0), (cx0 + cw, cy0 + ch), (cx0, cy0 + ch)], rad)
    ghost(t, card, (cx0, cy0, cx0 + cw, cy0 + ch), dark)
    rw, rh = 176, 360
    rx0, ry0 = cx0 + cw - 250, cy0 - 100
    rpts = ribbon_pts(rx0, ry0, rw, rh, 0.40 * rw)
    t.paint(fill(rpts, [0.17 * rw, 0.17 * rw, 0.08 * rw, 0.06 * rw, 0.08 * rw]), diag((rx0, ry0, rx0 + rw, ry0 + rh)))


def v_hang(t, dark, hole=True):
    """hang — the ribbon enters from the tile's top edge and hangs, the way a bookmark does."""
    w = 408
    x0, y0, h = 512 - w / 2, -60, 870
    pts = ribbon_pts(x0, y0, w, h, 0.36 * w)
    body = fill(pts, [0, 0, 0.045 * w, 0.035 * w, 0.045 * w])
    if hole:
        body = np.clip(body - disc(512, 470, 84), 0, 1)
    t.paint(body, diag((x0, 80, x0 + w, y0 + h)))


def v_hang_dot(t, dark):
    """hang. — the hanging ribbon with its full stop beside the tails."""
    w = 380
    x0, y0, h = 512 - w / 2 - 70, -60, 850
    pts = ribbon_pts(x0, y0, w, h, 0.36 * w)
    body = fill(pts, [0, 0, 0.045 * w, 0.035 * w, 0.045 * w])
    t.paint(body, diag((x0, 80, x0 + w, y0 + h)))
    dot_r = 74
    t.paint(disc(x0 + w + 58 + dot_r, y0 + h - dot_r, dot_r), solid(CORAL))


def v_hang_outline(t, dark):
    """hang, outlined — the hanging ribbon as one stroke, the coral dot inside it."""
    sw = 74
    w = 360
    x0, y0, h = 512 - w / 2, -120, 900
    pts = ribbon_pts(x0, y0, w, h, 0.36 * w)
    t.paint(stroke(pts, [0, 0, 0.09 * w, 0.06 * w, 0.09 * w], sw), diag((x0, 60, x0 + w, y0 + h)))
    t.paint(disc(512, 470, 70), solid(CORAL))


def v_fold(t, dark):
    """fold — the ribbon folded over at the top, the fold a mirrored ramp with a knockout crease."""
    w, h = 420, 700
    x0, y0 = 512 - w / 2, 512 - h / 2
    bbox = (x0, y0, x0 + w, y0 + h)
    pts = ribbon_pts(x0, y0, w, h, 0.20 * h)
    body = fill(pts, ribbon_radii(w))
    # the fold: the top band, its crease a diagonal falling to the right
    fy = y0 + 0.20 * h
    fold_pts = [(x0, y0), (x0 + w, y0), (x0 + w, fy + 34), (x0, fy - 34)]
    fold = fill(fold_pts, [0.20 * w, 0.20 * w, 0.03 * w, 0.03 * w])
    crease = fill(offset_polygon(fold_pts, 12), [0.20 * w + 12, 0.20 * w + 12, 0.03 * w + 12, 0.03 * w + 12])
    ground = solid(NIGHT if dark else CREAM)
    hole = disc(512, y0 + 0.52 * h, 80)
    t.paint(np.clip(body - hole, 0, 1), diag(bbox))
    t.paint(np.clip(crease - fold, 0, 1) * body, ground)            # the knockout line under the fold
    rev = diag((x0 + w, fy + 40, x0, y0))                              # the fold catches the light the other way
    t.paint(fold, rev)


def v_card(t, dark):
    """card — a 16:9 still with the ribbon hung over its edge: a saved show."""
    sw = 66
    cw, ch, rad = 660, 372, 96
    cx0, cy0 = 512 - cw / 2, 548 - ch / 2
    frame_pts = [(cx0, cy0), (cx0 + cw, cy0), (cx0 + cw, cy0 + ch), (cx0, cy0 + ch)]
    bbox = (cx0 - sw / 2, cy0 - 120, cx0 + cw + sw / 2, cy0 + ch + sw / 2)
    field = diag(bbox)
    frame = stroke(frame_pts, rad, sw)
    rw, rh = 150, 320
    rx0, ry0 = cx0 + cw - 210, cy0 - 96
    rpts = ribbon_pts(rx0, ry0, rw, rh, 0.42 * rw)
    ribbon = fill(rpts, [0.16 * rw, 0.16 * rw, 0.09 * rw, 0.07 * rw, 0.09 * rw])
    knock = fill(offset_polygon(rpts, 14), [0.16 * rw + 14, 0.16 * rw + 14, 0.09 * rw + 14, 0, 0.09 * rw + 14])
    ground = solid(NIGHT if dark else CREAM)
    t.paint(frame, field)
    t.paint(knock * frame, ground)                                    # the ribbon sits in front of the frame
    t.paint(ribbon, field)


def v_tally(t, dark):
    """tally — the outlined ribbon holding the season: two episodes watched, one to go."""
    sw = 72
    w, h = 400, 668
    x0, y0 = 512 - w / 2, 512 - h / 2
    pts = ribbon_pts(x0, y0, w, h, 0.19 * h)
    bbox = (x0 - sw / 2, y0 - sw / 2, x0 + w + sw / 2, y0 + h + sw / 2)
    t.paint(stroke(pts, [68, 68, 20, 14, 20], sw), diag(bbox))
    ys = [y0 + 0.24 * h, y0 + 0.42 * h, y0 + 0.60 * h]
    t.paint(disc(512, ys[0], 44), solid(CORAL))
    t.paint(disc(512, ys[1], 44), solid(CORAL))
    ghost(t, disc(512, ys[2], 44), bbox, dark)


def v_knockout(t, dark):
    """knockout — the tile is the ramp; the ribbon is cut out of it in cream, the hole showing the ramp."""
    if dark:
        return v_base(t, dark)
    t.paint(np.ones((S, S), dtype=np.float32), diag((0, 0, S, S)))
    w, h = 420, 690
    x0, y0 = 512 - w / 2, 512 - h / 2
    body = fill(ribbon_pts(x0, y0, w, h, 0.20 * h), ribbon_radii(w))
    hole = disc(512, y0 + 0.28 * h, 80)
    t.paint(np.clip(body - hole, 0, 1), solid(CREAM_INK))


def v_wide(t, dark):
    """wide — a broader, shorter bookmark that fills the square the way Aura's ring does."""
    w, h = 540, 640
    x0, y0 = 512 - w / 2, 512 - h / 2
    pts = ribbon_pts(x0, y0, w, h, 0.22 * h)
    body = fill(pts, [0.17 * w, 0.17 * w, 0.045 * w, 0.03 * w, 0.045 * w])
    hole = disc(512, y0 + 0.30 * h, 92)
    t.paint(np.clip(body - hole, 0, 1), diag((x0, y0, x0 + w, y0 + h)))


def v_outline(t, dark):
    """outline — round six's B with a real stroke's corners: rounded tips, rounded apex, one weight."""
    sw = 74
    w, h = 400, 668
    x0, y0 = 512 - w / 2, 512 - h / 2
    pts = ribbon_pts(x0, y0, w, h, 0.19 * h)
    bbox = (x0 - sw / 2, y0 - sw / 2, x0 + w + sw / 2, y0 + h + sw / 2)
    t.paint(stroke(pts, [68, 68, 22, 16, 22], sw), diag(bbox))
    t.paint(disc(512, y0 + 0.29 * h, 70), solid(CORAL))


VARIANTS = {
    "base": v_base,
    "dot": v_dot,
    "dot-hole": lambda t, dark: v_dot(t, dark, hole=True),
    "hang": v_hang,
    "hang-dot": v_hang_dot,
    "outline": v_outline,
    "card": v_card,
    "knockout": v_knockout,
    "knockout-dot": lambda t, dark: v_dot(t, dark, knockout=True),
    # kept for the record, not in the lineup: base-angular (the angular ramp pinches at a solid's
    # centre), taper (indistinguishable at 60 pt), card-fill (a plate with a small tab)
    "base-angular": lambda t, dark: v_base(t, dark, ramp="angular"),
    "taper": v_taper,
    "card-fill": v_card_fill,
}
LINEUP = ["base", "dot", "dot-hole", "hang", "hang-dot", "outline", "card", "knockout", "knockout-dot"]


def render(name, dark):
    t = Tile(NIGHT if dark else CREAM)
    VARIANTS[name](t, dark)
    return t.image()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=LINEUP)
    args = ap.parse_args()
    OUT.mkdir(exist_ok=True)
    for name in args.only:
        for dark in (False, True):
            render(name, dark).save(OUT / f"{name}-{'dark' if dark else 'light'}.png")
    print("rendered", args.only)


if __name__ == "__main__":
    main()
