#!/usr/bin/env python3
"""Previously. — round eight: dot-hole, hang and hang-dot, each iterated on its own knobs.

    ribbon8.py           # renders every variant into out4/
"""
import argparse

import numpy as np

from make import S, disc, Tile, solid, HERE
from make2 import CREAM, NIGHT, diag
from ribbon import fill, ribbon_pts, ribbon_radii, settle, CORAL

OUT = HERE / "out4"


def solid_ribbon(t, dark, w=396, h=660, notch=0.21, top_rad=0.20, hole=None, period=None, gap=62,
                 tuck=0.0, target=0.50):
    """A solid ribbon with an optional hole (r, y-fraction) and an optional period (r).
    `tuck` moves the ribbon back toward the centre by that fraction of the period's width."""
    dot_w = (gap + 2 * period) if period else 0
    total = w + dot_w
    x0 = 512 - total / 2 + (dot_w * tuck / 2)
    y0 = 512 - h / 2
    pts, dy = settle(ribbon_pts(x0, y0, w, h, notch * h), target * S)
    y0 += dy
    body = fill(pts, ribbon_radii(w, top=top_rad))
    if hole:
        r, fy = hole
        body = np.clip(body - disc(x0 + w / 2, y0 + fy * h, r), 0, 1)
    t.paint(body, diag((x0, y0, x0 + w, y0 + h)))
    if period:
        t.paint(disc(x0 + w + gap + period, y0 + h - period, period), solid(CORAL))


def hanging_ribbon(t, dark, w=408, bottom=810, notch=0.36, hole=None, period=None, gap=58, tuck=0.0,
                   top=-60):
    """A ribbon entering from the tile's top edge. `hole` = (r, y); `period` = r beside the tails."""
    dot_w = (gap + 2 * period) if period else 0
    x0 = 512 - (w + dot_w) / 2 + (dot_w * tuck / 2)
    h = bottom - top
    pts = ribbon_pts(x0, top, w, h, notch * w)
    body = fill(pts, [0, 0, 0.045 * w, 0.035 * w, 0.045 * w])
    if hole:
        r, y = hole
        body = np.clip(body - disc(x0 + w / 2, y, r), 0, 1)
    t.paint(body, diag((x0, 80, x0 + w, bottom)))
    if period:
        t.paint(disc(x0 + w + gap + period, bottom - period, period), solid(CORAL))


VARIANTS = {
    # dot-hole: the hole against the period
    "dh1-current":   lambda t, d: solid_ribbon(t, d, w=396, h=660, hole=(76, 0.27), period=76),
    "dh2-hierarchy": lambda t, d: solid_ribbon(t, d, w=410, h=680, notch=0.23, hole=(60, 0.26), period=86),
    "dh3-rhyme":     lambda t, d: solid_ribbon(t, d, w=400, h=660, hole=(72, 0.30), period=72, gap=36, tuck=0.5),
    "dh4-wide":      lambda t, d: solid_ribbon(t, d, w=440, h=640, notch=0.22, top_rad=0.18, hole=(80, 0.28), period=78),
    # hang: width, reach, hole height
    "h1-current":    lambda t, d: hanging_ribbon(t, d, w=408, bottom=810, notch=0.36, hole=(84, 470)),
    "h2-narrow":     lambda t, d: hanging_ribbon(t, d, w=372, bottom=830, notch=0.40, hole=(76, 480)),
    "h3-wide":       lambda t, d: hanging_ribbon(t, d, w=452, bottom=780, notch=0.34, hole=(92, 440)),
    "h4-low":        lambda t, d: hanging_ribbon(t, d, w=408, bottom=810, notch=0.36, hole=(84, 560)),
    # hang-dot: the period's weight and place, with and without the hole
    "hd1-current":   lambda t, d: hanging_ribbon(t, d, w=380, bottom=790, notch=0.36, period=74),
    "hd2-hole":      lambda t, d: hanging_ribbon(t, d, w=380, bottom=790, notch=0.36, hole=(72, 450), period=74),
    "hd3-heavy":     lambda t, d: hanging_ribbon(t, d, w=360, bottom=800, notch=0.38, period=86, gap=52),
    "hd4-tucked":    lambda t, d: hanging_ribbon(t, d, w=380, bottom=790, notch=0.36, period=74, gap=30, tuck=1.0),
    # the picks: each family's winning knobs combined
    "dh5-pick":      lambda t, d: solid_ribbon(t, d, w=404, h=670, notch=0.22, hole=(62, 0.26), period=84, gap=44, tuck=0.5),
    "h5-pick":       lambda t, d: hanging_ribbon(t, d, w=388, bottom=820, notch=0.38, hole=(80, 478)),
    "hd5-pick":      lambda t, d: hanging_ribbon(t, d, w=368, bottom=800, notch=0.38, period=84, gap=44, tuck=0.6),
}


def render(name, dark):
    t = Tile(NIGHT if dark else CREAM)
    VARIANTS[name](t, dark)
    return t.image()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=list(VARIANTS))
    args = ap.parse_args()
    OUT.mkdir(exist_ok=True)
    for name in args.only:
        for dark in (False, True):
            render(name, dark).save(OUT / f"{name}-{'dark' if dark else 'light'}.png")
    print("rendered", args.only)


if __name__ == "__main__":
    main()
