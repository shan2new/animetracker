#include <metal_stdlib>
using namespace metal;

// The launch's glass bead, as optics. One full-screen pass: the dark page, the name the bead has
// read, and the bead itself — a dome of clear glass that magnifies at its centre and bends hard
// toward its rim (with a trace of dispersion there), lit from the upper left (fresnel rim, two
// highlights, the light it focuses glowing at its lower right) — until coral ink blooms inside it
// and it is the full stop. Every input is a uniform the CPU computes from the film time
// (`SplashGlassScript`), so a frame is a pure function of that time.

struct GlassParams {
    float4 view;      // width, height (points), scale (px/pt), film time
    float4 text;      // the name's box: x, y, w, h (points)
    float4 bead;      // centre x, y, radius (points), magnification at the centre
    float4 state;     // ink 0…1, presence 0…1, reveal front x (points), glow 0…1
    float4 look;      // develop 0…1, warmth 0…1, sparkle 0…1, _
    float4 canvas;    // the page (sRGB)
    float4 coral;     // the full stop (sRGB)
};

struct GlassVertex { float4 position [[position]]; };

vertex GlassVertex glassVertex(uint vid [[vertex_id]]) {
    // One triangle that covers the screen.
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    GlassVertex out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash21(i), b = hash21(i + float2(1, 0)), c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// The name's coverage at a point (points), 0 outside its box.
static float nameAt(texture2d<float> name, sampler s, float2 p, constant GlassParams& g) {
    float2 uv = (p - g.text.xy) / g.text.zw;
    return name.sample(s, uv).a;
}

/// The page: the canvas, and a breath of warm light behind the name.
static float3 page(float2 p, constant GlassParams& g) {
    float3 c = g.canvas.rgb;
    float2 centre = float2(g.view.x * 0.5, g.text.y + g.text.w * 0.55);
    float2 q = (p - centre) / float2(g.view.x * 0.80, 210.0);
    c += g.look.y * exp(-dot(q, q) * 2.4) * float3(0.066, 0.034, 0.016);
    return c;
}

fragment float4 glassFragment(GlassVertex in [[stage_in]],
                              constant GlassParams& g [[buffer(0)]],
                              texture2d<float> name [[texture(0)]],
                              sampler s [[sampler(0)]]) {
    float scale = g.view.z;
    float time = g.view.w;
    float2 p = in.position.xy / scale;
    float3 ink0 = float3(0.975);

    // The page, and the letters the bead has already passed — the newest still warm, developing.
    float3 col = page(p, g);
    float cover = nameAt(name, s, p, g);
    float front = g.state.z;
    float revealed = smoothstep(front + 5.0, front - 5.0, p.x);
    float fresh = g.look.x * exp(-max(front - p.x, 0.0) / 28.0);
    float3 letter = ink0 + fresh * float3(0.20, 0.10, 0.02);
    col = mix(col, letter, cover * revealed);

    float2 c = g.bead.xy;
    float R = g.bead.z;
    float2 d = (p - c) / R;
    float r = length(d);

    // The full stop's own light, once it is coral.
    float glow = g.state.w * g.state.x;
    col += glow * g.coral.rgb * 0.30 * exp(-pow(max(r - 0.25, 0.0) / 1.9, 2.0));

    // Light the bead focuses onto the page beneath it: a soft warm spot, lower right.
    float2 cz = (p - (c + float2(0.35, 0.95) * R)) / (R * float2(1.1, 0.55));
    col += g.state.y * (1.0 - g.state.x) * exp(-dot(cz, cz) * 1.6) * float3(0.050, 0.034, 0.020);

    if (r < 1.0 && g.state.y > 0.0) {
        // Refraction: magnified at the centre, bending hard toward the rim, with a trace of
        // dispersion there (red pulled a hair wider than blue).
        float k = (1.0 / g.bead.w) * (1.0 + 2.2 * pow(r, 4.0));
        float spread = 0.020 * r * r;
        float2 qr = c + (p - c) * k * (1.0 + spread);
        float2 qg = c + (p - c) * k;
        float2 qb = c + (p - c) * k * (1.0 - spread);
        // Through the glass the whole name is there, read or not.
        float3 seen = float3(mix(page(qr, g).r, ink0.r, nameAt(name, s, qr, g)),
                             mix(page(qg, g).g, ink0.g, nameAt(name, s, qg, g)),
                             mix(page(qb, g).b, ink0.b, nameAt(name, s, qb, g)));

        // The glass: a little darker toward the rim, then the fresnel light there — strongest on
        // the side facing the light, a quieter return on the far side.
        float2 lightDir = normalize(float2(-0.62, -0.78));
        float2 dn = r > 1e-4 ? d / r : float2(0.0);
        float facing = saturate(dot(dn, lightDir));
        float away = saturate(-dot(dn, lightDir));
        float fres = pow(r, 4.5);
        float3 glass = seen * (0.95 - 0.22 * fres);
        glass += fres * (0.14 + 0.62 * facing + 0.20 * away);
        // A crisp rim line where the dome meets the page.
        glass += smoothstep(0.88, 0.99, r) * (0.06 + 0.40 * facing);
        // Highlights: a soft window of light, and a hot point inside it.
        float2 hs = d - float2(-0.34, -0.42);
        float2 hr = float2(hs.x * 0.80 + hs.y * 0.60, -hs.x * 0.60 + hs.y * 0.80) / float2(0.34, 0.16);
        float spec = exp(-dot(hr, hr) * 2.0) * 0.55;
        float2 hot = (d - float2(-0.30, -0.40)) / 0.075;
        spec += exp(-dot(hot, hot) * 2.2) * 0.85;
        // The sparkle: one bright sweep across the dome at the very end.
        float sw = g.look.z;
        if (sw > 0.0 && sw < 1.0) {
            float band = dot(d, normalize(float2(0.8, -0.6))) - mix(-1.3, 1.3, sw);
            spec += exp(-band * band * 40.0) * 0.55 * sin(sw * 3.14159);
        }
        glass += spec;
        // The light the dome focuses, glowing at its lower right from inside.
        float2 fz = (d - float2(0.34, 0.46)) / float2(0.36, 0.26);
        glass += exp(-dot(fz, fz) * 2.0) * float3(0.22, 0.14, 0.07);

        // Coral ink blooming from the centre, its front stirred, until the bead is the full stop.
        float stir = noise(d * 3.0 + float2(time * 1.6, -time * 1.2)) - 0.5;
        float reach = g.state.x * 1.35;
        float inked = smoothstep(reach, reach - 0.32, r + stir * 0.26 * (1.0 - g.state.x));
        float3 coral = g.coral.rgb * (1.04 - 0.26 * fres);
        coral += fres * facing * 0.20;
        coral += spec * 0.55;
        float3 bead = mix(glass, coral, inked);

        // Anti-aliased edge, and the bead's presence.
        float edge = smoothstep(1.0, 1.0 - 1.6 / (R * scale), r);
        col = mix(col, bead, edge * g.state.y);
    }

    // Grain below one step, so the dark never bands.
    col += (hash21(in.position.xy + time) - 0.5) / 255.0;
    return float4(col, 1.0);
}
