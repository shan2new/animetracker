#!/usr/bin/env python3
"""Previously. — round eleven: the final polish on Object (o9-object-lit), one micro-knob per tile."""
import json, sys
import numpy as np
from make import S, disc, _grid, ramp_color
from ribbon import fill, ribbon_pts
import glass as g
from glass2 import grp, write, render, NIGHT_WARM, OUT

CORAL = (0xE2, 0x4E, 0x3F)
CORAL_BRIGHT = (0xF0, 0x56, 0x3F)
RAMP_A = [(0.00, (0xFF, 0xC5, 0x52)), (0.50, (0xF3, 0x90, 0x3E)), (1.00, (0xE2, 0x4E, 0x3F))]   # round six
RAMP_B = [(0.00, (0xFF, 0xBB, 0x48)), (0.50, (0xF2, 0x8C, 0x3C)), (1.00, (0xDE, 0x4A, 0x3C))]   # less lemon at the top, a hair richer at the foot
TILE_A = NIGHT_WARM                  # #161211
TILE_B = (0x1A, 0x14, 0x12)          # warmer, a step lighter


def geometry(w=368, bottom=800, notch=0.38, period=84, gap=44, tuck=0.6, top=-60):
    dot_w = gap + 2 * period
    x0 = 512 - (w + dot_w) / 2 + (dot_w * tuck / 2)
    pts = ribbon_pts(x0, top, w, bottom - top, notch * w)
    body = fill(pts, [0, 0, 0.045 * w, 0.035 * w, 0.045 * w])
    pcx = x0 + w + gap + period
    return body, (x0, 80, x0 + w, bottom), pcx, bottom


def field(bbox, ramp, top=1.08, foot=0.88, lift=0.04, curl=0.10):
    x0, y0, x1, y1 = bbox
    x, y = _grid()
    base = ramp_color(((x - x0) / (x1 - x0) + (y - y0) / (y1 - y0)) / 2, ramp)
    t = np.clip((y - 80) / (800 - 80), 0, 1)[..., None]
    u = np.clip((x - x0) / (x1 - x0), 0, 1)[..., None]
    v = base * (top + (foot - top) * t) + lift * (1 - t)
    v = v * (1 + curl * np.cos((u - 0.35) * np.pi))
    return np.clip(v, 0, 1)


def make(name, ramp=RAMP_A, tile=TILE_A, bead_r=84, bead_rgb=CORAL, lighting="individual", rib_shadow=0.7,
         w=368, notch=0.38, blur=0, curl=0.10, bead_shadow=0.7):
    body, bbox, pcx, bottom = geometry(w=w, notch=notch, period=84)
    bead = disc(pcx, bottom - bead_r, bead_r)
    groups = [
        dict(grp([("period", bead, g.solid_rgb(bead_rgb), True)], shadow="layer-color", shadow_op=bead_shadow, tr=0.3, lighting=lighting)),
        dict(grp([("ribbon", body, field(bbox, ramp, curl=curl), True)], shadow="layer-color", shadow_op=rib_shadow, tr=0.08, lighting=lighting, blur=blur)),
    ]
    d = write(name, tile, groups, auto=True)
    print(name); render(d, ("Default",))
    return d


VARIANTS = {
    "x1-reference": dict(),
    "x2-ramp-b": dict(ramp=RAMP_B),
    "x3-bead-bigger-brighter": dict(bead_r=90, bead_rgb=CORAL_BRIGHT),
    "x4-combined-lighting": dict(lighting="combined"),
    "x5-tile-warmer-glow-lighter": dict(tile=TILE_B, rib_shadow=0.55),
    "x6-ribbon-wider": dict(w=380, notch=0.40),
    "x7-blur": dict(blur=12),
    "x8-guess": dict(ramp=RAMP_B, bead_r=90, bead_rgb=CORAL_BRIGHT, tile=TILE_B, rib_shadow=0.55),
}

if __name__ == "__main__":
    only = sys.argv[1:] or list(VARIANTS)
    for n in only:
        make(n, **VARIANTS[n])
