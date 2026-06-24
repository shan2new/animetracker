#!/usr/bin/env bash
# Round 2: force full-bleed dark field + solid glowing-glass treatment (the look that
# made 04 work). Regenerate the three weak concepts + two variations of the winner.
set -uo pipefail
cd "$(dirname "$0")"
: "${OPENROUTER_API_KEY:?set OPENROUTER_API_KEY}"
MODEL="${MODEL:-openai/gpt-5-image-mini}"

# Background instruction FIRST and forceful — the model dropped it last time.
BG="The ENTIRE 1024x1024 square is filled EDGE TO EDGE with a dark background — a deep plum #2A0F3A mesh gradient sinking into near-black #0E0E12, with a soft warm glow behind the subject. ABSOLUTELY NO white background, NO transparency, NO empty space, NO light/pale areas: every pixel to all four edges is dark. This is a full-bleed iOS app icon."
COMMON="Premium minimalist iOS app icon for a modern anime tracker app. Full-bleed 1024x1024 square, NO rounded corners and NO outer drop shadow (the OS adds the rounded mask). Single centered focal element, generous negative space, no text or letters, no clutter. The subject is a SOLID, chunky, glowing GLASS shape with a clean specular highlight (NOT a thin wireframe outline) so it holds at tiny sizes. Apple iOS 26 Liquid Glass: material depth and translucency, modern and sophisticated, high contrast. Accents glow in electric coral #FF4D6D to hot magenta-pink — absolutely NO gold, amber, yellow or orange. Square aspect ratio."

declare -a NAMES=(
  "05-play-v2"
  "06-arc-v2"
  "07-stack-v2"
  "08-strike-altA"
  "09-strike-altB"
)
declare -a PROMPTS=(
  "$BG FOCAL ELEMENT: a bold, solid geometric play triangle in glowing electric coral-to-hot-pink glass, its trailing edge breaking into a few tapered anime speed/motion streaks sweeping right (momentum, 'next episode'). Bright specular highlight on the top edge. $COMMON"
  "$BG FOCAL ELEMENT: a thick, solid glowing ring/orbit of electric coral-to-hot-pink glass (a weekly airing-cycle motif), with one brilliant four-point starlight glint catching the top — anime's dramatic light, abstracted. The ring is a substantial glowing band, NOT a hairline. $COMMON"
  "$BG FOCAL ELEMENT: three solid overlapping rounded translucent glass tiles stacked and receding into depth at a slight 3D tilt (a watch queue / 'up next' stack). The tiles are filled frosted glass glowing from deep plum through electric coral to hot pink, with lit edges — NOT empty outlines. $COMMON"
  "$BG FOCAL ELEMENT: a single bold play triangle FUSED with sweeping anime speed slashes behind it, blazing electric coral to hot pink with a glassy specular sheen — media + raw anime velocity in one mark. $COMMON"
  "$BG FOCAL ELEMENT: three bold tapered diagonal motion slashes sweeping upward-right, layered with strong depth and a bright coral-to-magenta neon glow and glass highlights — pure abstract anime velocity, dramatic and energetic. $COMMON"
)

for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"; prompt="${PROMPTS[$i]}"
  echo ">>> ${name} ..."
  jq -n --arg m "$MODEL" --arg p "$prompt" '{model:$m,modalities:["image","text"],image_config:{aspect_ratio:"1:1"},messages:[{role:"user",content:$p}]}' > "req-${name}.json"
  http=$(curl -sS -w '%{http_code}' -o "resp-${name}.json" "https://openrouter.ai/api/v1/chat/completions" \
    -H "Authorization: Bearer ${OPENROUTER_API_KEY}" -H "Content-Type: application/json" --data @"req-${name}.json")
  if [ "$http" != "200" ]; then echo "  HTTP $http"; head -c 500 "resp-${name}.json"; echo; continue; fi
  url=$(jq -r '.choices[0].message.images[0].image_url.url // empty' "resp-${name}.json")
  if [ -z "$url" ]; then echo "  no image"; head -c 500 "resp-${name}.json"; echo; continue; fi
  echo "$url" | sed 's/^data:image\/[a-zA-Z]*;base64,//' | base64 --decode > "${name}.png"
  echo "  OK -> ${name}.png ($(sips -g pixelWidth -g pixelHeight "${name}.png" 2>/dev/null | awk '/pixel/{print $2}' | paste -sd x -))"
done
echo ">>> Done."
