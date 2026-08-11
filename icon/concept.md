# Previously. — App Icon Concept

## The motif: a saved-place bookmark

The mark is one warm, soft-cornered bookmark on a near-black field. Its notch says
“this is where I left off”; the small inset point makes the saved place feel active.
It deliberately avoids a play button, broadcast rings, alert dot, or glass orb.

The silhouette carries the identity at 29 px. The iOS mask and layered-icon system add
the material treatment; the artwork itself stays quiet and unmistakable.

## Palette

| Token | Hex | Use |
|---|---|---|
| Base | `#0B0B0E` | full-bleed background |
| Accent | `#F0A24E` | bookmark body |
| Accent light | `#FFD6A0` | upper light on the ribbon |
| Accent deep | `#C9702E` | lower ribbon depth |

## Source and layers

- `design/app-icon/bookmark-v2.svg` is the complete flat master.
- `bookmark-ground.svg` and `bookmark-mark.svg` generate the two layers consumed by
  `ios/Resources/AppIcon.icon`.
- Keep the artwork full-bleed and without pre-baked rounded outer corners; iOS owns the
  launcher mask.
