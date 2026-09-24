#include <metal_stdlib>
using namespace metal;

// SILK — ribbons of light, gathered into the name.
//
// Modelled on what the premium streamers shipped in 2025: Apple TV's intro (macro shots of light
// travelling through curved glass — silky, spectral bands on black) and the flat, crisp logos
// every one of them resolves to. The screen opens on macro ribbons of light in the icon's warm
// spectrum — gold, amber, coral, rose — each with a bright hairline at its edges and a trace of
// cool dispersion beyond them, flowing slowly across the dark. Then the light gathers onto the
// line of the name and into it — the letters carry the silk for a moment — and settles into the
// app's own flat wordmark: the ribbon, "Previously", the coral full stop. Flat at rest; nothing
// glossy, nothing solid, no 3D.

struct SilkParams {
    float4 view;     // width, height (points), scale (px/pt), film time
    float4 name;     // the name's box: x, y, w, h (points)
    float4 mark;     // the ribbon's box: x, y, w, h (points)
    float4 flow;     // presence 0…1, gather 0…1 (bands converge on the name's line), confine 0…1, settle 0…1
    float4 canvas;   // sRGB
};

struct SilkVertex { float4 position [[position]]; };

vertex SilkVertex silkVertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    SilkVertex out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

static float silkHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

/// A sunset spectrum across a band, 0…1 — the icon's gold and coral at its heart, carried on
/// through magenta to violet at the far edge, the way light splits through glass. Saturated all
/// the way across: a dim orange is brown, and brown is what the first cut was.
static float3 spectrum(float v) {
    float3 gold = float3(1.00, 0.84, 0.32), orange = float3(1.00, 0.52, 0.14);
    float3 coral = float3(1.00, 0.27, 0.24), magenta = float3(0.94, 0.20, 0.62), violet = float3(0.52, 0.26, 1.00);
    v = saturate(v);
    if (v < 0.25) return mix(gold, orange, v / 0.25);
    if (v < 0.50) return mix(orange, coral, (v - 0.25) / 0.25);
    if (v < 0.75) return mix(coral, magenta, (v - 0.50) / 0.25);
    return mix(magenta, violet, (v - 0.75) / 0.25);
}

/// The ribbon mark, flat: the icon's bookmark in units of its width (y 0…aspect), negative inside.
static float silkRibbon(float2 u, float aspect) {
    const float notch = 0.40;
    float2 q = abs(u - float2(0.5, aspect * 0.5)) - float2(0.5, aspect * 0.5) + 0.06;
    float box = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.06;
    // The notch: a V cut up into the foot.
    float2 a = float2(0.5, aspect - notch);
    float left = dot(u - a, normalize(float2(notch, 0.5)));
    float right = dot(u - a, normalize(float2(-notch, 0.5)));
    float cut = min(left, right);                 // positive below both edges of the V
    return max(box, cut);
}

fragment float4 silkFragment(SilkVertex in [[stage_in]],
                             constant SilkParams& g [[buffer(0)]],
                             texture2d<float> name [[texture(0)]],
                             sampler s [[sampler(0)]]) {
    float time = g.view.w;
    float2 size = g.view.xy;
    float2 p = in.position.xy / g.view.z;
    float presence = g.flow.x, gather = g.flow.y, confine = g.flow.z, settle = g.flow.w;
    float3 col = g.canvas.rgb;

    // The line the light gathers onto: the name's.
    float line = g.name.y + g.name.w * 0.52;

    // The bands: three broad sweeps of light, macro — each a smooth spectral gradient across its
    // width (the icon's gold, amber, coral, rose), one edge catching the light as a crisp bright
    // line, the other falling away softly; luminous, adding toward white where they cross. A few
    // large gentle curves, never a repeating wave. Gathering pulls each onto the name's line and
    // narrows it to the letters' height.
    float3 light = float3(0.0);
    const float3 shape[3] = { float3(0.24, 0.30, 1.0), float3(0.62, -0.22, -0.8), float3(0.86, 0.18, 0.6) };
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float x = p.x / size.x;                                   // 0…1 across
        float drift = time * (0.10 + 0.03 * fi);
        // One gentle arc across the screen, tilted, drifting slowly.
        float centre = size.y * (shape[i].x + shape[i].y * (x - 0.5) + 0.07 * shape[i].z * sin(3.14159 * x + drift * 3.0 + fi));
        centre = mix(centre, line + (fi - 1.0) * 4.0, gather);
        float halfWidth = mix(78.0 + 26.0 * fi + 14.0 * sin(x * 3.0 + drift * 2.0 + fi), g.name.w * 0.48, gather);
        float d = (p.y - centre) / halfWidth;                     // −1 … 1 across the band
        if (abs(d) < 1.4) {
            float across = saturate((d + 1.0) * 0.5);
            float3 c = spectrum(across * 0.9 + 0.05 + 0.06 * sin(drift * 2.0 + fi));
            // Lit along the leading edge, falling away across the band.
            float body = smoothstep(1.0, 0.62, abs(d)) * mix(1.05, 0.55, across);
            float lit = exp(-pow((d + 0.975) / 0.022, 2.0)) * 1.1;  // a crisp hairline at the lit edge
            float soft = smoothstep(1.35, 0.95, abs(d)) * (1.0 - smoothstep(0.95, 1.0, abs(d))) * 0.25;
            float3 band = c * (body + soft) + mix(c, float3(1.0, 0.96, 0.9), 0.6) * lit;
            // A trace of cool dispersion just beyond the lit edge.
            band += float3(0.35, 0.55, 1.0) * exp(-pow((d + 1.08) / 0.05, 2.0)) * 0.22;
            light += band * (0.85 - 0.12 * fi);
        }
    }
    light *= presence;

    // The mark and the name, as masks: the ribbon's shape and the letters'.
    float2 mu = (p - g.mark.xy) / g.mark.z;
    float aspect = g.mark.w / g.mark.z;
    float msd = silkRibbon(mu, aspect) * g.mark.z;          // points
    float markCover = smoothstep(0.6, -0.6, msd);
    float2 nuv = (p - g.name.xy) / g.name.zw;
    float4 ink = name.sample(s, nuv);                        // premultiplied: white letters, coral stop
    float cover = max(ink.a, markCover);

    // Confining: the light outside the lockup lets go, the light inside stays — the letters and
    // the ribbon become windows onto the silk.
    float3 lit = light / (1.0 + light * 0.32);
    col += lit * mix(1.0, cover, confine);

    // Settling: the lockup becomes the app's flat wordmark — the ribbon in the icon's ramp, the
    // letters white, the full stop coral.
    float3 ramp = mix(float3(1.00, 0.73, 0.28), float3(0.87, 0.29, 0.24), saturate((mu.y / aspect) * 0.8 + mu.x * 0.2));
    float3 flatMark = ramp;
    float3 flatName = ink.a > 0.0 ? ink.rgb / max(ink.a, 1e-4) : float3(0.0);
    col = mix(col, flatMark, markCover * settle);
    col = mix(col, flatName, ink.a * settle);

    col += (silkHash(in.position.xy + fract(time * 9.0)) - 0.5) * (1.2 / 255.0);
    return float4(col, 1.0);
}
