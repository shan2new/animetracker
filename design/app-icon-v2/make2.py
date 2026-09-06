#!/usr/bin/env python3
"""Previously. — round six: stroke-built marks, no spheres, no glow.

What round five got wrong next to Aura: a lit ball with a highlight and a blur bloom under it on
every tile (the Aqua tell), an amber-to-brown ramp on beige, strokes twice Aura's weight with no
rhythm. Aura's discipline: strokes at ~6 % of the tile with round joins, one flat hue-shifting
ramp, a fainter echo layer for depth, and the identical drawing on both grounds.

    make2.py            # renders every direction into out2/
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from make import S, SS, sc, _L, _down, disc, rrect, polygon, ramp_color, _grid, Tile, solid, HERE

OUT = HERE / "out2"

CREAM = (0xF5, 0xF1, 0xEA)
NIGHT = (0x12, 0x10, 0x10)
# gold -> amber -> coral: the brand's amber in the middle, a hue shift either side, no brown anywhere
RAMP = [(0.00, (0xFF, 0xC5, 0x52)), (0.50, (0xF3, 0x90, 0x3E)), (1.00, (0xE2, 0x4E, 0x3F))]
GHOST_NIGHT = ((0xF4, 0xF1, 0xEC), 0.13)   # the unfilled part of a track on the night ground
GHOST_CREAM_ALPHA = 0.22                    # on cream it is the ramp, faint


def diag(bbox, ramp=RAMP):
    x0, y0, x1, y1 = bbox
    x, y = _grid()
    t = ((x - x0) / (x1 - x0) + (y - y0) / (y1 - y0)) / 2
    return ramp_color(t, ramp)


def stroke_path(points, w, closed=False):
    """A stroked polyline, round joins and caps, drawn at 4x."""
    m = _L()
    d = ImageDraw.Draw(m)
    pts = [(sc(x), sc(y)) for x, y in points]
    if closed:
        pts = pts + pts[:2]
    d.line(pts, fill=255, width=int(sc(w)), joint="curve")
    for x, y in ([pts[0], pts[-1]] if not closed else []):
        d.ellipse([x - sc(w) / 2, y - sc(w) / 2, x + sc(w) / 2, y + sc(w) / 2], fill=255)
    return _down(m)


def seg(p0, p1, w):
    """One straight stroke with round caps — a single PIL line has no join to seam."""
    m = _L()
    d = ImageDraw.Draw(m)
    (x0, y0), (x1, y1) = p0, p1
    d.line([(sc(x0), sc(y0)), (sc(x1), sc(y1))], fill=255, width=int(sc(w)))
    for x, y in (p0, p1):
        d.ellipse([sc(x - w / 2), sc(y - w / 2), sc(x + w / 2), sc(y + w / 2)], fill=255)
    return _down(m)


def arc_band(cx, cy, r, w, a0, a1, caps=True):
    """A stroked arc as an annulus sector: outer pieslice minus inner disc, round caps."""
    m = _L()
    d = ImageDraw.Draw(m)
    ro, ri = r + w / 2, r - w / 2
    d.pieslice([sc(cx - ro), sc(cy - ro), sc(cx + ro), sc(cy + ro)], a0, a1, fill=255)
    d.ellipse([sc(cx - ri), sc(cy - ri), sc(cx + ri), sc(cy + ri)], fill=0)
    if caps:
        for a in (a0, a1):
            t = np.radians(a)
            px, py = cx + r * np.cos(t), cy + r * np.sin(t)
            d.ellipse([sc(px - w / 2), sc(py - w / 2), sc(px + w / 2), sc(py + w / 2)], fill=255)
    return _down(m)


def union(*masks):
    return np.clip(sum(masks), 0, 1)


def arc_points(cx, cy, r, a0, a1, n=64):
    return [(cx + r * np.cos(np.radians(a)), cy + r * np.sin(np.radians(a))) for a in np.linspace(a0, a1, n)]


def ribbon_mask(x0, y0, w, h, rad, depth):
    """A bookmark: rounded top corners, square bottom corners, a V notch `depth` deep."""
    body = rrect(x0, y0, x0 + w, y0 + h + rad, rad)          # extend below, then cut flat + notch
    cut = polygon([(x0 - 4, y0 + h), (x0 + w / 2, y0 + h - depth), (x0 + w + 4, y0 + h),
                   (x0 + w + 4, y0 + h + rad + 8), (x0 - 4, y0 + h + rad + 8)])
    return np.clip(body - cut, 0, 1)


def ribbon_outline_points(x0, y0, w, h, rad, depth):
    """Centreline of a bookmark for stroking: arcs at the two top corners, a V at the foot."""
    pts = [(x0, y0 + h)]                                      # bottom-left corner
    pts += [(x0, y0 + rad)]
    pts += arc_points(x0 + rad, y0 + rad, rad, 180, 270, 24)  # top-left corner
    pts += [(x0 + w - rad, y0)]
    pts += arc_points(x0 + w - rad, y0 + rad, rad, 270, 360, 24)
    pts += [(x0 + w, y0 + h), (x0 + w / 2, y0 + h - depth)]
    return pts


# ---------------------------------------------------------------- directions

def ghost(t, mask, bbox, dark):
    if dark:
        t.paint(mask, solid(GHOST_NIGHT[0]), GHOST_NIGHT[1])
    else:
        t.paint(mask, diag(bbox), GHOST_CREAM_ALPHA)


def d_ribbon(t, dark):
    """Ribbon — the bookmark, solid, one ramp, a hole punched for the saved place (the ground shows through)."""
    w, h = 436, 700
    x0, y0 = 512 - w / 2, 512 - h / 2
    rad, depth = 0.19 * w, 0.20 * h
    body = ribbon_mask(x0, y0, w, h, rad, depth)
    hole = disc(512, y0 + 0.28 * h, 84)
    t.paint(np.clip(body - hole, 0, 1), diag((x0, y0, x0 + w, y0 + h)))


def d_ribbon_halo(t, dark):
    """Ribbon + halo — the solid ribbon with a fainter outline standing off it (Aura's echo ring)."""
    w, h = 356, 570
    x0, y0 = 512 - w / 2, 512 - h / 2 + 4
    rad, depth = 0.19 * w, 0.20 * h
    body = ribbon_mask(x0, y0, w, h, rad, depth)
    hole = disc(512, y0 + 0.28 * h, 70)
    # the halo: the same silhouette standing 56 px out, drawn as a 34 px stroke
    o, hw = 56, 34
    hx0, hy0, hwid = x0 - o, y0 - o, w + 2 * o
    hh = h + o * 1.25
    hrad = rad + o
    apex = hy0 + hh - depth - o * 0.55
    halo = union(
        seg((hx0, hy0 + hrad), (hx0, hy0 + hh), hw),
        seg((hx0 + hwid, hy0 + hrad), (hx0 + hwid, hy0 + hh), hw),
        seg((hx0 + hrad, hy0), (hx0 + hwid - hrad, hy0), hw),
        arc_band(hx0 + hrad, hy0 + hrad, hrad, hw, 180, 270),
        arc_band(hx0 + hwid - hrad, hy0 + hrad, hrad, hw, 270, 360),
        seg((hx0, hy0 + hh), (512, apex), hw),
        seg((hx0 + hwid, hy0 + hh), (512, apex), hw),
    )
    ghost(t, halo, (hx0, hy0, hx0 + hwid, hy0 + hh), dark)
    t.paint(np.clip(body - hole, 0, 1), diag((x0, y0, x0 + w, y0 + h)))


def d_ribbon_echo(t, dark):
    """Ribbon + echo — the same, with a fainter ribbon behind it, up and to the right: the one before."""
    w, h = 380, 610
    x0, y0 = 512 - w / 2 - 34, 512 - h / 2 + 30
    rad, depth = 0.19 * w, 0.20 * h
    bbox = (x0, y0, x0 + w + 68, y0 + h)
    back = ribbon_mask(x0 + 68, y0 - 62, w, h, rad, depth)
    front = ribbon_mask(x0, y0, w, h, rad, depth)
    ghost(t, np.clip(back - front, 0, 1), bbox, dark)
    hole = disc(x0 + w / 2, y0 + 0.28 * h, 74)
    t.paint(np.clip(front - hole, 0, 1), diag(bbox))


def d_ribbon_outline(t, dark, coral=False):
    """Ribbon, outlined — the bookmark as one stroke, the saved place a flat dot inside it (Aura's ring-and-bars anatomy)."""
    sw = 74
    w, h = 400, 668                                            # centreline box
    x0, y0 = 512 - w / 2, 512 - h / 2
    rad, depth = 68, 0.19 * h
    bbox = (x0 - sw / 2, y0 - sw / 2, x0 + w + sw / 2, y0 + h + sw / 2)
    field = diag(bbox)
    outline = union(
        seg((x0, y0 + rad), (x0, y0 + h), sw),                       # left side
        seg((x0 + w, y0 + rad), (x0 + w, y0 + h), sw),               # right side
        seg((x0 + rad, y0), (x0 + w - rad, y0), sw),                 # top
        arc_band(x0 + rad, y0 + rad, rad, sw, 180, 270),             # top-left corner
        arc_band(x0 + w - rad, y0 + rad, rad, sw, 270, 360),         # top-right corner
        seg((x0, y0 + h), (x0 + w / 2, y0 + h - depth), sw),         # notch, left leg
        seg((x0 + w, y0 + h), (x0 + w / 2, y0 + h - depth), sw),     # notch, right leg
    )
    t.paint(outline, field)
    dot = disc(512, y0 + 0.29 * h, 70)
    t.paint(dot, solid(RAMP[-1][1]) if coral else field)


def p_ribbon(t, dark, period):
    """P ribbon — the letter is the bookmark: a notched stem, a stroked bowl, one weight."""
    sw = 108                                                   # the stroke; the stem is a ribbon of the same width
    H = 724
    Rb = 158                                                   # bowl arc radius (centreline)
    L = 126                                                    # bowl's straight run from the stem
    top = 512 - H / 2
    bowl_h = 2 * Rb + sw
    pw = sw + L + Rb + sw / 2                                  # stem left edge -> bowl outer right edge
    dot_r, gap = 74, 68
    total = pw + (gap + 2 * dot_r if period else 0)
    left = 512 - total / 2
    sx = left + sw / 2                                         # stem centreline x
    # stem: a ribbon, square top with a small radius, notched foot
    stem = ribbon_mask(left, top, sw, H, 16, 0.80 * sw)
    # bowl: out of the stem's top, around, and back into the stem — one weight throughout
    cy = top + sw / 2
    bowl = union(seg((sx, cy), (sx + L, cy), sw),
                 arc_band(sx + L, cy + Rb, Rb, sw, -90, 90),
                 seg((sx + L, cy + 2 * Rb), (sx, cy + 2 * Rb), sw))
    bbox = (left, top, left + total, top + H)
    field = diag(bbox)
    t.paint(np.clip(stem + bowl, 0, 1), field)
    if period:
        t.paint(disc(left + total - dot_r, top + H - dot_r, dot_r), field)


def d_p(t, dark):
    p_ribbon(t, dark, period=False)


def d_p_dot(t, dark):
    p_ribbon(t, dark, period=True)


def d_ring(t, dark):
    """Ring — the MarkRing at Aura's weight: the watched arc in the ramp, the rest a ghost, no ball."""
    cx, cy, r, sw = 512, 512, 318, 80
    bbox = (cx - r - sw / 2, cy - r - sw / 2, cx + r + sw / 2, cy + r + sw / 2)
    ghost(t, arc_band(cx, cy, r, sw, 0, 360, caps=False), bbox, dark)
    t.paint(arc_band(cx, cy, r, sw, -90, 158), diag(bbox))


def d_frame(t, dark):
    """Frame — a 16:9 screen as one stroke, the coral dot in its corner: the light that says on."""
    sw = 70
    w, h, rad = 664, 428, 100                                  # centreline box
    x0, y0 = 512 - w / 2, 512 - h / 2
    bbox = (x0 - sw / 2, y0 - sw / 2, x0 + w + sw / 2, y0 + h + sw / 2)
    field = diag(bbox)
    frame = union(
        seg((x0 + rad, y0), (x0 + w - rad, y0), sw),
        seg((x0 + rad, y0 + h), (x0 + w - rad, y0 + h), sw),
        seg((x0, y0 + rad), (x0, y0 + h - rad), sw),
        seg((x0 + w, y0 + rad), (x0 + w, y0 + h - rad), sw),
        arc_band(x0 + rad, y0 + rad, rad, sw, 180, 270),
        arc_band(x0 + w - rad, y0 + rad, rad, sw, 270, 360),
        arc_band(x0 + w - rad, y0 + h - rad, rad, sw, 0, 90),
        arc_band(x0 + rad, y0 + h - rad, rad, sw, 90, 180),
    )
    t.paint(frame, field)
    t.paint(disc(x0 + w - 134, y0 + h - 116, 60), solid(RAMP[-1][1]))


DIRECTIONS = {
    "ribbon": d_ribbon,
    "ribbon-outline": d_ribbon_outline,
    "ribbon-outline-coral": lambda t, dark: d_ribbon_outline(t, dark, coral=True),
    "frame": d_frame,
    "p": d_p,
    "p-dot": d_p_dot,
    "ring": d_ring,
}


def render(name, dark):
    t = Tile(NIGHT if dark else CREAM)
    DIRECTIONS[name](t, dark)
    return t.image()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=list(DIRECTIONS))
    args = ap.parse_args()
    OUT.mkdir(exist_ok=True)
    for name in args.only:
        for dark in (False, True):
            render(name, dark).save(OUT / f"{name}-{'dark' if dark else 'light'}.png")
    print("rendered", args.only)


if __name__ == "__main__":
    main()
