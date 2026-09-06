#!/usr/bin/env python3
"""Previously. — round nine: the ribbon as Liquid Glass, rendered by Icon Composer's own engine.

Each variant is an Icon Composer document (`glass/<name>.icon`): flat layer PNGs from the round-eight
geometry plus an icon.json that says what material each layer is. `ictool` (Icon Composer.app)
renders the Default and Dark renditions — the same renderer iOS 27 uses — into glass/out/.

    glass.py            # writes every document and renders it
"""
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image

from make import S, disc, _grid, ramp_color, HERE
from make2 import RAMP, CREAM, NIGHT
from ribbon import fill, ribbon_pts, ribbon_radii, settle, CORAL

ROOT = HERE / "glass"
OUT = ROOT / "out"
ICTOOL = "/Applications/Xcode-beta.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
WHITE = (0xFF, 0xFA, 0xF2)


# ---------------------------------------------------------------- geometry (round eight picks)

def hang_masks(w=368, bottom=800, notch=0.38, period=84, gap=44, tuck=0.6, top=-60, hole=None):
    dot_w = gap + 2 * period if period else 0
    x0 = 512 - (w + dot_w) / 2 + (dot_w * tuck / 2)
    pts = ribbon_pts(x0, top, w, bottom - top, notch * w)
    body = fill(pts, [0, 0, 0.045 * w, 0.035 * w, 0.045 * w])
    if hole:
        body = np.clip(body - disc(x0 + w / 2, hole[1], hole[0]), 0, 1)
    per = disc(x0 + w + gap + period, bottom - period, period) if period else None
    return body, per, (x0, 80, x0 + w, bottom)


def solid_masks(w=404, h=670, notch=0.22, hole=(62, 0.26), period=84, gap=44, tuck=0.5):
    dot_w = gap + 2 * period if period else 0
    x0 = 512 - (w + dot_w) / 2 + (dot_w * tuck / 2)
    y0 = 512 - h / 2
    pts, dy = settle(ribbon_pts(x0, y0, w, h, notch * h), 0.50 * S)
    y0 += dy
    body = fill(pts, ribbon_radii(w))
    if hole:
        body = np.clip(body - disc(x0 + w / 2, y0 + hole[1] * h, hole[0]), 0, 1)
    per = disc(x0 + w + gap + period, y0 + h - period, period) if period else None
    return body, per, (x0, y0, x0 + w, y0 + h)


# ---------------------------------------------------------------- layer images

def diag_field(bbox):
    x0, y0, x1, y1 = bbox
    x, y = _grid()
    return ramp_color(((x - x0) / (x1 - x0) + (y - y0) / (y1 - y0)) / 2, RAMP)


def layer_png(mask, rgb_field, path):
    """Straight-alpha RGBA: the colour everywhere (so glass edges tint right), the mask as alpha."""
    if rgb_field.ndim == 1:
        rgb_field = np.broadcast_to(rgb_field, (S, S, 3))
    im = np.zeros((S, S, 4), dtype=np.uint8)
    im[..., :3] = np.clip(rgb_field * 255 + 0.5, 0, 255).astype(np.uint8)
    im[..., 3] = np.clip(mask * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(im).save(path)


def solid_rgb(rgb):
    return np.array(rgb, dtype=np.float32) / 255.0


def p3(rgb, a=1.0):
    return "display-p3:%.5f,%.5f,%.5f,%.5f" % (rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, a)


# ---------------------------------------------------------------- documents

def write_doc(name, ground, layers, group, dark_ground=None, dark_layers=None):
    """ground: rgb fill. layers: [(layer-name, mask, rgb_field, glass:bool)]. group: dict of group keys."""
    doc = ROOT / f"{name}.icon"
    (doc / "Assets").mkdir(parents=True, exist_ok=True)
    layer_json = []
    for lname, mask, field, glass in layers:
        layer_png(mask, field, doc / "Assets" / f"{lname}.png")
        layer_json.append({"name": lname, "image-name": f"{lname}.png", "glass": glass})
    j = {
        "fill": {"solid": p3(ground)},
        "groups": [dict(layers=layer_json, **group)],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    if dark_ground:
        j["fill-specializations"] = [{"appearance": "dark", "value": {"solid": p3(dark_ground)}}]
    (doc / "icon.json").write_text(json.dumps(j, indent=2))
    return doc


def render(doc, renditions=("Default", "Dark")):
    OUT.mkdir(exist_ok=True)
    for r in renditions:
        out = OUT / f"{doc.stem}-{r}.png"
        res = subprocess.run([ICTOOL, str(doc), "--export-image", "--output-file", str(out), "--platform", "iOS",
                              "--rendition", r, "--width", "1024", "--height", "1024", "--scale", "1"],
                             capture_output=True, text=True)
        if res.returncode != 0:
            print("  !!", doc.stem, r, (res.stderr or res.stdout).strip()[:300])
        else:
            print("  ok", out.name)


GROUP_GLASS = dict(lighting="combined", specular=True, shadow={"kind": "neutral", "opacity": 0.5},
                   translucency={"enabled": True, "value": 0.5}, blur=0)
GROUP_OBJECT = dict(lighting="combined", specular=True, shadow={"kind": "neutral", "opacity": 0.5},
                    translucency={"enabled": False, "value": 0}, blur=0)
GROUP_FLAT = dict(lighting="combined", specular=False, shadow={"kind": "none", "opacity": 0},
                  translucency={"enabled": False, "value": 0}, blur=0)


def build_all():
    body, per, bbox = hang_masks()
    ramp = diag_field(bbox)
    coral = solid_rgb(CORAL)
    white = solid_rgb(WHITE)
    docs = []
    # 1 · night, glass ribbon: amber glass on a dark tile (Wallet / Fitness family)
    docs.append(write_doc("g1-night-glass", NIGHT, [("ribbon", body, ramp, True), ("period", per, coral, True)], GROUP_GLASS))
    # 2 · night, object ribbon: the flat ramp as a lit object (specular + shadow, no translucency)
    docs.append(write_doc("g2-night-object", NIGHT, [("ribbon", body, ramp, False), ("period", per, coral, False)], GROUP_OBJECT))
    # 3 · cream, object ribbon (Reminders / Health family)
    docs.append(write_doc("g3-cream-object", CREAM, [("ribbon", body, ramp, False), ("period", per, coral, False)], GROUP_OBJECT, dark_ground=NIGHT))
    # 4 · ramp tile, white glass ribbon (Messages / Files family)
    tile = np.ones((S, S), dtype=np.float32)
    docs.append(write_doc("g4-ramp-whiteglass", (0xF3, 0x90, 0x3E),
                          [("ground", tile, diag_field((0, 0, S, S)), False), ("ribbon", body, white, True), ("period", per, white, True)],
                          GROUP_GLASS))
    # 5 · cream, glass ribbon: amber glass on cream
    docs.append(write_doc("g5-cream-glass", CREAM, [("ribbon", body, ramp, True), ("period", per, coral, True)], GROUP_GLASS, dark_ground=NIGHT))
    # 6 · the round-eight flat drawing, no material at all — the control
    docs.append(write_doc("g0-flat", CREAM, [("ribbon", body, ramp, False), ("period", per, coral, False)], GROUP_FLAT, dark_ground=NIGHT))
    for d in docs:
        print(d.name)
        render(d)


if __name__ == "__main__":
    build_all()
