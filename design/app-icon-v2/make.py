#!/usr/bin/env python3
"""Previously. — app icon directions, drawn from geometry (no raster source).

Benchmark: the Aura icon (aura-assistant/design/icon/make_v9.py) — one hue family on a quiet
ground, flat unmasked layers (Liquid Glass adds the depth), smallest feature >= 80 px at 1024,
centred for the watch circle, judged at 180 px in a home-screen row, never at 1024.

    make.py                # renders every direction, light + dark, into out/
    make.py --only ring    # one direction

Ground: cream #F4F0E9 (light) / #0C0B0C (dark). Amber ramp (top-left -> bottom-right):
#FFC98A -> #F0A24E -> #D4582B. The head/orb ramp: #FFE6BF -> #F5A94F -> #CF4F27, highlight at
(42%, 38%) of its box. The unfilled part of any track is the ramp at low alpha — never grey.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024
SS = 4
HERE = Path(__file__).parent
OUT = HERE / "out"
FONT = HERE.parent.parent / "ios/Resources/Fonts/Outfit-SemiBold.ttf"

GROUND_LIGHT = (0xF4, 0xF0, 0xE9)
GROUND_DARK = (0x0C, 0x0B, 0x0C)
INK_LIGHT = (0x1B, 0x17, 0x14)      # warm near-black ink on cream
INK_DARK = (0xF4, 0xF1, 0xEC)       # the app's textPrimary on the night ground
RAMP = [(0.00, (0xFF, 0xC9, 0x8A)), (0.50, (0xF0, 0xA2, 0x4E)), (1.00, (0xD4, 0x58, 0x2B))]
ORB = [(0.00, (0xFF, 0xE6, 0xBF)), (0.45, (0xF5, 0xA9, 0x4F)), (1.00, (0xCF, 0x4F, 0x27))]
CREAM_DOT = (0xFF, 0xF6, 0xE8)


# ---------------------------------------------------------------- masks (drawn at 4x, downsampled)

def _L():
    return Image.new("L", (S * SS, S * SS), 0)


def _down(m):
    return np.asarray(m.resize((S, S), Image.LANCZOS), dtype=np.float32) / 255.0


def sc(v):
    return v * SS


def disc(cx, cy, r):
    m = _L()
    ImageDraw.Draw(m).ellipse([sc(cx - r), sc(cy - r), sc(cx + r), sc(cy + r)], fill=255)
    return _down(m)


def ring(cx, cy, r, w):
    """Annulus with stroke centre at radius r, width w."""
    m = _L()
    d = ImageDraw.Draw(m)
    ro, ri = r + w / 2, r - w / 2
    d.ellipse([sc(cx - ro), sc(cy - ro), sc(cx + ro), sc(cy + ro)], fill=255)
    d.ellipse([sc(cx - ri), sc(cy - ri), sc(cx + ri), sc(cy + ri)], fill=0)
    return _down(m)


def arc(cx, cy, r, w, a0, a1, caps=True):
    """Stroked arc (degrees, clockwise from 3 o'clock like PIL), round caps."""
    m = _L()
    d = ImageDraw.Draw(m)
    ro = r + w / 2
    d.arc([sc(cx - ro), sc(cy - ro), sc(cx + ro), sc(cy + ro)], a0, a1, fill=255, width=int(sc(w)))
    if caps:
        for a in (a0, a1):
            t = np.radians(a)
            px, py = cx + r * np.cos(t), cy + r * np.sin(t)
            d.ellipse([sc(px - w / 2), sc(py - w / 2), sc(px + w / 2), sc(py + w / 2)], fill=255)
    return _down(m)


def rrect(x0, y0, x1, y1, r):
    m = _L()
    ImageDraw.Draw(m).rounded_rectangle([sc(x0), sc(y0), sc(x1), sc(y1)], radius=sc(r), fill=255)
    return _down(m)


def capsule(x0, y0, x1, y1):
    return rrect(x0, y0, x1, y1, (y1 - y0) / 2)


def polygon(pts):
    m = _L()
    ImageDraw.Draw(m).polygon([(sc(x), sc(y)) for x, y in pts], fill=255)
    return _down(m)


def text_mask(txt, px, cx, cy, font=FONT):
    """Text set at cap-height-ish `px`, its bbox centred on (cx, cy). Returns mask + bbox."""
    f = ImageFont.truetype(str(font), int(sc(px)))
    m = _L()
    d = ImageDraw.Draw(m)
    l, t, r, b = d.textbbox((0, 0), txt, font=f)
    w, h = r - l, b - t
    ox, oy = sc(cx) - w / 2 - l, sc(cy) - h / 2 - t
    d.text((ox, oy), txt, font=f, fill=255)
    return _down(m), ((ox + l) / SS, (oy + t) / SS, (ox + r) / SS, (oy + b) / SS)


def blur(mask, sigma):
    im = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(sigma)), dtype=np.float32) / 255.0


# ---------------------------------------------------------------- colour fields

def _grid():
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) + 0.5
    return x, y


def ramp_color(t, ramp):
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,), dtype=np.float32)
    for (t0, c0), (t1, c1) in zip(ramp, ramp[1:]):
        m = (t >= t0) & (t <= t1)
        u = ((t - t0) / (t1 - t0))[m][:, None]
        out[m] = (np.array(c0, dtype=np.float32) * (1 - u) + np.array(c1, dtype=np.float32) * u) / 255.0
    return out


def diag(bbox, ramp=RAMP):
    """Diagonal ramp across a bbox, top-left -> bottom-right (the light comes from the top-left)."""
    x0, y0, x1, y1 = bbox
    x, y = _grid()
    t = ((x - x0) / (x1 - x0) + (y - y0) / (y1 - y0)) / 2
    return ramp_color(t, ramp)


def orb(cx, cy, r, ramp=ORB):
    """A lit sphere: highlight at (42%, 38%) of its box, ramp radius 0.85 of the box."""
    x, y = _grid()
    fx, fy = cx + (0.42 - 0.5) * 2 * r, cy + (0.38 - 0.5) * 2 * r
    t = np.hypot(x - fx, y - fy) / (0.85 * 2 * r)
    return ramp_color(t, ramp)


def solid(rgb):
    return np.broadcast_to(np.array(rgb, dtype=np.float32) / 255.0, (S, S, 3))


# ---------------------------------------------------------------- compositing

class Tile:
    def __init__(self, ground):
        self.rgb = np.empty((S, S, 3), dtype=np.float32)
        self.rgb[...] = np.array(ground, dtype=np.float32) / 255.0

    def paint(self, mask, color, alpha=1.0):
        a = (np.clip(mask, 0, 1) * alpha)[..., None]
        self.rgb = self.rgb * (1 - a) + color * a
        return self

    def image(self):
        arr = np.clip(self.rgb * 255 + 0.5, 0, 255).astype(np.uint8)
        return Image.fromarray(arr)


def glow(tile, mask, color, sigma, alpha):
    """A soft bloom under a lit element: the mask blurred and painted in the head colour."""
    tile.paint(blur(mask, sigma), color, alpha)


# ---------------------------------------------------------------- the directions
# Each paints onto `t`. `dark` selects the appearance. Marks fill ~72-80 % of the tile (Aura's
# ring reaches 76 %); nothing below 80 px at 1024.

def ghost_alpha(dark):
    # The unfilled part of a track: the ramp at low alpha. Cream needs less, night needs more.
    return 0.32 if dark else 0.24


def head(t, cx, cy, r, dark, bloom=True):
    """The airing dot: a lit orb with a bloom beneath it."""
    if bloom:
        glow(t, disc(cx, cy, r * 1.15), solid((0xF5, 0xA0, 0x48)), r * 0.60, 0.46 if dark else 0.28)
    t.paint(disc(cx, cy, r), orb(cx, cy, r))


def d_playhead(t, dark):
    """A · Playhead — the progress bar with its glowing head. The name drawn: where you left off."""
    y, h = 512, 150
    x0, x1 = 136, 888
    xh = 606                     # the head: ~62 % along, the ghost clearly continuing past it
    hr = 124
    bbox = (x0, y - h / 2, x1, y + h / 2)
    t.paint(capsule(x0, y - h / 2, x1, y + h / 2), diag(bbox), ghost_alpha(dark))
    t.paint(capsule(x0, y - h / 2, xh, y + h / 2), diag(bbox))
    head(t, xh, y, hr, dark)


def d_fullstop(t, dark):
    """B · Full stop — the wordmark's P with the airing dot as its period."""
    ink = solid(INK_DARK if dark else INK_LIGHT)
    bold = HERE.parent.parent / "ios/Resources/Fonts/Outfit-Bold.ttf"
    size, dot_r, gap = 700, 116, 52
    pm, (l, tp, r, b) = text_mask("P", size, 512, 512, font=bold)
    group_w = (r - l) + gap + 2 * dot_r
    shift = (S - group_w) / 2 - l
    pm, (l, tp, r, b) = text_mask("P", size, 512 + shift, 500, font=bold)
    t.paint(pm, ink)
    head(t, r + gap + dot_r, b - dot_r + 4, dot_r, dark)


def d_ring(t, dark):
    """C · Ring — the app's own MarkRing, two thirds of the way round, its head lit."""
    cx, cy, r, w = 512, 512, 314, 128
    bbox = (cx - r - w / 2, cy - r - w / 2, cx + r + w / 2, cy + r + w / 2)
    t.paint(ring(cx, cy, r, w), diag(bbox), ghost_alpha(dark))
    a0, a1 = -90, 158            # 12 o'clock, clockwise past two thirds
    t.paint(arc(cx, cy, r, w, a0, a1), diag(bbox))
    th = np.radians(a1)
    head(t, cx + r * np.cos(th), cy + r * np.sin(th), 98, dark)


def d_echo(t, dark):
    """D · Echo — 'Previously on…': the airing dot with its past trailing behind it."""
    cx, cy, r = 630, 512, 138
    bbox = (150, 150, 800, 874)
    field = diag(bbox)
    alphas = [0.72, 0.46, 0.26] if dark else [0.60, 0.38, 0.20]
    for rr, a in zip([246, 352, 458], alphas):
        t.paint(arc(cx, cy, rr, 68, 180 - 44, 180 + 44), field, a)
    head(t, cx, cy, r, dark)


def d_still(t, dark):
    """E · The still — a night card (the episode's frame) carrying the lit playhead."""
    cw, ch, rad = 780, 470, 92
    x0, y0 = 512 - cw / 2, 512 - ch / 2
    card = solid((0x2B, 0x27, 0x26) if dark else INK_LIGHT)
    t.paint(rrect(x0, y0, x0 + cw, y0 + ch, rad), card)
    # the playhead across the card's lower third
    y, h = y0 + ch - 128, 88
    bx0, bx1 = x0 + 88, x0 + cw - 88
    xh = bx0 + (bx1 - bx0) * 0.62
    bbox = (bx0, y - h / 2, bx1, y + h / 2)
    t.paint(capsule(bx0, y - h / 2, bx1, y + h / 2), diag(bbox), 0.36)
    t.paint(capsule(bx0, y - h / 2, xh, y + h / 2), diag(bbox))
    head(t, xh, y, 80, True)


def d_ribbon(t, dark):
    """F · Ribbon, rebuilt — the current bookmark, flat, one ramp, the slot replaced by the dot."""
    w = 430
    h = w * 1.58
    x0, y0 = 512 - w / 2, 512 - h / 2 - 10
    rad = w * 0.17
    apex = y0 + h * 0.76
    bottom = y0 + h * 0.96
    body = rrect(x0, y0, x0 + w, y0 + h, rad)
    notch = polygon([(x0 - 2, bottom), (512, apex), (x0 + w + 2, bottom), (x0 + w + 2, y0 + h + 4), (x0 - 2, y0 + h + 4)])
    body = np.clip(body - notch, 0, 1)
    t.paint(body, diag((x0, y0, x0 + w, y0 + h)))
    t.paint(disc(512, y0 + h * 0.24, 56), solid(CREAM_DOT))


def d_orb(t, dark):
    """G · Orb — the full stop alone: one warm light in the night, the app's atom at full size."""
    cx, cy, r = 512, 512, 292
    glow(t, disc(cx, cy, r * 1.12), solid((0xF5, 0xA0, 0x48)), r * 0.62, 0.50 if dark else 0.30)
    t.paint(disc(cx, cy, r), orb(cx, cy, r))


def d_rewind(t, dark):
    """H · Rewind — 'Previously on…' as TV says it: the recap glyph, the leading beat lit."""
    # two rounded triangles pointing left; the nearer one solid, the one behind it a ghost
    def tri(cx, w, h, rad):
        m = _L()
        d = ImageDraw.Draw(m)
        pts = [(cx - w / 2, 512), (cx + w / 2, 512 - h / 2), (cx + w / 2, 512 + h / 2)]
        d.polygon([(sc(x), sc(y)) for x, y in pts], fill=255)
        # round the corners: erode by drawing the polygon slightly inset, then blur-threshold
        return _down(m.filter(ImageFilter.GaussianBlur(sc(rad))).point(lambda v: 255 if v > 127 else 0))
    w, h = 400, 460
    bbox = (110, 512 - h / 2, 914, 512 + h / 2)
    field = diag(bbox)
    t.paint(tri(700, w, h, 40), field, ghost_alpha(dark) + 0.10)
    t.paint(tri(330, w, h, 40), field)
    head(t, 330 + 40, 512, 96, dark, bloom=False) if False else None


DIRECTIONS = {
    "playhead": d_playhead,
    "fullstop": d_fullstop,
    "ring": d_ring,
    "echo": d_echo,
    "still": d_still,
    "ribbon": d_ribbon,
    "orb": d_orb,
    "rewind": d_rewind,
}


def render(name, dark):
    t = Tile(GROUND_DARK if dark else GROUND_LIGHT)
    DIRECTIONS[name](t, dark)
    return t.image()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=list(DIRECTIONS))
    args = ap.parse_args()
    OUT.mkdir(exist_ok=True)
    for name in args.only:
        for dark in (False, True):
            im = render(name, dark)
            p = OUT / f"{name}-{'dark' if dark else 'light'}.png"
            im.save(p)
            print("wrote", p)


if __name__ == "__main__":
    main()
