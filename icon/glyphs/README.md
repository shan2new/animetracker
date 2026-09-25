> **Superseded (26 Sep):** every glyph is now a Tabler icon — see `icon/tabler/icons.py`. This
> folder is the retired hand-drawn set; `generate.py` refuses to run without `--force`.

# AniTrack UI glyphs

These 104 compact, rounded outline and filled SVG assets replace the app-owned SF Symbols. They are hand-drawn on a 24-unit grid and rendered as template images for the app and its Live Activity/widget extension. The artwork uses the same single-ink, rounded-line approach as the existing bottom-tab glyphs. The numbered rules badge shares one circle asset and draws its changing number as SwiftUI text.

Regenerate the source SVGs, the shared asset catalog, and the Swift lookup manifest with:

```bash
python3 icon/glyphs/generate.py
```

The script uses `rsvg-convert` to produce 1×, 2×, and 3× transparent PNG renditions in `ios/Shared/AppSymbols.xcassets`, plus the Swift asset-name lookup in `ios/Shared/AppGlyphCatalog.swift`.
