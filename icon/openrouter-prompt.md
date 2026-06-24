# OpenRouter — generate the AniTrack icon raster

This is ready to run the moment an `OPENROUTER_API_KEY` is available. It produces a
1024×1024 raster following the same concept as the hand-authored SVG layers, to use as
a fallback Asset-Catalog icon (and as a reference for refining the Icon Composer art).

## Recommended model

**`google/gemini-2.5-flash-image`** (a.k.a. "Nano Banana") — currently the strongest,
cheapest, and most reliable image-output model on OpenRouter for clean graphic / logo
work, with aspect-ratio control via `image_config`. It returns a base64 PNG data URL in
the assistant message's `images` array.

- Fallback if that id ever 404s: `google/gemini-2.5-flash-preview-image`.
- Newer preview line (if available in your account): `google/gemini-3.1-flash-image-preview`.

Verify the live id with: `curl https://openrouter.ai/api/v1/models | jq '.data[].id' | grep image`

## The image prompt (paste as the user message)

> A premium minimalist iOS app icon for "AniTrack", an airing-first anime tracker.
> Centered composition on a 1024x1024 square, full-bleed, NO rounded corners and NO
> drop shadow around the outer square (the OS adds the rounded-rect mask itself).
> Subject: a bold, chunky rounded **play triangle** in warm orange (#F0A24E, top-lit to
> #FFC07A, shaded to #E08A38) sitting on a translucent dark **glass disc** (#20202A to
> #131318) with a soft bright specular highlight along its top rim. Two faint concentric
> warm-orange **broadcast pulse rings** radiate around the disc. A small glowing
> **"new episode" notification dot** sits at the top-right of the disc, warm orange with
> a tiny white specular highlight and a thin dark halo so it pops. Background is a
> near-black vertical gradient (#16161B to #0B0B0E) with a soft warm radial glow behind
> the disc. Style: Apple iOS 26 Liquid Glass, glassy translucency, clean specular
> highlights, no text, no thin lines, no clutter, high contrast, reads clearly at small
> sizes. Square aspect ratio.

## curl (Chat Completions, image output)

```bash
export OPENROUTER_API_KEY="sk-or-..."   # set when available

curl -sS "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "google/gemini-2.5-flash-image",
    "modalities": ["image", "text"],
    "image_config": { "aspect_ratio": "1:1" },
    "messages": [
      { "role": "user", "content": "A premium minimalist iOS app icon for AniTrack, an airing-first anime tracker. Centered on a 1024x1024 square, full-bleed, NO rounded corners and NO outer shadow (the OS adds the rounded mask). Subject: a bold chunky rounded play triangle in warm orange (#F0A24E, top-lit to #FFC07A, shaded to #E08A38) on a translucent dark glass disc (#20202A to #131318) with a bright specular highlight along its top rim. Two faint concentric warm-orange broadcast pulse rings radiate around the disc. A small glowing new-episode notification dot at top-right of the disc, warm orange with a tiny white specular highlight and thin dark halo. Background: near-black vertical gradient (#16161B to #0B0B0E) with a soft warm radial glow behind the disc. Style: Apple iOS 26 Liquid Glass, glassy translucency, clean specular highlights, no text, no thin lines, no clutter, high contrast, square aspect ratio." }
    ]
  }' > /tmp/anitrack-icon-response.json
```

## Extract the PNG from the response

The image comes back as a base64 data URL in `.choices[0].message.images[0].image_url.url`.

```bash
# strip the "data:image/png;base64," prefix, decode to icon-1024.png
jq -r '.choices[0].message.images[0].image_url.url' /tmp/anitrack-icon-response.json \
  | sed 's/^data:image\/[a-zA-Z]*;base64,//' \
  | base64 --decode > "$(dirname "$0")/icon-1024.png" 2>/dev/null \
  || { jq -r '.choices[0].message.images[0].image_url.url' /tmp/anitrack-icon-response.json \
        | sed 's/^data:image\/[a-zA-Z]*;base64,//' | base64 --decode > icon-1024.png; }

# Verify it is exactly 1024x1024; if the model returned another size, resize:
#   sips -z 1024 1024 icon-1024.png        (macOS, built-in)
sips -g pixelWidth -g pixelHeight icon-1024.png
```

Drop the resulting `icon-1024.png` into both this folder and
`AppIcon-fallback.appiconset/` (the `Contents.json` already references that filename),
then follow `README.md` to wire it into Xcode.

## Notes
- `modalities` MUST include `"image"` or the model returns text only.
- If you prefer a one-fixed-provider deterministic route, append `:exacto` style routing
  via the OpenRouter `provider` field, or use the Nitro/Balanced default.
- Always sanity-check the raster against `concept.md`: orange mark, dark glass disc,
  pulse rings, top-right dot, full-bleed, no pre-baked rounded corners.
