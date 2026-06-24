# AniTrack — App Icon Concept

## The motif: a glass broadcast disc with a play mark + "new episode" pulse dot

AniTrack is an **airing-first** anime tracker — its whole reason for being is "what's
new, what's airing, what dropped today." The icon needs to say *play / broadcast / a
fresh episode just landed* in a single glance, and survive being shrunk to a 40 px
home-screen tile.

**Chosen mark (one, committed):**

> A bold, chunky **play triangle** centered on a translucent **glass disc**, ringed by
> two faint **broadcast pulse rings**, with a small warm **"new episode" notification
> dot** at the top-right.

### Why this over the alternatives

- **Play triangle** is the most universally legible "watch / video / episode" glyph
  there is. It needs zero explanation and reads at any size — no thin strokes, no text.
- The **disc + pulse rings** turn a generic play button into something that says
  *broadcast / airing*, which is AniTrack's specific angle (vs. a generic media app).
- The **notification dot** is the emotional hook: "a new episode is waiting." It also
  gives the icon an asymmetric focal point so it doesn't read as just another play
  button, and it maps directly to the app's core notification feature.
- Rejected: a stylized "A" monogram (generic, doesn't say *anime* or *airing*); a TV /
  CRT (dated, fussy at small sizes); cherry-blossom / sakura cliché (overused, fragile
  at small sizes). The disc reads as a glass lens/orb which suits Liquid Glass perfectly.

The shapes are deliberately **big and rounded** so Icon Composer's Liquid Glass
treatment (specular highlights, edge refraction, parallax across layers) has clean,
chunky geometry to work with.

## Palette

| Token        | Hex       | Use                                  |
|--------------|-----------|--------------------------------------|
| Base         | `#0B0B0E` | near-black background floor          |
| Card surface | `#16161B` | top of background gradient, disc     |
| Accent       | `#F0A24E` | play mark, pulse rings, glow, dot     |
| Accent light | `#FFC07A` | top-lit highlight of the play mark    |
| Accent deep  | `#E08A38` | bottom shade of the play mark         |

## The three layers (Icon Composer import order, back → front)

Apple composes layered icons as foreground / mid / background and applies Liquid Glass
per layer, with subtle parallax between them. Each file is a full-bleed 1024×1024 SVG.

### 1. `background.svg` — atmosphere
- Near-black vertical gradient (`#16161B` → `#0B0B0E`).
- A soft warm radial glow (`#F0A24E`) anchored slightly above center, so the mark feels
  lit from within.
- No geometry, no edges — this is the floor the glass sits on. Full-bleed; never masked
  by content.

### 2. `midground.svg` — the glass broadcast disc
- Two faint concentric **pulse rings** (the "airing" signal).
- A central **glass disc** (`#20202A` → `#131318`) with a warm inner glow and a rim
  highlight that is bright at the top and dark at the bottom — the cue Icon Composer
  amplifies into a Liquid Glass specular edge.
- This layer carries most of the "glassiness" and should get the strongest translucency
  / blur treatment in Icon Composer.

### 3. `foreground.svg` — the mark
- The **bold play triangle** (rounded corners, top-lit orange gradient + a white sheen).
- The **"new episode" pulse dot** at top-right (dark halo so it pops off the disc, warm
  center, small white specular highlight).
- This is the highest-contrast layer and should sit "closest" with the most pronounced
  drop shadow / parallax.

## Variant treatments (Default / Dark / Mono)

Icon Composer produces all three from the same layered source; design intent below.

### Default (light system appearance)
- As authored above: warm orange mark on the dark glass disc over the near-black glow.
- Because AniTrack's brand floor is already dark, the "default" and "dark" icons are
  intentionally close — the brand reads as a premium dark app in both.

### Dark
- Same composition; deepen the background to pure `#0B0B0E` with the glow slightly
  dimmed, and let Icon Composer push the disc translucency a touch further so the glass
  reads against the system dark wallpaper. The orange mark stays full saturation as the
  single point of warmth.

### Mono (tinted)
- Drop all color. Render the mark and disc rim as **white at varying opacity** on a
  transparent/neutral field so the system tint can recolor it:
  - Play triangle: white at ~95%.
  - Pulse dot: white at ~90% with its dark halo removed (use opacity contrast instead).
  - Disc fill: white at ~12–16%; rim at ~25%.
  - Pulse rings: white at ~10%.
- Keep it shape-only — no gradients carry through mono. The play triangle alone must
  still read, since at the smallest tinted sizes the rings/disc nearly vanish.

## Safe area / sizing notes
- Canvas 1024×1024, **full-bleed**, no pre-baked rounded corners and no pre-baked system
  glass — iOS applies the rounded-rect mask and Liquid Glass itself.
- Key content (play mark + dot) sits well within a ~10% safe margin; the disc is ~55% of
  canvas width so nothing important rides the mask edge.
- Minimum stroke / feature weight is large (14 px+ at 1024) so it holds at 40 px.
