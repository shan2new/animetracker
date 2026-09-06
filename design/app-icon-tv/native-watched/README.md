# Previously — native watched-TV study

An exploratory app icon: a television plus a completion mark represents tracking what has been watched. This is a design study, not an approved replacement for the production icon.

## Editable document

`Previously-Watched.icon` is the authoritative document. It contains five flat SVG layers in four native material groups. The screen and matte feet share one group to respect Icon Composer's four-group limit.

The check uses the app's amber `#F0A24E`; the period uses coral `#F0563F`. Highlights, translucency, shadows, masking, and refraction are applied by Icon Composer. The SVG files contain only flat geometry.

The enclosure material was edited and saved in **Icon Composer 2.0 (109.4), generation 27**:

- Specular alignment: Inside
- Refraction: enabled, strength 18%, depth 8%
- Translucency: 28%
- Screen and feet: glass disabled

Composer added its native `features`, `refractivity`, and string-valued `specular` fields when saving. These newer fields are not represented by the installed `compose-app-icon` skill's older JSON schema. The flat core document passed the skill validator; the final saved document was verified with Apple's native `ictool` renderer.

## Previews

- `previews/Default-1024.png`: final native Default appearance
- `previews/Dark-1024.png`: final native Dark appearance
- `previews/Default-60.png`: final native 60-pixel rendering
- `previews/core-default.png`: initial native material baseline before Composer 2.0 tuning

All final preview exports succeeded after the material settings were saved. The earlier study's command-line export was byte-identical to its GUI export with generation 27 selected, confirming the renderer path used here.

`source/icon-core.json` records the portable construction before the newer material properties were set in the editor. Replacing the final document with that core file would reset the 2.0 material annotations. The sibling SVG sources match the final package assets.

Workflow reference: [Apple Icon Composer](https://developer.apple.com/icon-composer/).
