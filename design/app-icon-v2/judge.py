#!/usr/bin/env python3
"""Judge the directions where icons live: squircle-masked, 180 px in a home-screen row on both
wallpapers, and a 29/40/60 pt strip. usage: judge.py [names...]"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
import os
OUT = HERE / os.environ.get("ICON_OUT", "out")
AURA = Path("/Users/shantanusinha/Desktop/workspace/aura-assistant/design/icon/AppIcon-1024.png")
AURA_DARK = Path("/Users/shantanusinha/Desktop/workspace/aura-assistant/ios/Aura/AuraPair.icon/Assets/layer-nocturne-dark.png")
CURRENT = Path("/private/tmp/claude-501/-Users-shantanusinha-Desktop-workspace-animetracker/b51d53e3-d154-4660-9777-ec1fac686589/scratchpad/ref/current-icon.png")


def squircle_mask(size, n=5.0):
    ss = 4
    Sz = size * ss
    m = Image.new("L", (Sz, Sz), 0)
    a = Sz / 2
    pts = []
    for i in range(1440):
        t = 2 * math.pi * i / 1440
        c, s = math.cos(t), math.sin(t)
        pts.append((a + a * math.copysign(abs(c) ** (2 / n), c), a + a * math.copysign(abs(s) ** (2 / n), s)))
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def masked(icon, size):
    im = icon.convert("RGB").resize((size, size), Image.LANCZOS).convert("RGBA")
    im.putalpha(squircle_mask(size))
    return im


def font(sz):
    for p in ["/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"]:
        try:
            return ImageFont.truetype(p, sz)
        except Exception:
            pass
    return ImageFont.load_default()


def neighbour(size, bg, kind):
    im = Image.new("RGBA", (size, size), bg)
    d = ImageDraw.Draw(im)
    c = size / 2
    if kind == "disc":
        r = size * 0.26; d.ellipse([c - r, c - r, c + r, c + r], fill=(255, 255, 255, 255))
    elif kind == "ring":
        r = size * 0.28; d.ellipse([c - r, c - r, c + r, c + r], outline=(255, 255, 255, 255), width=int(size * 0.09))
    elif kind == "bars":
        for i, h in enumerate((0.22, 0.42, 0.30)):
            x = c + (i - 1) * size * 0.2
            d.rounded_rectangle([x - size * 0.05, c - size * h, x + size * 0.05, c + size * h], radius=size * 0.05, fill=(255, 255, 255, 255))
    elif kind == "square":
        r = size * 0.24; d.rounded_rectangle([c - r, c - r, c + r, c + r], radius=size * 0.07, fill=(255, 255, 255, 255))
    im.putalpha(squircle_mask(size))
    return im


NEIGH = [((52, 120, 246, 255), "disc"), ((40, 205, 65, 255), "ring"), ((255, 159, 10, 255), "bars"), ((142, 142, 147, 255), "square"), ((255, 55, 95, 255), "disc"), ((94, 92, 230, 255), "square")]


def homerow(icons, wallpaper, label_color, px=180, gap=78, per_row=4):
    """Rows of `per_row` icons: candidates interleaved with flat stand-in neighbours."""
    slots = []
    k = 0
    for label, icon in icons:
        slots.append((label, masked(icon, px)))
        bg, kind = NEIGH[k % len(NEIGH)]; k += 1
        slots.append((["Mail", "Notes", "Maps", "Files", "Music", "Photos"][k % 6], neighbour(px, bg, kind)))
    rows = math.ceil(len(slots) / per_row)
    W = 60 + per_row * (px + gap)
    H = 60 + rows * (px + gap + 40)
    im = Image.new("RGBA", (W, H), wallpaper)
    d = ImageDraw.Draw(im)
    f = font(30)
    for i, (label, s) in enumerate(slots):
        r, c = divmod(i, per_row)
        x, y = 60 + c * (px + gap), 60 + r * (px + gap + 40)
        im.alpha_composite(s, (int(x), int(y)))
        tw = d.textlength(label, font=f)
        d.text((x + px / 2 - tw / 2, y + px + 14), label, fill=label_color, font=f)
    return im


def strip(icons, wallpaper):
    sizes = [87, 120, 180]
    W = 60 + sum(sizes) + 60 * len(sizes) + 200
    H = 40 + len(icons) * (180 + 60)
    im = Image.new("RGBA", (W, H), wallpaper)
    d = ImageDraw.Draw(im)
    f = font(28)
    for r, (label, icon) in enumerate(icons):
        y = 40 + r * (180 + 60)
        x = 60
        for s in sizes:
            im.alpha_composite(masked(icon, s), (x, int(y + (180 - s) / 2)))
            x += s + 60
        d.text((x, y + 70), label, fill=(200, 200, 200, 255), font=f)
    return im


def circle_mask(size):
    ss = 4
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).ellipse([0, 0, size * ss - 1, size * ss - 1], fill=255)
    return m.resize((size, size), Image.LANCZOS)


def masked_circle(icon, size):
    im = icon.convert("RGB").resize((size, size), Image.LANCZOS).convert("RGBA")
    im.putalpha(circle_mask(size))
    return im


def circle_strip(icons, wallpaper, size=128):
    """watchOS: the same tiles under a circle."""
    W = 40 + len(icons) * (size + 40)
    H = 40 + size + 60
    im = Image.new("RGBA", (W, H), wallpaper)
    d = ImageDraw.Draw(im)
    f = font(22)
    for i, (label, icon) in enumerate(icons):
        x = 40 + i * (size + 40)
        im.alpha_composite(masked_circle(icon, size), (x, 40))
        tw = d.textlength(label, font=f)
        d.text((x + size / 2 - tw / 2, 40 + size + 14), label, fill=(200, 200, 200, 255), font=f)
    return im


def sheet(names, size=360, pad=40):
    """Light row over dark row, every tile squircle-masked, on a mid ground with labels."""
    cols = len(names)
    W = pad + cols * (size + pad)
    H = pad + 2 * (size + pad + 44)
    im = Image.new("RGBA", (W, H), (58, 58, 62, 255))
    d = ImageDraw.Draw(im)
    f = font(30)
    for r, appearance in enumerate(["light", "dark"]):
        for c, name in enumerate(names):
            p = OUT / f"{name}-{appearance}.png"
            icon = Image.open(p)
            x, y = pad + c * (size + pad), pad + r * (size + pad + 44)
            im.alpha_composite(masked(icon, size), (x, y))
            label = f"{name} · {appearance}"
            tw = d.textlength(label, font=f)
            d.text((x + size / 2 - tw / 2, y + size + 10), label, fill=(230, 230, 230, 255), font=f)
    return im


def main():
    names = sys.argv[1:] or ["fullstop", "ring", "echo", "orb", "still", "rewind", "ribbon", "playhead"]
    sheet(names).convert("RGB").save(OUT / "sheet.png")
    light = [(n, Image.open(OUT / f"{n}-light.png")) for n in names]
    dark = [(n, Image.open(OUT / f"{n}-dark.png")) for n in names]
    bench = [("Aura", Image.open(AURA)), ("Current", Image.open(CURRENT))]
    homerow(light + bench, (0, 0, 0, 255), (243, 239, 232, 255)).convert("RGB").save(OUT / "homerow-light-on-black.png")
    homerow(light + bench, (226, 229, 236, 255), (20, 20, 24, 255)).convert("RGB").save(OUT / "homerow-light-on-pale.png")
    homerow(dark + bench, (0, 0, 0, 255), (243, 239, 232, 255)).convert("RGB").save(OUT / "homerow-dark-on-black.png")
    strip(light + [("Aura", Image.open(AURA))], (12, 12, 14, 255)).convert("RGB").save(OUT / "small-light.png")
    strip(dark + [("Aura dark", Image.open(AURA_DARK))], (12, 12, 14, 255)).convert("RGB").save(OUT / "small-dark.png")
    circle_strip(dark, (0, 0, 0, 255)).convert("RGB").save(OUT / "watch-dark.png")
    circle_strip(light, (0, 0, 0, 255)).convert("RGB").save(OUT / "watch-light.png")
    print("wrote sheet + homerows + strips")


if __name__ == "__main__":
    main()
