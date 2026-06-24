#!/usr/bin/env bash
# Generate AniTrack logo experiments via OpenRouter (gpt-5-image-mini).
# Requires: OPENROUTER_API_KEY in env. Writes PNGs into this folder.
set -uo pipefail
cd "$(dirname "$0")"

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  echo "ERROR: OPENROUTER_API_KEY is not set in the environment." >&2
  exit 3
fi

MODEL="${MODEL:-openai/gpt-5-image-mini}"

COMMON="Premium minimalist iOS app icon for a modern anime tracker app. Full-bleed 1024x1024 square composition, NO rounded corners and NO outer drop shadow (the OS applies the rounded-rect mask itself). Single centered focal element with generous negative space. No text, no letters, no words, no clutter, no thin fragile lines. Apple iOS 26 Liquid Glass aesthetic: subtle material depth, translucency and a clean specular highlight, but do NOT bake in heavy gloss. Modern, sophisticated, high contrast, reads clearly when shrunk to a tiny home-screen tile. Warm-but-not-gold palette: deep plum #2A0F3A mesh gradient blending into near-black #0E0E12, with a soft warm radial glow; accents in glowing electric coral #FF4D6D to hot magenta-pink (absolutely NO gold, amber, yellow or orange). Square aspect ratio."

declare -a NAMES=(
  "01-kinetic-play"
  "02-light-arc"
  "03-episode-stack"
  "04-kinetic-strike"
)
declare -a PROMPTS=(
  "FOCAL ELEMENT: a bold, crisp geometric play triangle whose trailing edge dissolves into three tapered anime-style speed/motion streaks sweeping to the right, conveying momentum and 'the next episode'. The play glyph and its motion streaks glow in electric coral to hot magenta-pink with a glassy specular highlight on the top edge. $COMMON"
  "FOCAL ELEMENT: a single clean thin circular orbit ring set slightly off-center (a weekly airing-cycle motif), with one brilliant four-point starlight glint / lens-flare sparkle catching the top of the ring — anime's signature dramatic light, abstracted. Ring and glint glow in an electric coral to hot-pink gradient. Calm, elegant, cyclical. $COMMON"
  "FOCAL ELEMENT: three overlapping rounded translucent glass tiles/frames receding into depth at a slight 3D tilt — a watch queue / 'up next' stack, an abstracted manga-panel grid. Frosted glassmorphic edges catch light. The tiles graduate from deep plum into electric coral and hot pink. $COMMON"
  "FOCAL ELEMENT: three bold tapered diagonal motion/speed slashes sweeping upward to the right — pure abstract anime velocity with zero literal media cliche. Sharp, energetic, glassy specular highlights. Slashes glow electric coral to hot pink. $COMMON"
)

for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"
  prompt="${PROMPTS[$i]}"
  echo ">>> Generating ${name} ..."
  resp="resp-${name}.json"
  jq -n --arg m "$MODEL" --arg p "$prompt" '{
    model: $m,
    modalities: ["image","text"],
    image_config: { aspect_ratio: "1:1" },
    messages: [ { role: "user", content: $p } ]
  }' > "req-${name}.json"

  http=$(curl -sS -w '%{http_code}' -o "$resp" \
    "https://openrouter.ai/api/v1/chat/completions" \
    -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
    -H "Content-Type: application/json" \
    --data @"req-${name}.json")

  if [ "$http" != "200" ]; then
    echo "  HTTP $http — response head:" >&2
    head -c 600 "$resp" >&2; echo >&2
    continue
  fi

  url=$(jq -r '.choices[0].message.images[0].image_url.url // empty' "$resp")
  if [ -z "$url" ]; then
    echo "  No image in response. Body head:" >&2
    head -c 600 "$resp" >&2; echo >&2
    continue
  fi
  echo "$url" | sed 's/^data:image\/[a-zA-Z]*;base64,//' | base64 --decode > "${name}.png"
  if [ -s "${name}.png" ]; then
    dims=$(sips -g pixelWidth -g pixelHeight "${name}.png" 2>/dev/null | awk '/pixel/{print $2}' | paste -sd x -)
    echo "  OK -> ${name}.png (${dims})"
  else
    echo "  Decoded to empty file." >&2
  fi
done
echo ">>> Done."
