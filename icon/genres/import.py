#!/usr/bin/env python3
"""Import the genre art into the iOS asset catalogue.

Discover → Genres draws one tile per genre in Apple Music's Browse grammar: the picture full-bleed,
graded into ONE colour, the genre's name in white at its foot
(ios/Sources/Features/Discover/DiscoverGenres.swift). A genre has up to two pictures — an ANIME one
(an illustration) and a TV one (a photograph) — and the app draws the one that fits the viewer
(`GenreArt`). This script turns the generated sources into what the app loads:

    icon/genres/src/<flavour>/<key>.png   (or .jpg / .jpeg / .webp)      flavour: anime | tv
      → ios/Resources/Assets.xcassets/Genres/genre-<key>-<flavour>.imageset   (JPEG, @2x + @3x)

On the way every picture is
  · cropped to the tile's 16:9 (centred — art made to the brief is 16:9 already), and
  · GRADED, Apple Music's way: the picture's light and dark mapped onto its genre's colour — a
    duotone from a deep shade to a bright tint of one hue (`GENRES`: a hue and a depth). Both
    flavours of a genre share the grade, so switching the flavour changes the picture, never the
    tile's colour.

It also writes a contact sheet per flavour — icon/genres/sheet-<flavour>.png, the tiles as the app
draws them, name and all — so a composition can be judged without building the app.

Re-running replaces what it wrote; an imageset whose source is gone is deleted, so the catalogue
always matches src/. It reports, per flavour, what `GENRES` needs and src/ lacks.

    python3 icon/genres/import.py          # import, grade, sheets
    python3 icon/genres/import.py --raw    # skip the grade (to see the sources as generated)

Needs Pillow and NumPy (`pip3 install pillow numpy`).
"""
import json
import math
import pathlib
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = ROOT / "icon" / "genres"
SRC = HERE / "src"
DEST = ROOT / "ios" / "Resources" / "Assets.xcassets" / "Genres"
FONT = ROOT / "ios" / "Resources" / "Fonts" / "Outfit-Bold.ttf"

ANIME, TV = "anime", "tv"
FLAVOURS = (ANIME, TV)
BOTH = (ANIME, TV)

# The server's vocabulary (server/src/discover/genres.ts) — keep in step with it. Per key: the name
# (for the sheets); the flavours it NEEDS — a genre only one catalogue files holds only that
# catalogue's shows, so it only gets that catalogue's picture (Mecha is anime whoever is looking; a
# live-action Mecha photo would promise a tile of shows that are not there); and its grade, an
# OKLCH hue in degrees and a depth (`DEPTHS`). The grid is ordered by title count, so any two
# genres can be neighbours: within a depth no two hues are closer than 25°, and the depth tells
# apart the ones that share a hue family (Action / Horror, Drama / Mecha, Mystery / Crime).
GENRES = {
    # key              name              flavours  hue  depth
    "action":          ("Action",         BOTH,      30, "bright"),
    "adventure":       ("Adventure",      BOTH,     145, "mid"),
    "comedy":          ("Comedy",         BOTH,     100, "bright"),
    "drama":           ("Drama",          BOTH,     255, "mid"),
    "fantasy":         ("Fantasy",        BOTH,     288, "mid"),
    "sci-fi":          ("Sci-Fi",         BOTH,     220, "bright"),
    "mystery":         ("Mystery",        BOTH,     200, "mid"),
    "romance":         ("Romance",        (ANIME,),   0, "bright"),
    "horror":          ("Horror",         (ANIME,),  25, "dark"),
    "thriller":        ("Thriller",       (ANIME,),  65, "dark"),
    "psychological":   ("Psychological",  (ANIME,), 320, "mid"),
    "supernatural":    ("Supernatural",   (ANIME,), 280, "dark"),
    "slice-of-life":   ("Slice of Life",  (ANIME,),  65, "bright"),
    "sports":          ("Sports",         (ANIME,), 135, "bright"),
    "mecha":           ("Mecha",          (ANIME,), 245, "dark"),
    "music":           ("Music",          (ANIME,), 335, "bright"),
    "mahou-shoujo":    ("Mahou Shoujo",   (ANIME,), 300, "bright"),
    "crime":           ("Crime",          (TV,),    190, "dark"),
    "documentary":     ("Documentary",    (TV,),     85, "mid"),
    "family":          ("Family",         (TV,),     20, "mid"),
    "reality":         ("Reality",        (TV,),    350, "mid"),
    "war-politics":    ("War & Politics", (TV,),    115, "dark"),
    "western":         ("Western",        (TV,),     50, "mid"),
    "animation":       ("Animation",      (TV,),    175, "bright"),
}

# A depth is where the picture's middle tones land: `bright` is Apple Music's Pop and Bollywood (a
# light ground, the subject a deeper figure on it), `mid` its Punjabi, `dark` its Concerts (a dark
# ground with the light picked out). OKLab lightness and chroma, measured off Apple's tiles (their
# grounds sit at L 0.55–0.69): the name is white, and white on L 0.69 is ~2.9:1, so no depth lifts a
# ground past that — at 0.74 Comedy's yellow and Animation's mint left the name at 2.3:1.
DEPTHS = {
    #          shadow L  highlight L  gamma  shadow C  highlight C
    "bright": (0.26,     0.69,        0.80,  0.08,     0.17),
    "mid":    (0.18,     0.62,        1.05,  0.07,     0.15),
    "dark":   (0.10,     0.58,        1.45,  0.05,     0.13),
}

# The tile is 16:9 and at most ~240 pt wide (two across on the widest iPhone is 198 pt; one across
# at the accessibility sizes is wider and takes a slight upscale rather than every tile carrying
# four times the pixels it needs). No iOS 18 device is @1x.
ASPECT = 16 / 9
POINTS_WIDE = 240
SCALES = (2, 3)
EXTENSIONS = (".png", ".jpg", ".jpeg", ".webp")


# ---- OKLab (Björn Ottosson's) ----

def _to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _to_gamma(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def lightness(rgb):
    """OKLab L of an sRGB array in 0…1."""
    r, g, b = (_to_linear(rgb[..., i]) for i in range(3))
    l_ = np.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m_ = np.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s_ = np.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_


def _oklab_to_linear(L, a, b):
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960771 * l - 0.7034186147 * m + 1.7076147010 * s)


def _max_chroma(hue):
    """The largest in-gamut chroma at each of 256 lightnesses, for one hue (bisection)."""
    h = math.radians(hue)
    Ls = np.linspace(0, 1, 256)
    lo, hi = np.zeros(256), np.full(256, 0.4)
    for _ in range(24):
        mid = (lo + hi) / 2
        r, g, b = _oklab_to_linear(Ls, mid * math.cos(h), mid * math.sin(h))
        inside = (np.minimum(np.minimum(r, g), b) >= -1e-4) & (np.maximum(np.maximum(r, g), b) <= 1 + 1e-4)
        lo, hi = np.where(inside, mid, lo), np.where(inside, hi, mid)
    return lo


def grade(rgb, hue, depth):
    """The picture as a duotone of one hue: its lightness (auto-levelled) mapped from the depth's
    shadow to its highlight, chroma rising with it and kept inside sRGB."""
    shadow_l, high_l, gamma, shadow_c, high_c = DEPTHS[depth]
    L = lightness(rgb)
    lo, hi = np.percentile(L, 1), np.percentile(L, 99)
    t = np.clip((L - lo) / max(hi - lo, 1e-3), 0, 1) ** gamma
    out_l = shadow_l + (high_l - shadow_l) * t
    out_c = shadow_c + (high_c - shadow_c) * t
    limit = _max_chroma(hue)
    out_c = np.minimum(out_c, 0.97 * np.interp(out_l, np.linspace(0, 1, 256), limit))
    h = math.radians(hue)
    r, g, b = _oklab_to_linear(out_l, out_c * math.cos(h), out_c * math.sin(h))
    return np.stack([_to_gamma(r), _to_gamma(g), _to_gamma(b)], axis=-1)


# ---- Import ----

def crop_to_tile(image):
    w, h = image.size
    if w / h > ASPECT:
        cw = round(h * ASPECT)
        x0 = (w - cw) // 2
        return image.crop((x0, 0, x0 + cw, h))
    ch = round(w / ASPECT)
    y0 = (h - ch) // 2
    return image.crop((0, y0, w, y0 + ch))


def source_for(flavour, key):
    for ext in EXTENSIONS:
        path = SRC / flavour / f"{key}{ext}"
        if path.exists():
            return path
    return None


def write_imageset(name, image):
    folder = DEST / f"{name}.imageset"
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    images = [{"idiom": "universal", "scale": "1x"}]
    for scale in SCALES:
        width = POINTS_WIDE * scale
        size = (width, round(width / ASPECT))
        filename = f"{name}@{scale}x.jpg"
        # 4:4:4 — a duotone is all saturated edges, and 4:2:0 smears them.
        image.resize(size, Image.LANCZOS).save(folder / filename, quality=88, subsampling=0, optimize=True)
        images.append({"idiom": "universal", "filename": filename, "scale": f"{scale}x"})
    (folder / "Contents.json").write_text(json.dumps(
        {"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


# ---- Contact sheet: the tiles as DiscoverGenres draws them (two across on a 393-pt phone) ----

SHEET_SCALE = 2
PHONE, GUTTER, GAP, RADIUS = 393, 16, 12, 10
NAME_SIZE, NAME_INSET, NAME_BOTTOM = 18, 12, 12   # Outfit Bold 18; the text frame 12 pt in
CANVAS = (9, 9, 11)


def _wrap(draw, name, font, width):
    """Two lines at the spaces; a single word that will not fit shrinks instead (the app's rule)."""
    if draw.textlength(name, font=font) <= width or " " not in name:
        return [name]
    words, lines, line = name.split(), [], ""
    for word in words:
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    lines.append(line)
    return lines[:2]


def draw_tile(image, name, size):
    s = SHEET_SCALE
    tile_w, tile_h = size
    if image is None:
        tile = Image.new("RGB", size, (28, 28, 32))
    else:
        tile = image.resize(size, Image.LANCZOS)
    draw = ImageDraw.Draw(tile)
    font_size = NAME_SIZE * s
    font = ImageFont.truetype(str(FONT), font_size)
    usable = tile_w - 2 * NAME_INSET * s
    lines = _wrap(draw, name, font, usable)
    while len(lines) == 1 and draw.textlength(lines[0], font=font) > usable and font_size > NAME_SIZE * s * 0.7:
        font_size -= 1
        font = ImageFont.truetype(str(FONT), font_size)
    ascent, descent = font.getmetrics()
    line_h = ascent + descent
    baseline = tile_h - NAME_BOTTOM * s - descent
    for i, line in enumerate(reversed(lines)):
        draw.text((NAME_INSET * s, baseline - i * line_h), line, font=font, fill=(255, 255, 255), anchor="ls")
    if image is None:
        small = ImageFont.truetype(str(FONT), 11 * s)
        draw.text((NAME_INSET * s, NAME_INSET * s), "missing", font=small, fill=(120, 120, 130), anchor="lt")
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=RADIUS * s, fill=255)
    return tile, mask


def write_sheet(flavour, tiles, graded):
    s = SHEET_SCALE
    tile_w = (PHONE - 2 * GUTTER - GAP) / 2
    size = (round(tile_w * s), round(tile_w / ASPECT * s))
    rows = (len(tiles) + 1) // 2
    header = 40
    height = round(header * s + rows * (size[1] + GAP * s) + GUTTER * s)
    sheet = Image.new("RGB", (PHONE * s, height), CANVAS)
    draw = ImageDraw.Draw(sheet)
    label = ImageFont.truetype(str(FONT), 13 * s)
    have = sum(1 for _, _, image in tiles if image is not None)
    draw.text((GUTTER * s, 20 * s), f"{flavour} · {have}/{len(tiles)} · {'graded' if graded else 'raw'}",
              font=label, fill=(150, 150, 160), anchor="lm")
    for i, (_, name, image) in enumerate(tiles):
        tile, mask = draw_tile(image, name, size)
        x = round((GUTTER + (i % 2) * (tile_w + GAP)) * s)
        y = round(header * s + (i // 2) * (size[1] + GAP * s))
        sheet.paste(tile, (x, y), mask)
    sheet.save(HERE / f"sheet-{flavour}.png", optimize=True)


def main():
    graded = "--raw" not in sys.argv[1:]
    if not SRC.is_dir():
        print(f"no source folder: {SRC}")
        return 1
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

    written = set()
    for flavour in FLAVOURS:
        folder = SRC / flavour
        present = {p.stem for p in folder.iterdir() if p.suffix.lower() in EXTENSIONS} if folder.is_dir() else set()
        unknown = sorted(present - set(GENRES))
        unneeded = sorted(k for k in present & set(GENRES) if flavour not in GENRES[k][1])
        imported, missing, tiles = [], [], []
        for key, (name, flavours, hue, depth) in GENRES.items():
            if flavour not in flavours:
                continue
            path = source_for(flavour, key)
            if path is None:
                missing.append(key)
                tiles.append((key, name, None))
                continue
            image = crop_to_tile(Image.open(path).convert("RGB"))
            if image.size[0] < POINTS_WIDE * SCALES[-1]:
                print(f"  ! {flavour}/{key}: {image.size[0]} px wide is below "
                      f"{POINTS_WIDE * SCALES[-1]} px; it will be upscaled")
            if graded:
                pixels = np.asarray(image, dtype=np.float64) / 255
                image = Image.fromarray((grade(pixels, hue, depth) * 255 + 0.5).astype(np.uint8))
            write_imageset(f"genre-{key}-{flavour}", image)
            written.add(f"genre-{key}-{flavour}")
            imported.append(key)
            tiles.append((key, name, image))
        write_sheet(flavour, tiles, graded)
        needed = len(imported) + len(missing)
        print(f"{flavour}: imported {len(imported)}/{needed}" + (f" · missing: {', '.join(missing)}" if missing else ""))
        if unneeded:
            print(f"  not imported — {flavour} is not a catalogue these genres hold: {', '.join(unneeded)}")
        if unknown:
            print(f"  unknown keys ignored: {', '.join(unknown)}")

    # The catalogue matches src/: an imageset nothing wrote this run goes (a removed source, or an
    # older name such as the flavourless `genre-<key>`).
    for folder in DEST.glob("genre-*.imageset"):
        if folder.name[: -len(".imageset")] not in written:
            shutil.rmtree(folder)
    print(f"sheets: {', '.join(str((HERE / f'sheet-{f}.png').relative_to(ROOT)) for f in FLAVOURS)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
