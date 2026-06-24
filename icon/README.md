# AniTrack App Icon

Everything needed to ship the AniTrack iOS app icon, following Apple's **iOS 26 Liquid
Glass** layered-icon guidelines. Self-contained in this folder.

## What's here

```
icon/
├── concept.md                     # The icon concept + 3-layer + Default/Dark/Mono spec
├── background.svg                 # Layer 1 (back)  — atmosphere / glow         1024×1024
├── midground.svg                  # Layer 2 (mid)   — glass broadcast disc      1024×1024
├── foreground.svg                 # Layer 3 (front) — play mark + pulse dot      1024×1024
├── icon-flat.svg                  # Flat composite preview (all 3 layers merged) 1024×1024
├── icon-1024.png                  # Rasterized fallback PNG  *(NOT yet generated — see below)*
├── AppIcon-fallback.appiconset/   # Asset Catalog set (single 1024 universal, iOS 26 form)
│   └── Contents.json              #   references icon-1024.png
├── openrouter-prompt.md           # Ready-to-run image-gen prompt + curl for the raster
└── README.md                      # This file
```

## Rasterization status

**`icon-1024.png` has NOT been generated.** No SVG rasterizer was available in this
environment (`rsvg-convert`, `cairosvg`, `inkscape`, `magick`, `convert` all absent).
Generate it with whichever route you prefer:

### Option A — rasterize the hand-authored SVG (offline, deterministic)
Install a rasterizer, then run from this folder:
```bash
# Homebrew: brew install librsvg        (rsvg-convert)  — recommended, crisp
rsvg-convert -w 1024 -h 1024 icon-flat.svg -o icon-1024.png

# or  pip install cairosvg
cairosvg icon-flat.svg -W 1024 -H 1024 -o icon-1024.png

# or  ImageMagick
magick -background none -density 384 icon-flat.svg -resize 1024x1024 icon-1024.png

# or  Inkscape
inkscape icon-flat.svg --export-type=png -w 1024 -h 1024 -o icon-1024.png
```
macOS has no built-in SVG→PNG, but `qlmanage -t -s 1024 -o . icon-flat.svg` can produce
a preview thumbnail in a pinch.

### Option B — generate the raster via OpenRouter (when the key is available)
Follow **`openrouter-prompt.md`** — recommended model **`google/gemini-2.5-flash-image`**.
It writes `icon-1024.png` directly. This gives a richer, AI-painted Liquid-Glass look;
Option A gives an exact, on-brand vector render. Either is a valid fallback.

Once `icon-1024.png` exists, copy it into `AppIcon-fallback.appiconset/` (the
`Contents.json` already points at that filename).

## Full pipeline: SVG layers → Icon Composer → AppIcon.icon → Xcode

The proper, App-Store-grade iOS 26 icon is the **layered** one, built in Apple's **Icon
Composer** (ships with Xcode 26 / macOS 26.4+). The SVGs here are the import-ready layers.

1. **Open Icon Composer** (Xcode ▸ Open Developer Tool ▸ Icon Composer, or `open -a "Icon Composer"`).
2. **Create a new icon**, canvas 1024×1024.
3. **Import the three layers** in order, back to front:
   - `background.svg`  → Background group
   - `midground.svg`   → a middle layer group
   - `foreground.svg`  → Foreground group
   These SVGs are full-bleed with **no pre-baked rounded corners and no pre-baked glass**
   on purpose — Icon Composer + iOS apply the rounded-rect mask and Liquid Glass.
4. **Apply Liquid Glass** per layer: give the midground disc the strongest translucency
   / specular treatment, give the foreground mark a pronounced shadow + parallax. Tune
   highlights so the top rim of the disc and the top of the play triangle catch light.
5. **Configure the three appearances** per `concept.md`:
   - **Default** — full color as authored.
   - **Dark** — deepen the background, dim the glow, keep the orange mark saturated.
   - **Mono (tinted)** — switch layers to white-at-opacity, shape-only (the system tints it).
6. **Export** as **`AppIcon.icon`**.
7. **Add to Xcode**: drag `AppIcon.icon` into your app target's asset area (or set it as
   the app icon source). In iOS 26 the single `.icon` carries all sizes/appearances —
   no more per-size PNG grids. Set the target's **App Icon** build setting to `AppIcon`.

## Immediate fallback (ship today, before Icon Composer art is done)

Until `AppIcon.icon` is finished, the app can ship the flat raster:

1. Produce `icon-1024.png` (Option A or B above).
2. Copy it into `AppIcon-fallback.appiconset/`.
3. Either:
   - Drag `AppIcon-fallback.appiconset` into your `Assets.xcassets`, renaming it
     `AppIcon`, **or**
   - Copy its `Contents.json` + `icon-1024.png` over your existing
     `Assets.xcassets/AppIcon.appiconset/`.
   This is the iOS 26 single-size (1024 universal) asset form — Xcode downscales for all
   home-screen/Settings sizes.

## Swapping the OpenRouter raster in later
If you generated the icon with OpenRouter and later prefer the vector render (or vice
versa), just regenerate/replace `icon-1024.png` and re-copy it into the appiconset — no
other change needed. The layered `AppIcon.icon` always supersedes the flat fallback once
you add it to the target.

## Brand palette (for reference)
| Base `#0B0B0E` · Card `#16161B` · Accent `#F0A24E` · Accent-light `#FFC07A` · Accent-deep `#E08A38` |
