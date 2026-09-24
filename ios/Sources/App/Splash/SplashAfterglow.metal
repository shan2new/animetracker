#include <metal_stdlib>
using namespace metal;

// AFTERGLOW — the launch as the lights going down before an episode.
//
// The dark fills with a soft, slowly drifting glow in the brand's warm light — gold, amber, coral,
// a little rose — gathered around the middle of the screen and falling away to the edges, the way
// a screen lights a dim room. The name surfaces in it, soft and warm at first, then crisp white.
// Then the glow gathers and comes to rest in the coral full stop, which keeps a gentle light of
// its own; the page is quiet again, and the app comes up. Nothing is solid or glossy, nothing is
// fast: light, colour and focus only.

struct GlowParams {
    float4 view;    // width, height (points), scale (px/pt), film time
    float4 text;    // the name's box: x, y, w, h (points)
    float4 stop;    // the full stop: centre x, y, radius (points), _
    float4 light;   // glow 0…1, gather 0…1, breath −1…1, _
    float4 name;    // settling front x (points), presence 0…1, warmth 0…1, the stop's light 0…1
    float4 canvas;  // sRGB
    float4 coral;   // sRGB
};

struct GlowVertex { float4 position [[position]]; };

vertex GlowVertex glowVertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    GlowVertex out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

static float glowHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float glowNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = glowHash(i), b = glowHash(i + float2(1, 0)), c = glowHash(i + float2(0, 1)), d = glowHash(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * glowNoise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

/// The warm light's colour for a value 0…1: plum in the shadows, through rose and coral, to
/// amber and a little gold at the brightest.
static float3 warm(float v) {
    float3 plum  = float3(0.20, 0.05, 0.10);
    float3 rose  = float3(0.62, 0.17, 0.22);
    float3 coral = float3(0.94, 0.36, 0.26);
    float3 amber = float3(0.97, 0.57, 0.27);
    float3 gold  = float3(1.00, 0.76, 0.40);
    if (v < 0.30) return mix(plum, rose, v / 0.30);
    if (v < 0.58) return mix(rose, coral, (v - 0.30) / 0.28);
    if (v < 0.82) return mix(coral, amber, (v - 0.58) / 0.24);
    return mix(amber, gold, (v - 0.82) / 0.18);
}

fragment float4 glowFragment(GlowVertex in [[stage_in]],
                             constant GlowParams& g [[buffer(0)]],
                             texture2d<float> name [[texture(0)]],
                             sampler s [[sampler(0)]]) {
    float time = g.view.w;
    float2 p = in.position.xy / g.view.z;
    float2 size = g.view.xy;
    float3 col = g.canvas.rgb;

    // The glow: five soft pools of pure coloured light — gold, peach, coral, rose, and a violet
    // for depth — drifting slowly about the name and adding as light does, like stage lights on a
    // dark set. No noise, no texture: clean light only. As it gathers, every pool travels to the
    // full stop and draws in.
    float gather = g.light.y;
    float g7 = pow(gather, 0.8);
    // The light sits a little below the name — dawn behind a horizon — so the name reads against
    // it rather than washing out in its brightest part.
    float2 home = float2(size.x * 0.5, g.text.y + g.text.w * 0.5 + 34.0);
    float3 light = float3(0.0);
    const float3 hue[5] = { float3(1.00, 0.74, 0.38), float3(1.00, 0.50, 0.28), float3(0.93, 0.30, 0.26),
                            float3(0.84, 0.24, 0.46), float3(0.42, 0.22, 0.62) };
    const float2 at[5] = { float2(-110, 6), float2(20, 30), float2(132, 12), float2(-24, 96), float2(-40, -120) };
    const float2 span[5] = { float2(175, 105), float2(210, 120), float2(175, 110), float2(230, 120), float2(270, 150) };
    const float strength[5] = { 0.50, 0.52, 0.50, 0.40, 0.32 };
    const float3 orbit[5] = { float3(26, 12, 0.9), float3(-30, 10, 1.1), float3(22, -14, 0.8),
                              float3(-18, 16, 1.3), float3(34, 10, 0.7) };
    for (int i = 0; i < 5; i++) {
        float ph = float(i) * 1.7;
        float2 drift = float2(orbit[i].x * sin(time * orbit[i].z + ph), orbit[i].y * cos(time * orbit[i].z * 0.8 + ph));
        float2 from = home + at[i] + drift;
        // Gathering, each pool curls in toward the full stop rather than sliding straight at it.
        float2 toStop = g.stop.xy - from;
        float2 curl = float2(-toStop.y, toStop.x) * 0.18 * sin(g7 * 3.14159) * (i % 2 == 0 ? 1.0 : -1.0);
        float2 c = mix(from, g.stop.xy, g7) + curl;
        float2 r = mix(span[i], float2(g.stop.z * 6.0), g7) * (1.0 + 0.06 * g.light.z);
        float2 e = (p - c) / r;
        // The cool pools (rose, violet) let go first as it gathers — only the warm light travels
        // into the full stop; crossing under the name together they mixed to an olive smudge.
        float keep = i >= 3 ? (1.0 - smoothstep(0.0, 0.45, gather)) : 1.0;
        // And what travels warms to the full stop's own coral: dim gold on the dark reads olive.
        float3 tone = mix(hue[i], g.coral.rgb, smoothstep(0.05, 0.55, gather));
        light += tone * strength[i] * keep * exp(-dot(e, e) * 1.5);
    }
    light *= g.light.x;
    // A soft shoulder, so the brightest overlap reads as light, not a clipped patch.
    col += light / (1.0 + light * 0.55) * 0.95;

    // The name: soft and warm where the light has not settled on it yet, clearing to crisp white
    // behind a gentle front that travels left to right.
    float2 uv = (p - g.text.xy) / g.text.zw;
    float presence = g.name.y;
    float settled = smoothstep(g.name.x + 46.0, g.name.x - 46.0, p.x);
    float cover = name.sample(s, uv, level((1.0 - settled) * 4.2)).a;
    float bloom = name.sample(s, uv, level(5.2)).a;
    float3 ink = mix(float3(1.0, 0.84, 0.70), float3(0.975), settled);
    ink = mix(ink, float3(0.975), 1.0 - g.name.z);
    // A breath of shade under the letters (their own blurred shape), so white type holds on light.
    col *= 1.0 - 0.22 * bloom * presence;
    col += bloom * float3(1.0, 0.60, 0.40) * 0.10 * g.name.z * presence;
    col = mix(col, ink, cover * presence * mix(0.55, 1.0, settled));

    // The full stop, holding the light: a coral bead, and the glow it keeps.
    float2 sd = (p - g.stop.xy) / g.stop.z;
    float sr = length(sd);
    float stopLight = g.name.w;
    col += g.coral.rgb * stopLight * 0.55 * exp(-pow(max(sr - 0.6, 0.0) / 2.6, 2.0));
    float bead = smoothstep(1.0, 1.0 - 1.4 / (g.stop.z * g.view.z), sr);
    col = mix(col, g.coral.rgb + float3(0.06, 0.04, 0.03) * stopLight, bead * saturate(stopLight * 1.4));

    // Film grain, a hair under one step, so the light never bands.
    col += (glowHash(in.position.xy + fract(time * 13.0)) - 0.5) * (1.4 / 255.0);
    return float4(col, 1.0);
}
