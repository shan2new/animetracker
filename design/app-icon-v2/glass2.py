#!/usr/bin/env python3
"""Previously. — round ten: Object, Cream and Frost, each iterated in Icon Composer's material.

Documents may now carry several groups (front to back), so a layer can take a different shadow or
translucency from its neighbour. Rendered by ictool into glass/out2/.
"""
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image

from make import S, disc, _grid, ramp_color, HERE
from make2 import RAMP, NIGHT
from ribbon import CORAL
import glass as g

OUT = HERE / "glass" / "out2"
DOCS = HERE / "glass"
ICTOOL = g.ICTOOL
AMBER = (0xF3, 0x90, 0x3E)
BRAND = (0xF0, 0xA2, 0x4E)
DEEP = (0xE8, 0x66, 0x3A)
WHITE = g.WHITE
NIGHT_WARM = (0x16, 0x12, 0x11)


def grp(layers, shadow="neutral", shadow_op=0.6, tr=0.0, lighting="individual", specular=True, blur=0):
    return dict(layers=layers, lighting=lighting, specular=specular, shadow={"kind": shadow, "opacity": shadow_op},
                translucency={"enabled": tr > 0, "value": tr}, blur=blur)


def write(name, fill_rgb, groups, auto=False, dark_fill=None, dark_auto=False):
    """groups: list of (group-settings, [(layer-name, mask, rgb_field, glass)])."""
    doc = DOCS / f"{name}.icon"
    (doc / "Assets").mkdir(parents=True, exist_ok=True)
    gj = []
    for settings in groups:
        settings = dict(settings)
        layers = settings.pop("layers")
        lj = []
        for lname, mask, field, glass in layers:
            g.layer_png(mask, field, doc / "Assets" / f"{lname}.png")
            lj.append({"name": lname, "image-name": f"{lname}.png", "glass": glass})
        gj.append(dict(settings, layers=lj))
    j = {"fill": ({"automatic-gradient": g.p3(fill_rgb)} if auto else {"solid": g.p3(fill_rgb)}),
         "groups": gj, "supported-platforms": {"circles": ["watchOS"], "squares": "shared"}}
    if dark_fill:
        j["fill-specializations"] = [{"appearance": "dark", "value": ({"automatic-gradient": g.p3(dark_fill)} if dark_auto else {"solid": g.p3(dark_fill)})}]
    (doc / "icon.json").write_text(json.dumps(j, indent=2))
    return doc


def render(doc, rends=("Default",), size=1024):
    OUT.mkdir(exist_ok=True)
    for r in rends:
        out = OUT / f"{doc.stem}-{r}.png"
        res = subprocess.run([ICTOOL, str(doc), "--export-image", "--output-file", str(out), "--platform", "iOS",
                              "--rendition", r, "--width", str(size), "--height", str(size), "--scale", "1"], capture_output=True, text=True)
        print("  ", "ok" if res.returncode == 0 else "!! " + (res.stderr or res.stdout).strip()[:200], out.name)


# ---------------------------------------------------------------- the geometry (round-eight Hang.)

body, per, bbox = g.hang_masks()
x0, _, x1, _ = bbox
x, y = _grid()
ramp = g.diag_field(bbox)
t = np.clip((y - 80) / (800 - 80), 0, 1)[..., None]              # 0 at the top of the visible ribbon, 1 at the tails
u = np.clip((x - x0) / (x1 - x0), 0, 1)[..., None]                # 0 at the ribbon's left edge, 1 at its right

def volume(top=1.05, foot=0.92, lift=0.03, curl=0.0):
    """The ramp with a top light, a darker foot, and an optional curl (cylinder shading across the width)."""
    v = ramp * (top + (foot - top) * t) + lift * (1 - t)
    if curl:
        v = v * (1 + curl * np.cos((u - 0.35) * np.pi))          # lit a little left of centre, falling to the right
    return np.clip(v, 0, 1)

coral = g.solid_rgb(CORAL)
white = g.solid_rgb(WHITE)
per_big = disc(0, 0, 0)  # placeholder, replaced below
# a bigger period for one Object variant: same centre, r 94
_, per_r, _ = g.hang_masks(period=84)
cx = x1 + 44 + 84
per_big = disc(cx, 800 - 84, 94)

docs = []
def D(name, fill_rgb, groups, **k):
    d = write(name, fill_rgb, [gr for gr in groups], **k); docs.append(d); return d

# ---------------------------------------------------------------- Object
D("o1-object", NIGHT, [(grp([("period", per, coral, True), ("ribbon", body, volume(), False)], tr=0.3))])
D("o2-object-darktile", NIGHT_WARM, [(grp([("period", per, coral, True), ("ribbon", body, volume(), False)], tr=0.3))], auto=True)
D("o3-object-curl", NIGHT, [(grp([("period", per, coral, True), ("ribbon", body, volume(1.08, 0.88, 0.04, 0.07), False)], tr=0.3))])
D("o4-object-glow", NIGHT, [(grp([("ribbon", body, volume(), False)], shadow="layer-color", shadow_op=0.7)),
                            (grp([("period", per, coral, True)], tr=0.3))])
D("o5-object-rim", NIGHT, [(grp([("period", per, coral, True), ("ribbon", body, volume(), True)], tr=0.08))])
D("o6-object-solidperiod", NIGHT, [(grp([("period", per_big, coral, False), ("ribbon", body, volume(1.08, 0.88, 0.04, 0.07), False)]))])
D("o7-object-all", NIGHT_WARM, [(grp([("ribbon", body, volume(1.08, 0.88, 0.04, 0.07), True)], shadow="layer-color", shadow_op=0.7, tr=0.08)),
                                (grp([("period", per, coral, True)], tr=0.3))], auto=True)

# ---------------------------------------------------------------- Cream
D("c1-cream", NIGHT, [(grp([("period", per, coral, False), ("ribbon", body, white, True)], tr=0.2))])
D("c2-cream-solid", NIGHT, [(grp([("period", per, coral, False), ("ribbon", body, white, True)], tr=0.1))])
D("c3-cream-glassier-darktile", NIGHT_WARM, [(grp([("period", per, coral, False), ("ribbon", body, white, True)], tr=0.35))], auto=True)
D("c4-cream-bead-glow", NIGHT, [(grp([("ribbon", body, white, True)], tr=0.2)),
                                (grp([("period", per, coral, True)], shadow="layer-color", shadow_op=0.7, tr=0.3))])

# ---------------------------------------------------------------- Frost
D("f1-frost", AMBER, [(grp([("period", per, white, True), ("ribbon", body, white, True)], shadow_op=0.55, tr=0.2))], auto=True, dark_fill=NIGHT)
D("f2-frost-brand", BRAND, [(grp([("period", per, white, True), ("ribbon", body, white, True)], shadow_op=0.55, tr=0.2))], auto=True, dark_fill=NIGHT)
D("f3-frost-deep", DEEP, [(grp([("period", per, white, True), ("ribbon", body, white, True)], shadow_op=0.55, tr=0.2))], auto=True, dark_fill=NIGHT)
D("f4-frost-glassier", AMBER, [(grp([("period", per, white, False), ("ribbon", body, white, True)], shadow_op=0.55, tr=0.35))], auto=True, dark_fill=NIGHT)

for d in docs:
    print(d.stem)
    render(d, ("Default", "Dark") if d.stem.startswith("f") else ("Default",))
