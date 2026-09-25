"""The handover board for Split-Flap A (dark) and D (light), at iteration 3's geometry."""
import sys
sys.path.insert(0, str(__import__("pathlib").Path(__file__).parent))
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import kit
from kit import aa, rbox, circle, U, minus, hexc, S, FONT, X, Y
import flap2, iter3
LOGO = flap2.LOGO; P = iter3.P
tf = ImageFont.truetype(FONT + "Outfit-SemiBold.ttf", 30); lf = ImageFont.truetype(FONT + "Outfit-Regular.ttf", 19)
sf = ImageFont.truetype(FONT + "Outfit-Regular.ttf", 16)
it = {k: f"iter3/{k}-" for k in "AD"}

def rounded(im, r=24):
    m = Image.new("L", im.size, 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=r, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0)); out.paste(im, (0, 0), m); return out

# 1 — the flat mark (the header and the lockup use it): the letter with its seam, the coral stop
def flat_mark(ink=0xF7F1E6, with_stop=True, stop_dx=-220):
    Pm = flap2.p_mask(P) * ((Y < P["seam0"]) | (Y > P["seam1"]))
    dot = aa(circle(X, Y, P["dot"][0] + stop_dx, P["dot"][1], P["dot_r"])) if with_stop else np.zeros((S, S))
    rgba = np.zeros((S, S, 4)); rgba[..., :3] = hexc(ink) * Pm[..., None]; rgba[..., 3] = Pm
    rgba[..., :3] = rgba[..., :3] * (1 - dot[..., None]) + hexc(0xFF5A45) * dot[..., None]; rgba[..., 3] = np.maximum(rgba[..., 3], dot)
    im = Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8)); return im.crop(im.getbbox())

# 2 — the launch: the board at the final geometry, flipping to P.
MODS = P["mods"]; SEAM0, SEAM1, TOP, BOT = P["seam0"], P["seam1"], P["top"], P["bot"]
def board(stages):
    rgb = np.ones((S, S, 3)) * hexc(0x0B0B0E)
    for i, (x0, x1) in enumerate(MODS):
        stage, s = stages[i]
        tb = aa(rbox(X, Y, x0, TOP, x1, SEAM0, 30)); bb = aa(rbox(X, Y, x0, SEAM1, x1, BOT, 30))
        glyph = flap2.p_mask(P) if i == 0 else aa(circle(X, Y, P["dot"][0], P["dot"][1], P["dot_r"]))
        ink = hexc(0xF7F1E6) if i == 0 else hexc(0xFF5A45)
        rgb = rgb * (1 - tb[..., None]) + hexc(0x3A3843) * tb[..., None]; rgb = rgb * (1 - bb[..., None]) + hexc(0x24232A) * bb[..., None]
        if stage >= 1:
            m = glyph * (Y < SEAM0) * tb; rgb = rgb * (1 - m[..., None]) + ink * m[..., None]
        if stage >= 3:
            m = glyph * (Y > SEAM1) * bb; rgb = rgb * (1 - m[..., None]) + ink * m[..., None]
        if stage == 1:
            f = aa(rbox(X, Y, x0, SEAM0 - (SEAM0 - TOP) * s, x1, SEAM0, 10))
            rgb = rgb * (1 - f[..., None]) + hexc(0x3A3843) * (0.55 + 0.45 * s) * f[..., None]
        if stage == 2:
            f = aa(rbox(X, Y, x0, SEAM1, x1, SEAM1 + (BOT - SEAM1) * s, 10))
            Yc = SEAM1 + (Y - SEAM1) / max(s, 0.05)
            g2 = (flap2.p_mask(P, X, Yc) if i == 0 else aa(circle(X, Yc, P["dot"][0], P["dot"][1], P["dot_r"]))) * (Yc > SEAM1)
            rgb = rgb * (1 - f[..., None]) + hexc(0x24232A) * (0.6 + 0.4 * s) * f[..., None]
            m = g2 * f; rgb = rgb * (1 - m[..., None]) + ink * (0.7 + 0.3 * s) * m[..., None]
        seam = aa(rbox(X, Y, x0, SEAM0, x1, SEAM1, 0)); rgb = rgb * (1 - seam[..., None]) + hexc(0x08080A) * seam[..., None]
        c = (SEAM0 + SEAM1) / 2
        pins = aa(U(circle(X, Y, x0 - 6, c, 13), circle(X, Y, x1 + 6, c, 13))); rgb = rgb * (1 - pins[..., None]) + hexc(0x6E6C78) * pins[..., None]
    return Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).convert("RGBA")

frames = [board(f) for f in [((0, 0), (0, 0)), ((1, 0.5), (0, 0)), ((2, 0.55), (1, 0.45)), ((3, 1), (2, 0.6)), ((3, 1), (3, 1))]]
last = frames[-1]; d = ImageDraw.Draw(last); wf = ImageFont.truetype(FONT + "Outfit-SemiBold.ttf", 92)
w = d.textlength("Previously.", font=wf); x0 = 512 - w / 2
d.text((x0, 862), "Previously", font=wf, fill=(247, 241, 230)); d.text((x0 + d.textlength("Previously", font=wf), 862), ".", font=wf, fill=(255, 90, 69))

# 3 — the board itself
Wd = 1960
sheet = Image.new("RGBA", (Wd, 2420), (18, 18, 22, 255)); ds = ImageDraw.Draw(sheet)
ds.text((40, 26), "Split-Flap — A (dark) and D (light), after three rounds", font=ImageFont.truetype(FONT + "Outfit-SemiBold.ttf", 40), fill=(245, 245, 245))
# the final icons, large
for i, k in enumerate("AD"):
    sheet.alpha_composite(Image.open(it[k] + "Default.png").convert("RGBA").resize((520, 520), Image.LANCZOS), (40 + i * 560, 100))
ds.text((40, 632), "A · dark board", font=tf, fill=(240, 240, 240)); ds.text((600, 632), "D · light board", font=tf, fill=(240, 240, 240))
# appearances and sizes
y0 = 690
for i, k in enumerate("AD"):
    x0 = 40 + i * 560
    for j, (rend, lab) in enumerate((("Default", "Default"), ("Dark", "Dark"), ("TintedDark", "Tinted"), ("TintedLight", "Tinted light"), ("ClearDark", "Clear"))):
        sm = Image.open(it[k] + rend + ".png").convert("RGBA").resize((92, 92), Image.LANCZOS)
        sheet.alpha_composite(sm, (x0 + j * 104, y0)); ds.text((x0 + j * 104, y0 + 98), lab, font=sf, fill=(130, 130, 140))
    for j, px in enumerate((180, 120, 87)):
        sm = Image.open(it[k] + "Default.png").convert("RGBA").resize((px, px), Image.LANCZOS)
        sheet.alpha_composite(sm, (x0 + [0, 196, 332][j], y0 + 140 + (180 - px) // 2))
    ds.text((x0, y0 + 330), "60 · 40 · 29 pt", font=sf, fill=(130, 130, 140))
# the progression
ds.text((1180, 100), "How it got here", font=tf, fill=(240, 240, 240))
prog = [("../r7/out/A-two-flaps-Default.png", "../r7/out/D-light-Default.png", "Start"), ("iter1/A-Default.png", "iter1/D-Default.png", "Round 1"),
        ("iter2/A-Default.png", "iter2/D-Default.png", "Round 2"), ("iter3/A-Default.png", "iter3/D-Default.png", "Round 3")]
for j, (a, dd, lab) in enumerate(prog):
    sheet.alpha_composite(Image.open(a).convert("RGBA").resize((170, 170), Image.LANCZOS), (1180 + j * 190, 150))
    sheet.alpha_composite(Image.open(dd).convert("RGBA").resize((170, 170), Image.LANCZOS), (1180 + j * 190, 334))
    ds.text((1180 + j * 190, 512), lab, font=lf, fill=(150, 150, 160))
notes = ["Round 1  bigger flaps, even margins, round axle pins",
         "Round 2  a taller bowl — the counter opened; the stop kerned in",
         "Round 3  air round the letter; the light board's letter printed, not glass"]
for j, n in enumerate(notes):
    ds.text((1180, 552 + j * 30), n, font=sf, fill=(140, 140, 150))
# the home screen, both
home = Image.open(LOGO / "home_now.png").convert("RGBA")
ds.text((40, 1100), "On the home screen", font=tf, fill=(240, 240, 240))
for i, k in enumerate("AD"):
    h = home.copy(); h.alpha_composite(Image.open(it[k] + "Default.png").convert("RGBA").resize((192, 192), Image.LANCZOS), (903, 536))
    sheet.alpha_composite(rounded(h.crop((0, 60, 1179, 1100)).resize((560, 494), Image.LANCZOS)), (40 + i * 600, 1150))
# the feed header
feed = Image.open(LOGO / "feed_now.png").convert("RGBA")
m = flat_mark(); m = m.resize((round(m.width * 80 / m.height), 80), Image.LANCZOS)
dd = ImageDraw.Draw(feed); dd.rectangle([380, 200, 800, 300], fill=feed.getpixel((600, 170)))
feed.alpha_composite(m, (round(589.5 - m.width / 2), 206))
ds.text((1280, 1100), "The feed's header", font=tf, fill=(240, 240, 240))
sheet.alpha_composite(rounded(feed.crop((0, 60, 1179, 700)).resize((640, 347), Image.LANCZOS)), (1280, 1150))
# the launch
ds.text((40, 1690), "The launch — the board flips to P., then the name", font=tf, fill=(240, 240, 240))
for i, fr in enumerate(frames):
    sheet.alpha_composite(rounded(fr.resize((360, 360), Image.LANCZOS)), (40 + i * 380, 1740))
    ds.text((40 + i * 380, 2112), ["blank", "the top flap falls", "the P lands", "the stop turns", "P. · the name"][i], font=lf, fill=(140, 140, 150))
sheet = sheet.crop((0, 0, Wd, 2170)); sheet.save("handover.png"); print(sheet.size)
