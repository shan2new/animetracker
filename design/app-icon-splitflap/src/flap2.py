"""Split-Flap A (dark) and D (light), iterated. One parameter set per iteration; each run renders both icons
in the four appearances with ictool and writes a review sheet (large, 60 pt, 29 pt, modes, home screen)."""
import sys, json, subprocess, importlib
sys.path.insert(0, str(__import__("pathlib").Path(__file__).parent))
from kit import *
from pathlib import Path
HERE = Path(__file__).parent
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
LOGO = HERE

def vgrad(y0, y1, c0, c1):
    t = np.clip((Y - y0) / (y1 - y0), 0, 1)[..., None]
    return hexc(c0) * (1 - t) + hexc(c1) * t

def p_mask(p, Xa=None, Ya=None):
    Xa = X if Xa is None else Xa; Ya = Y if Ya is None else Ya
    x0 = p["p_cx"] - p["p_w"] / 2; bowl_bot = p["seam0"] - p["bowl_gap"]
    ro = (bowl_bot - p["cap0"]) / 2; ri = ro - p["bowl"]; xc = x0 + p["p_w"] - ro; cy = p["cap0"] + ro
    half = lambda r: minus(circle(Xa, Ya, xc, cy, r), rbox(Xa, Ya, -10, -10, xc - 4, S + 10, 0))
    outer = U(rbox(Xa, Ya, x0, p["cap0"], xc + 4, bowl_bot, p["corner"]), half(ro))
    outer = U(outer, rbox(Xa, Ya, x0, p["cap0"], x0 + p["stem"] + 20, bowl_bot, p["corner"]))
    counter = U(rbox(Xa, Ya, x0 + p["stem"] - 4, p["cap0"] + p["bowl"], xc + 4, bowl_bot - p["bowl"], p["counter_r"]), half(ri))
    return aa(minus(U(rbox(Xa, Ya, x0, p["cap0"], x0 + p["stem"], p["cap1"], p["corner"]), outer), counter))

def save(a, rgb, path):
    rgb = np.broadcast_to(rgb, (S, S, 3)) if np.ndim(rgb) == 1 else rgb
    im = np.zeros((S, S, 4), dtype=np.uint8)
    im[..., :3] = np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8); im[..., 3] = np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(im).save(path)

def G(layers, glass=True, shadow=("neutral", 0.45), tr=0.0, blur=0.0, specular=True):
    return dict(layers=[(n, a, c, glass) for n, a, c in layers], lighting="individual", specular=specular,
                shadow={"kind": shadow[0], "opacity": shadow[1]}, translucency={"enabled": tr > 0, "value": tr}, blur=blur)

def build(out_dir, name, groups, grd):
    doc = out_dir / f"{name}.icon"; (doc / "Assets").mkdir(parents=True, exist_ok=True)
    groups = groups + [G([("ground",) + grd], glass=False, shadow=("neutral", 0.0), specular=False)]
    gj = []
    for g in groups:
        lj = []
        for n, a, c, glass in g["layers"]:
            save(a, c, doc / "Assets" / f"{n}.png"); lj.append({"name": n, "image-name": f"{n}.png", "glass": glass})
        gj.append({k: v for k, v in g.items() if k != "layers"} | {"layers": lj})
    (doc / "icon.json").write_text(json.dumps({"fill": {"solid": "display-p3:0,0,0,1"}, "groups": gj,
                                               "supported-platforms": {"circles": ["watchOS"], "squares": "shared"}}, indent=1))
    outs = {}
    for rend, extra in (("Default", []), ("Dark", []), ("TintedDark", ["--tint-color", "0.08", "--tint-strength", "0.9"]),
                        ("TintedLight", ["--tint-color", "0.55", "--tint-strength", "0.9"]), ("ClearDark", []), ("ClearLight", [])):
        o = out_dir / f"{name}-{rend}.png"
        subprocess.run([ICTOOL, str(doc), "--export-image", "--output-file", str(o), "--platform", "iOS", "--rendition", rend,
                        "--width", "1024", "--height", "1024", "--scale", "1"] + extra, capture_output=True)
        outs[rend] = o
    return outs

def icon(out_dir, name, p, pal):
    mods = p["mods"]
    tops, bots, pins, housing = (np.zeros((S, S)) for _ in range(4))
    for (a, b) in mods:
        tops = np.maximum(tops, np.maximum(aa(rbox(X, Y, a, p["top"], b, p["seam0"], p["flap_r"])) * (Y < p["seam0"] + 1),
                                           aa(rbox(X, Y, a, p["top"] + 80, b, p["seam0"], p["seam_r"]))))
        bots = np.maximum(bots, np.maximum(aa(rbox(X, Y, a, p["seam1"], b, p["bot"], p["flap_r"])),
                                           aa(rbox(X, Y, a, p["seam1"], b, p["bot"] - 80, p["seam_r"]))))
        c = (p["seam0"] + p["seam1"]) / 2
        if p["pins"] == "round":
            pins = np.maximum(pins, aa(U(circle(X, Y, a - p["pin_off"], c, p["pin_r"]), circle(X, Y, b + p["pin_off"], c, p["pin_r"]))))
        else:
            pins = np.maximum(pins, aa(U(rbox(X, Y, a - 13, p["seam0"] - 14, a + 3, p["seam1"] + 14, 5), rbox(X, Y, b - 3, p["seam0"] - 14, b + 13, p["seam1"] + 14, 5))))
        if p.get("housing"):
            e = p["housing"]
            housing = np.maximum(housing, aa(rbox(X, Y, a - e, p["top"] - e, b + e, p["bot"] + e, p["flap_r"] + e)))
    P = p_mask(p)
    top_rgb = vgrad(p["top"], p["seam0"], pal["top0"], pal["top1"])
    top_rgb = top_rgb * (1 + p["crown"] * np.clip(1 - (Y - p["top"]) / 40, 0, 1))[..., None]
    edge = np.clip(1 - np.abs(Y - (p["seam0"] - 3)) / 3, 0, 1)
    top_rgb = top_rgb * (1 + p["edge_light"] * edge)[..., None]
    bot_rgb = vgrad(p["seam1"], p["bot"], pal["bot0"], pal["bot1"])
    bot_rgb = bot_rgb * (1 - p["cast"] * np.clip(1 - (Y - p["seam1"]) / p["cast_len"], 0, 1) ** 1.3)[..., None]
    dot = aa(circle(X, Y, p["dot"][0], p["dot"][1], p["dot_r"]))
    # Four groups at most: actool refuses an iOS 26 icon with more ("Too many visible groups"), a
    # limit Icon Composer's own renderer does not enforce. The flaps and their pins share a group.
    groups = [G([("stop", dot, hexc(pal["dot"]))], shadow=("layer-color", p["dot_shadow"])),
              G([("letter-top", P * (Y < p["seam0"]), hexc(pal["ink"])), ("letter-bottom", P * (Y > p["seam1"]), hexc(pal["ink"]))],
                shadow=("neutral", p["ink_shadow"]), tr=p.get("ink_tr", 0.0), glass=pal.get("ink_glass", True)),
              G([("pins", pins, hexc(pal["pin"])), ("flaps-top", tops, top_rgb), ("flaps-bottom", bots, bot_rgb)],
                tr=p["flap_tr"], blur=p["flap_blur"], shadow=("neutral", 0.5))]
    if p.get("housing"):
        groups.append(G([("housing", housing, hexc(pal["housing"]))], tr=0.1, shadow=("neutral", 0.4)))
    t = np.clip((X * 0.2 + Y * 0.8) / S, 0, 1)[..., None]
    grd = hexc(pal["g0"]) * (1 - t) + hexc(pal["g1"]) * t
    gx, gy, gr, gc, ga = pal["glow"]
    g = (np.exp(-((X - gx) ** 2 + (Y - gy) ** 2) / (2 * gr * gr)) * ga)[..., None]
    return build(out_dir, name, groups, (np.ones((S, S)), grd * (1 - g) + hexc(gc) * g))

def review(out_dir, res, title):
    tf = ImageFont.truetype(FONT + "Outfit-SemiBold.ttf", 28); lf = ImageFont.truetype(FONT + "Outfit-Regular.ttf", 17)
    home = Image.open(LOGO / "home_now.png").convert("RGBA")
    W = 1900; sheet = Image.new("RGBA", (W, 1180), (18, 18, 22, 255)); d = ImageDraw.Draw(sheet)
    d.text((30, 20), title, font=tf, fill=(240, 240, 240))
    for i, k in enumerate(("A", "D")):
        x0 = 30 + i * 470
        sheet.alpha_composite(Image.open(res[k]["Default"]).convert("RGBA").resize((440, 440), Image.LANCZOS), (x0, 70))
        for j, rend in enumerate(("Default", "Dark", "TintedDark", "TintedLight", "ClearDark", "ClearLight")):
            sm = Image.open(res[k][rend]).convert("RGBA").resize((66, 66), Image.LANCZOS)
            sheet.alpha_composite(sm, (x0 + j * 74, 530)); d.text((x0 + j * 74, 600), ["60pt", "Dark", "TintD", "TintL", "ClrD", "ClrL"][j], font=lf, fill=(125, 125, 135))
        for j, px in enumerate((180, 120, 87)):
            sm = Image.open(res[k]["Default"]).convert("RGBA").resize((px, px), Image.LANCZOS)
            sheet.alpha_composite(sm, (x0 + [0, 196, 332][j], 640 + (180 - px) // 2))
        d.text((x0, 830), ["A · dark", "D · light"][i] + "  —  180 / 120 / 87 px (60 / 40 / 29 pt @3x)", font=lf, fill=(140, 140, 150))
    for i, k in enumerate(("A", "D")):
        h = home.copy(); h.alpha_composite(Image.open(res[k]["Default"]).convert("RGBA").resize((192, 192), Image.LANCZOS), (903, 536))
        ph = h.crop((0, 60, 1179, 1100)).resize((440, 388), Image.LANCZOS)
        m = Image.new("L", ph.size, 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, 439, 387], radius=22, fill=255)
        sheet.paste(ph, (980 + i * 460, 70), m)
    sheet.save(out_dir / "review.png"); return sheet

if __name__ == "__main__":
    it = sys.argv[1]
    cfg = importlib.import_module(f"iter{it}")
    out = HERE / f"iter{it}"; out.mkdir(exist_ok=True)
    res = {"A": icon(out, "A", cfg.P, cfg.DARK), "D": icon(out, "D", cfg.P, cfg.LIGHT)}
    review(out, res, cfg.TITLE)
    print("done", it)
