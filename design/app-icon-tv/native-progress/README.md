# Previously — progress bezel study

The television's frame doubles as a viewing-progress indicator. Amber marks the watched portion, a coral point marks the current position, and the remaining lower-right edge stays translucent. The screen is quiet and the feet are plain. This is an exploratory design, awaiting selection.

## Editable document

`Previously-Progress.icon` is the authoritative Icon Composer document. Its five flat SVG layers are arranged in four native material groups. Brand colors are amber `#F0A24E` and coral `#F0563F`. Icon Composer supplies the highlights, translucency, shadows, refraction, and platform mask.

The matte feet share the foremost group with the coral marker but have glass disabled. Keeping them above the glass track prevents their geometry from producing an unwanted refracted stripe inside the lower-right bezel.

The document opens in Icon Composer 2.0 (109.4) with design generation 27 selected and no layer-count warning. Default and Dark previews were exported successfully with Apple's native `ictool`; the 60-pixel Default render and the native Mono appearance were also visually inspected.

## Previews and sources

- `previews/Default-1024.png`: native Default appearance
- `previews/Dark-1024.png`: native Dark appearance
- `previews/Default-60.png`: native rendering at 60 pixels
- `source/*.svg`: flat source geometry, matching the package assets
- `source/icon-core.json`: portable construction validated with the installed compose-app-icon skill

The installed skill's schema predates Composer 2.0's `features`, `refractivity`, and string-valued `specular` fields. The final package includes these native material annotations, verified by Composer and its renderer. Rebuilding from the portable core alone would reset those annotations.

Workflow reference: [Apple Icon Composer](https://developer.apple.com/icon-composer/).
