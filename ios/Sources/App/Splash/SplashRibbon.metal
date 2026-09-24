#include <metal_stdlib>
using namespace metal;

// RIBBON — one ribbon of silk light that becomes the mark (`SplashRibbonScript`).
//
// The film opens close on a single broad ribbon of light, turning slowly in the dark: the sunset
// spectrum across its width, one edge catching the light as a bright hairline, a fold where it
// turns over. The camera eases back as the ribbon calms — the fold runs down it and off its tails,
// it straightens, stands upright — and it is the mark: the icon's ribbon, notch and all, in the
// icon's gold-to-coral. The name is written in beside it. One object, one move, nothing random.
//
// Two passes: the page (the canvas, the light the ribbon gives off, the name) as one full-screen
// triangle, then the ribbon itself as a triangle strip the script lays out every frame, blended
// premultiplied over it.

struct RibbonParams {
    float4 view;     // width, height (points), scale (px/pt), film time
    float4 glow;     // the light it gives off: centre x, y (points), radius (points), strength
    float4 name;     // the name's box: x, y, w, h (points)
    float4 look;     // presence 0…1, resolve 0…1 (silk → mark), the name 0…1, sheen s
    float4 shape;    // the ribbon's length (points at rest), _, far-edge softness 0…1, camera zoom
    float4 canvas;   // sRGB
    float4 markBox;  // the gate's lit mark, as a picture: x, y, w, h (points)
    float4 bloomBox; // the gate's light behind it: x, y, w, h
    float4 lockup;   // the lit mark 0…1 (the silk hands over to it), the light 0…1, _, _
};

// MARK: - The page

struct PageVertex { float4 position [[position]]; };

vertex PageVertex ribbonPageVertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    PageVertex out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

static float ribbonHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

fragment float4 ribbonPageFragment(PageVertex in [[stage_in]],
                                   constant RibbonParams& g [[buffer(0)]],
                                   texture2d<float> name [[texture(0)]],
                                   texture2d<float> mark [[texture(1)]],
                                   texture2d<float> bloom [[texture(2)]],
                                   sampler s [[sampler(0)]]) {
    float2 p = in.position.xy / g.view.z;
    float3 col = g.canvas.rgb;

    // The light the ribbon gives off: a warm pool on the dark about it.
    float2 e = (p - g.glow.xy) / g.glow.z;
    col += float3(0.95, 0.36, 0.34) * g.glow.w * exp(-dot(e, e) * 1.6) * 0.10;

    // The gate's own light (a premultiplied picture of the gate's view) comes up as the ribbon
    // lands.
    float4 lit = bloom.sample(s, (p - g.bloomBox.xy) / g.bloomBox.zw) * g.lockup.y;
    col = col * (1.0 - lit.a) + lit.rgb;

    // The name, surfacing beneath the mark: warm as it arrives, settling to its own white (the
    // full stop to its coral).
    float4 ink = name.sample(s, (p - g.name.xy) / g.name.zw);
    float shown = g.look.z;
    float3 own = ink.a > 0.0 ? ink.rgb / ink.a : float3(0.0);
    own = mix(own * float3(1.0, 0.80, 0.64), own, shown);
    col = mix(col, own, ink.a * shown);

    col += (ribbonHash(in.position.xy + fract(g.view.w * 9.0)) - 0.5) * (1.2 / 255.0);
    return float4(col, 1.0);
}

// MARK: - The ribbon

struct RibbonOut {
    float4 position [[position]];
    float2 material;   // s along (0 head → 1 tails), v across (−1 lit edge → +1)
    float4 turn;       // the satin's pitch, the spine's lean, the width on screen, _
};

vertex RibbonOut ribbonMeshVertex(uint vid [[vertex_id]],
                                  const device float4* strip [[buffer(1)]],
                                  constant RibbonParams& g [[buffer(0)]]) {
    float4 place = strip[vid * 2];
    RibbonOut out;
    float2 ndc = place.xy / g.view.xy * 2.0 - 1.0;
    out.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
    out.material = place.zw;
    out.turn = strip[vid * 2 + 1];
    return out;
}

/// The mark's outline (`RibbonShape`) in the ribbon's own units — along 0 (head) … L (tails),
/// across −W/2 … W/2 — negative inside: a strip with rounded head corners and the notch cut up
/// into its tails.
static float ribbonOutline(float along, float across, float L, float W) {
    float hw = W * 0.5;
    float rc = 0.06 * W;
    float2 q = float2(abs(across) - hw + rc, rc - along);
    float head = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rc;
    float nd = 0.40 * W;
    float notch = ((along - (L - nd)) * hw - abs(across) * nd) / sqrt(hw * hw + nd * nd);
    return max(head, notch);
}

/// The sunset spectrum across the silk: gold, orange, coral, magenta, violet — saturated all the
/// way across (a dim orange is brown).
static float3 silkSpectrum(float v) {
    float3 gold = float3(1.00, 0.84, 0.32), orange = float3(1.00, 0.52, 0.14);
    float3 coral = float3(1.00, 0.27, 0.24), magenta = float3(0.94, 0.20, 0.62), violet = float3(0.52, 0.26, 1.00);
    v = saturate(v);
    if (v < 0.25) return mix(gold, orange, v / 0.25);
    if (v < 0.50) return mix(orange, coral, (v - 0.25) / 0.25);
    if (v < 0.75) return mix(coral, magenta, (v - 0.50) / 0.25);
    return mix(magenta, violet, (v - 0.75) / 0.25);
}

/// The icon's ramp and its two quiet overlays (`RibbonFill`), at a point of the resting ribbon.
static float3 markInk(float along, float across, float L, float W) {
    float x = across + W * 0.5, y = along;
    float d = saturate((x * W + y * L) / (W * W + L * L));
    float3 top = float3(1.0, 0.733, 0.282), mid = float3(0.949, 0.549, 0.235), foot = float3(0.871, 0.290, 0.235);
    float3 c = d < 0.5 ? mix(top, mid, d / 0.5) : mix(mid, foot, (d - 0.5) / 0.5);
    float u = saturate(y / L), w = saturate(x / W);
    // Lit at the head, shaded at the foot.
    c = u < 0.35 ? mix(c, float3(1.0), 0.09 * (1.0 - u / 0.35)) : mix(c, float3(0.0), 0.22 * (u - 0.35) / 0.65);
    // A cylinder's light across the width.
    c = w < 0.35 ? mix(mix(c, float3(0.0), 0.08), mix(c, float3(1.0), 0.09), w / 0.35)
                 : mix(mix(c, float3(1.0), 0.09), mix(c, float3(0.0), 0.18), (w - 0.35) / 0.65);
    return c;
}

fragment float4 ribbonMeshFragment(RibbonOut in [[stage_in]],
                                   constant RibbonParams& g [[buffer(0)]]) {
    float time = g.view.w;
    float presence = g.look.x, resolve = g.look.y;
    float L = g.shape.x * g.shape.w, soft = g.shape.z;
    float W = in.turn.z;
    float s = in.material.x, v = in.material.y;
    float along = s * L, across = v * W * 0.5;

    // Coverage: the outline, anti-aliased by its own screen-space rate of change.
    float d = ribbonOutline(along, across, L, W);
    float aa = saturate(0.5 - d / max(fwidth(d), 1e-4));
    // While it is light, the trailing end fades like the end of a stroke of light, and the far
    // edge falls away softly; the lit edge and the notched tails stay crisp.
    float far = saturate((v + 1.0) * 0.5);
    float nearTails = smoothstep(L - 1.6 * W, L - 0.4 * W, along);
    float fall = 1.0 - soft * (1.0 - nearTails) * smoothstep(0.62, 1.0, far) * 0.85;
    float trailing = mix(1.0, smoothstep(0.0, 0.55 * L, along), soft);
    float cover = aa * fall * trailing;

    // The light beyond the lit edge: a trace of cool dispersion, additive.
    float fringe = exp(-pow((v + 1.09) / 0.05, 2.0)) * 0.20 * (1.0 - resolve) * trailing
        * step(0.0, along) * step(along, L - 0.4 * W);

    if (cover <= 0.0 && fringe <= 0.001) discard_fragment();

    // The silk: satin rippling gently toward and away from us, the ripples travelling down it.
    // Where a ripple turns to the light it is bright, where it turns away it is deep: bands of
    // light flowing along the ribbon. The spectrum across its width, drifting slowly along it,
    // flat across (light falling away across it read as a tube); one edge catching the light.
    float pitch = in.turn.x;
    float2 tangent = float2(sin(in.turn.y), cos(in.turn.y));
    float3 n = float3(sin(pitch) * tangent, cos(pitch));
    float3 light = normalize(float3(-0.50, -0.72, 0.48));
    float3 halfway = normalize(light + float3(0.0, 0.0, 1.0));
    float diffuse = saturate(dot(n, light));
    float spec = pow(saturate(dot(n, halfway)), 24.0);
    float flow = 0.07 * sin(6.28318 * (s * 0.7 - time * 0.16));
    float3 hue = silkSpectrum(far * 0.9 + 0.05 + flow);
    // Where the satin turns from the light it deepens toward rose and violet, never toward brown.
    hue = mix(hue, float3(0.78, 0.18, 0.52), (1.0 - diffuse) * 0.30);
    float body = mix(1.0, 0.84, far) * (0.44 + 0.84 * diffuse);
    float sheen = exp(-pow((s - g.look.w) / 0.09, 2.0)) * 0.30;
    float hair = exp(-pow((v + 0.972) / 0.024, 2.0)) * (1.0 - resolve) * (0.55 + 0.6 * diffuse);
    float3 silk = hue * body
        + mix(hue, float3(1.0, 0.93, 0.84), 0.55) * (sheen + spec * 0.42)
        + mix(hue, float3(1.0, 0.96, 0.9), 0.6) * hair;
    silk = silk / (1.0 + 0.18 * silk);

    // The mark: the icon's ramp and overlays, flat — with the landing's last catch of light.
    float3 mark = markInk(along, across, L, W) + float3(1.0, 0.9, 0.75) * sheen * 0.5;
    float3 col = mix(silk, mark, resolve);

    float a = cover * presence;
    float3 fringeLight = float3(0.35, 0.55, 1.0) * fringe * presence;
    return float4(col * a + fringeLight, a);
}

// MARK: - The handover

/// The gate's own lit mark, laid OVER the ribbon, which stays whole beneath it: a true crossfade.
/// Fading the ribbon out while the picture faded in under it let the canvas through both — a
/// quarter of it at the midpoint — and the mark dimmed to brown on its way to gold.
fragment float4 ribbonHandoverFragment(PageVertex in [[stage_in]],
                                       constant RibbonParams& g [[buffer(0)]],
                                       texture2d<float> name [[texture(0)]],
                                       texture2d<float> mark [[texture(1)]],
                                       sampler s [[sampler(0)]]) {
    float2 p = in.position.xy / g.view.z;
    float4 m = mark.sample(s, (p - g.markBox.xy) / g.markBox.zw) * g.lockup.x;
    if (m.a <= 0.0) discard_fragment();
    return m;
}
