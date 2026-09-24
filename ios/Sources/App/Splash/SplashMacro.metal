#include <metal_stdlib>
using namespace metal;

// MACRO — the film opens INSIDE the full stop. The first frame is a macro shot of the coral bead —
// the whole screen a glossy coral surface under a studio light — and the camera pulls back, fast,
// until the bead is a full stop at the end of a name that rushes in from the edge of the frame.
// One object, one camera move; the brand's colour, full bleed, at the start.
//
// The world is the finished lockup (the name's box and the full stop, in points); the camera is a
// zoom about the full stop, and its screen position. Fast zooms are shot with a shutter: each
// pixel averages the world at a few zooms across the frame's interval — real radial motion blur.

struct MacroParams {
    float4 view;     // width, height (points), scale (px/pt), film time
    float4 text;     // the name's box in the world: x, y, w, h
    float4 stop;     // the full stop: centre x, y (world), radius, _
    float4 camera;   // where the stop sits on screen x, y; log zoom; log-zoom travelled per frame
    float4 look;     // fade-in 0…1, halo 0…1, glint sweep 0…1, light drift 0…1
    float4 canvas;   // sRGB
    float4 coral;    // sRGB
};

struct MacroVertex { float4 position [[position]]; };

vertex MacroVertex macroVertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    MacroVertex out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

static float macroHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

/// The world at point `w` (points), seen at `zoom`.
static float3 world(float2 w, float zoom, constant MacroParams& g, texture2d<float> name, sampler s) {
    float R = g.stop.z;
    float2 d = (w - g.stop.xy) / R;
    float r2 = dot(d, d);

    // The page — and, faintly, the coral light the bead gives off, so it floats in the dark rather
    // than sitting on it.
    float3 col = g.canvas.rgb;
    col += g.coral.rgb * g.look.y * 0.075 * exp(-max(r2 - 1.0, 0.0) / 6.0);

    // The name.
    float cover = name.sample(s, (w - g.text.xy) / g.text.zw).a;
    col = mix(col, float3(0.975), cover);

    if (r2 < 1.0) {
        // The bead: lacquered coral — deep and saturated where it turns from the light, warming to
        // a lit coral, light passing a little way into it at the terminator.
        float3 n = float3(d, sqrt(1.0 - r2));
        float drift = g.look.w;
        float3 L = normalize(float3(-0.52 + 0.20 * drift, -0.60 + 0.10 * drift, 0.60));
        float3 V = float3(0.0, 0.0, 1.0);
        float ndl = dot(n, L);
        float wrap = 0.45;
        float diff = saturate((ndl + wrap) / (1.0 + wrap));
        float3 shadow = float3(0.40, 0.045, 0.045);
        float3 mid = g.coral.rgb;
        float3 light = float3(1.0, 0.56, 0.42);
        float3 base = diff < 0.55 ? mix(shadow, mid, smoothstep(0.0, 0.55, diff))
                                  : mix(mid, light, smoothstep(0.55, 1.0, diff));
        base += float3(0.20, 0.03, 0.02) * pow(1.0 - abs(ndl), 5.0) * 0.8;
        // Studio light, reflected: a long feathered strip at the upper left (the key), a thinner
        // one beside it (the kicker), a dim fill at the lower right — the reflections of a product
        // macro, curving with the surface, drifting as the light does. No hard-edged window.
        float3 Rv = reflect(-V, n);
        float2 kc = Rv.xy - float2(-0.36 + 0.20 * drift, -0.44 + 0.06 * drift);
        float2 ka = float2(kc.x * 0.84 + kc.y * 0.54, -kc.x * 0.54 + kc.y * 0.84);
        float key = exp(-pow(ka.x / 0.13, 2.0)) * smoothstep(0.62, 0.12, abs(ka.y)) * 0.58;
        float2 kk = ka - float2(0.24, 0.02);
        float kicker = exp(-pow(kk.x / 0.035, 2.0)) * smoothstep(0.46, 0.06, abs(kk.y)) * 0.34;
        float2 fb = (Rv.xy - float2(0.52, 0.58)) / float2(0.30, 0.24);
        float fill = exp(-dot(fb, fb) * 1.6) * 0.10;
        float3 H = normalize(L + V);
        float spec = pow(saturate(dot(n, H)), 70.0) * 0.22;
        float3 reflections = float3(1.0, 0.96, 0.92) * (key + kicker + spec) + float3(1.0, 0.8, 0.7) * fill;
        // A warm back-light along the rim.
        float fres = pow(1.0 - n.z, 3.2);
        float3 rim = float3(1.0, 0.70, 0.52) * fres * 0.30;
        // One glint as it lands.
        float gs = g.look.z;
        float glint = 0.0;
        if (gs > 0.0 && gs < 1.0) {
            float band = dot(d, normalize(float2(0.8, -0.6))) - mix(-1.4, 1.4, gs);
            glint = exp(-band * band * 30.0) * 0.6 * sin(gs * 3.14159);
        }
        float3 bead = base + reflections + rim + glint;
        // Anti-aliased at every zoom: one and a half pixels, in the bead's own units.
        float px = 1.5 / (g.view.z * zoom * R);
        float edge = smoothstep(1.0, 1.0 - px, sqrt(r2));
        col = mix(col, bead, edge);
    }
    return col;
}

fragment float4 macroFragment(MacroVertex in [[stage_in]],
                              constant MacroParams& g [[buffer(0)]],
                              texture2d<float> name [[texture(0)]],
                              sampler s [[sampler(0)]]) {
    float2 p = in.position.xy / g.view.z;
    float logZoom = g.camera.z;
    float travel = g.camera.w;
    // The shutter: exposures across the frame's interval when the camera is moving fast, each
    // pixel's offset jittered so they blend into one streak instead of stepping into copies.
    int shots = travel > 0.004 ? 14 : 1;
    float jitter = macroHash(in.position.xy * 0.73 + fract(g.view.w * 7.0)) - 0.5;
    float3 acc = float3(0.0);
    for (int i = 0; i < shots; i++) {
        float f = shots > 1 ? ((float(i) + 0.5 + jitter) / float(shots) - 0.5) : 0.0;
        float zoom = exp(logZoom + travel * f);
        float2 w = g.stop.xy + (p - g.camera.xy) / zoom;
        acc += world(w, zoom, g, name, s);
    }
    float3 col = acc / float(shots);
    // Lights up from the dark.
    col = mix(g.canvas.rgb, col, g.look.x);
    col += (macroHash(in.position.xy + g.view.w) - 0.5) / 255.0;
    return float4(col, 1.0);
}
