#!/usr/bin/env python3
"""The final Object as an Android adaptive icon: background, foreground and monochrome layers at
every density, from the same geometry as the iOS document. Android has no Liquid Glass, so the
material is baked: the tile's gradient, the ribbon's volume, and soft coloured glows under the
ribbon and the period.

Canvas 108 dp; the launcher's mask shows the centre ~72 dp; the 1024 iOS tile maps onto that
72 dp, and the ribbon is extended to the canvas top so it hangs from the edge under any mask.

    android_icon.py            # writes android/app/src/main/res/mipmap-*/ic_launcher_*.png + a preview
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from make import _grid, ramp_color, HERE
from ribbon import rounded, ribbon_pts
from glass3 import RAMP_B, CORAL_BRIGHT, TILE_B

REPO = HERE.parent.parent
RES = REPO / "android/app/src/main/res"
DENSITIES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
C = 1536                       # working canvas: 108 dp at 1536 px -> the 72 dp visible region is 1024 px, i.e. the iOS tile 1:1
OFF = (C - 1024) / 2           # 256: where the iOS tile's origin sits on the canvas
SS = 4

# tile: Apple's automatic gradient from #1A1412, sampled from the rendered final (top lighter, bottom darker)
TILE_TOP = (0x24, 0x1C, 0x19)
TILE_BOT = (0x14, 0x0F, 0x0E)


def to_canvas(pts):
    return [(x + OFF, y + OFF) for x, y in pts]


def poly_mask(pts, size=C):
    m = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(m).polygon([(x * SS, y * SS) for x, y in pts], fill=255)
    return np.asarray(m.resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0


def disc_mask(cx, cy, r, size=C):
    m = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(m).ellipse([(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS], fill=255)
    return np.asarray(m.resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0


def blur(mask, sigma):
    im = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(sigma)), dtype=np.float32) / 255.0


def rgba(rgb_field, alpha):
    out = np.zeros((C, C, 4), dtype=np.uint8)
    out[..., :3] = np.clip(rgb_field * 255 + 0.5, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(out)


def over(dst, src):
    """dst, src: float RGBA (C, C, 4) straight alpha."""
    a = src[..., 3:4]; da = dst[..., 3:4]
    oa = a + da * (1 - a)
    rgb = (src[..., :3] * a + dst[..., :3] * da * (1 - a)) / np.maximum(oa, 1e-6)
    return np.concatenate([rgb, oa], axis=-1)


def build():
    # ---- geometry, in iOS tile space (round-eight Hang., round-eleven numbers), then onto the canvas
    w, bottom, notch, period, gap, tuck = 376, 800, 0.40, 84, 44, 0.6
    dot_w = gap + 2 * period
    x0 = 512 - (w + dot_w) / 2 + (dot_w * tuck / 2)
    top = -OFF                                            # the ribbon runs to the canvas top
    pts = ribbon_pts(x0, top, w, bottom - top, notch * w)
    pts = rounded(pts, [0, 0, 0.045 * w, 0.035 * w, 0.045 * w])
    ribbon = poly_mask(to_canvas(pts))
    bead_r = 90
    pcx, pcy = x0 + w + gap + period, bottom - bead_r
    bead = disc_mask(pcx + OFF, pcy + OFF, bead_r)

    # ---- colour: the ramp with volume and curl, as in glass3.field
    x, y = np.mgrid[0:C, 0:C].astype(np.float32)[::-1] + 0.5   # x, y
    bx0, by0, bx1, by1 = x0 + OFF, 80 + OFF, x0 + w + OFF, bottom + OFF
    base = ramp_color(((x - bx0) / (bx1 - bx0) + (y - by0) / (by1 - by0)) / 2, RAMP_B)
    t = np.clip((y - by0) / (by1 - by0), 0, 1)[..., None]
    u = np.clip((x - bx0) / (bx1 - bx0), 0, 1)[..., None]
    field = base * (1.08 + (0.88 - 1.08) * t) + 0.04 * (1 - t)
    field = np.clip(field * (1 + 0.10 * np.cos((u - 0.35) * np.pi)), 0, 1)
    coral = np.broadcast_to(np.array(CORAL_BRIGHT, dtype=np.float32) / 255, (C, C, 3))

    # ---- background: the tile gradient over the whole canvas
    tv = (y / C)[..., None]
    tile = (np.array(TILE_TOP) * (1 - tv) + np.array(TILE_BOT) * tv) / 255.0
    background = rgba(tile, np.ones((C, C), dtype=np.float32))

    # ---- foreground: glows (baked stand-ins for the coloured shadows), ribbon, bead
    fg = np.zeros((C, C, 4), dtype=np.float32)
    glow_rib = blur(ribbon, 34) * 0.42
    fg = over(fg, np.concatenate([np.broadcast_to(np.array([0.95, 0.55, 0.25], dtype=np.float32), (C, C, 3)), glow_rib[..., None]], axis=-1))
    glow_bead = blur(bead, 26) * 0.5
    fg = over(fg, np.concatenate([coral, glow_bead[..., None]], axis=-1))
    # a soft contact shadow under both, the way the launcher would light a raised object
    shadow = blur(np.clip(ribbon + bead, 0, 1), 10) * 0.35
    fg = over(fg, np.concatenate([np.zeros((C, C, 3), dtype=np.float32), shadow[..., None]], axis=-1))
    fg = over(fg, np.concatenate([field, ribbon[..., None]], axis=-1))
    # the bead: a touch of light at its top-left, the way the glass bead catches it
    bx, by = pcx + OFF - 0.3 * bead_r, pcy + OFF - 0.35 * bead_r
    hl = np.clip(1 - np.hypot(x - bx, y - by) / (1.3 * bead_r), 0, 1)[..., None]
    bead_rgb = np.clip(coral * (0.92 + 0.22 * hl), 0, 1)
    fg = over(fg, np.concatenate([bead_rgb, bead[..., None]], axis=-1))
    foreground = Image.fromarray(np.clip(fg * 255 + 0.5, 0, 255).astype(np.uint8))

    # ---- monochrome: the silhouette, white (themed icons tint it)
    mono = rgba(np.ones((C, C, 3), dtype=np.float32), np.clip(ribbon + bead, 0, 1))

    for d, px in DENSITIES.items():
        for name, im in [("background", background), ("foreground", foreground), ("monochrome", mono)]:
            out = RES / f"mipmap-{d}" / f"ic_launcher_{name}.png"
            im.resize((px, px), Image.LANCZOS).save(out, optimize=True)
        print("wrote", d, px)
    return background, foreground, mono


def preview(background, foreground, mono):
    """The composed icon under Android's masks: circle, squircle, rounded square; plus themed."""
    comp = Image.alpha_composite(background.convert("RGBA"), foreground.convert("RGBA"))
    vis = 1024                                        # the 72 dp visible region at canvas scale
    cx = C / 2
    def masked(shape):
        m = Image.new("L", (C * 2, C * 2), 0); d = ImageDraw.Draw(m)
        r = vis
        if shape == "circle":
            d.ellipse([cx * 2 - r, cx * 2 - r, cx * 2 + r, cx * 2 + r], fill=255)
        elif shape == "rounded":
            d.rounded_rectangle([cx * 2 - r, cx * 2 - r, cx * 2 + r, cx * 2 + r], radius=r * 0.4, fill=255)
        else:  # squircle
            pts = []
            for i in range(1440):
                th = 2 * math.pi * i / 1440
                c, s = math.cos(th), math.sin(th)
                pts.append((cx * 2 + r * math.copysign(abs(c) ** (2 / 5), c), cx * 2 + r * math.copysign(abs(s) ** (2 / 5), s)))
            d.polygon(pts, fill=255)
        m = m.resize((C, C), Image.LANCZOS)
        out = comp.copy(); out.putalpha(m)
        return out.crop((int(cx - vis / 2) - 20, int(cx - vis / 2) - 20, int(cx + vis / 2) + 20, int(cx + vis / 2) + 20))
    tiles = [masked(s) for s in ("squircle", "circle", "rounded")]
    themed = Image.new("RGBA", (C, C), (0x35, 0x2F, 0x2C, 255))
    tm = mono.copy(); tint = Image.new("RGBA", (C, C), (0xF3, 0xC9, 0xA6, 255)); tint.putalpha(tm.split()[3])
    themed.alpha_composite(tint); themed.putalpha(Image.new("L", (C, C), 255))
    th = themed; m = Image.new("L", (C, C), 0); ImageDraw.Draw(m).ellipse([cx - vis / 2, cx - vis / 2, cx + vis / 2, cx + vis / 2], fill=255); th.putalpha(m)
    tiles.append(th.crop((int(cx - vis / 2) - 20, int(cx - vis / 2) - 20, int(cx + vis / 2) + 20, int(cx + vis / 2) + 20)))
    s = 260; pad = 30
    sheet = Image.new("RGB", (pad + len(tiles) * (s + pad), pad * 2 + s + 40), (20, 20, 22))
    d = ImageDraw.Draw(sheet)
    for i, (t, lab) in enumerate(zip(tiles, ["squircle", "circle", "rounded square", "themed (mono)"])):
        tt = t.resize((s, s), Image.LANCZOS); sheet.paste(tt, (pad + i * (s + pad), pad), tt); d.text((pad + i * (s + pad), pad + s + 8), lab, fill=(220, 220, 220))
    p = HERE / "glass" / "out2" / "android-preview.png"; sheet.save(p); print("preview", p)


if __name__ == "__main__":
    preview(*build())
