#include <metal_stdlib>
using namespace metal;

// ALIGN — the mark as five layers of coloured glass (gold, amber, coral, rose, violet) at different
// depths. Seen from an angle they fan apart into overlapping planes of light; one slow camera move
// brings the view head-on and they slide into register, their colours merging into the icon's own;
// then the mark is the gate's lit mark (`LaunchLockup`), its light comes up and the name surfaces.
// Nothing bends and nothing has a head or a tail: the only motion is the camera's.
//
// One full-screen pass: the canvas, the gate's light (a picture), the five layers, the registered
// mark, the gate's lit mark (a picture) and the name (a picture).

struct AlignParams {
    float4 view;      // width, height (points), scale (px/pt), film time
    float4 mark;      // the resting mark: x, y, w, h (points)
    float4 name;      // the name's box (points, already risen)
    float4 markPic;   // the gate's lit mark, as a picture: x, y, w, h
    float4 bloomBox;  // the gate's light, as a picture: x, y, w, h
    float4 landing;   // the lit mark 0…1, the light 0…1, the name 0…1, leaving 0…1
    float4 canvas;    // sRGB
    float4 cam;       // yaw, pitch, roll (radians), zoom
    float4 at;        // where the stack's centre is drawn: x, y (points); layer spacing (points); fuse 0…1
    float4 look;      // presence, sheen, register 0…1, _
};

struct AlignVertex { float4 position [[position]]; };

vertex AlignVertex alignVertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    AlignVertex out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

static float alignHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

/// The mark's outline (`RibbonShape`), negative inside: along 0 (head) … L (tails), across −W/2 … W/2.
static float alignOutline(float along, float across, float L, float W) {
    float hw = W * 0.5;
    float rc = 0.06 * W;
    float2 q = float2(abs(across) - hw + rc, rc - along);
    float head = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rc;
    float nd = 0.40 * W;
    float notch = ((along - (L - nd)) * hw - abs(across) * nd) / sqrt(hw * hw + nd * nd);
    return max(head, notch);
}

/// The lit mark's ink (`RibbonFill` with `material` 1): the icon's ramp laid out in the shape's
/// UNIT square, as SwiftUI lays out a topLeading → bottomTrailing gradient, under its two overlays
/// with the lit shade (0.45 of the flat mark's).
static float3 alignInk(float along, float across, float L, float W) {
    float x = across + W * 0.5, y = along;
    float d = saturate((x / W + y / L) * 0.5);
    float3 top = float3(1.0, 0.733, 0.282), mid = float3(0.949, 0.549, 0.235), foot = float3(0.871, 0.290, 0.235);
    float3 c = d < 0.5 ? mix(top, mid, d / 0.5) : mix(mid, foot, (d - 0.5) / 0.5);
    float u = saturate(y / L), w = saturate(x / W);
    const float shade = 0.45;
    c = u < 0.35 ? mix(c, float3(1.0), 0.09 * (1.0 - u / 0.35)) : mix(c, float3(0.0), 0.22 * shade * (u - 0.35) / 0.65);
    c = w < 0.35 ? mix(mix(c, float3(0.0), 0.08 * shade), mix(c, float3(1.0), 0.09), w / 0.35)
                 : mix(mix(c, float3(1.0), 0.09), mix(c, float3(0.0), 0.18 * shade), (w - 0.35) / 0.65);
    return c;
}

static float3 alignGel(int i) {
    if (i == 0) return float3(1.00, 0.80, 0.34);
    if (i == 1) return float3(1.00, 0.56, 0.20);
    if (i == 2) return float3(0.98, 0.33, 0.25);
    if (i == 3) return float3(0.90, 0.24, 0.52);
    return float3(0.56, 0.30, 0.96);
}

fragment float4 alignFragment(AlignVertex in [[stage_in]],
                              constant AlignParams& g [[buffer(0)]],
                              texture2d<float> name [[texture(0)]],
                              texture2d<float> mark [[texture(1)]],
                              texture2d<float> bloom [[texture(2)]],
                              sampler s [[sampler(0)]]) {
    float2 screen = in.position.xy / g.view.z;
    float t = g.view.w;
    float leaving = g.landing.w;
    // Leaving, the lockup recedes a hair about the mark's centre as it goes.
    float2 centre = g.mark.xy + g.mark.zw * 0.5;
    float2 p = centre + (screen - centre) / (1.0 - 0.03 * leaving);
    float3 col = g.canvas.rgb;

    // The gate's light, under everything.
    float4 lit = bloom.sample(s, (p - g.bloomBox.xy) / g.bloomBox.zw) * g.landing.y;
    col = col * (1.0 - lit.a) + lit.rgb;

    // The camera's rotation (world → view), rows r1, r2, r3.
    float yaw = g.cam.x, pitch = g.cam.y, roll = g.cam.z, zoom = g.cam.w;
    float cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch), cr = cos(roll), sr = sin(roll);
    float3x3 Ry = float3x3(float3(cy, 0, -sy), float3(0, 1, 0), float3(sy, 0, cy));
    float3x3 Rx = float3x3(float3(1, 0, 0), float3(0, cp, sp), float3(0, -sp, cp));
    float3x3 Rz = float3x3(float3(cr, sr, 0), float3(-sr, cr, 0), float3(0, 0, 1));
    float3x3 R = Rz * Rx * Ry;
    float3 r1 = float3(R[0][0], R[1][0], R[2][0]);
    float3 r2 = float3(R[0][1], R[1][1], R[2][1]);
    float3 r3 = float3(R[0][2], R[1][2], R[2][2]);

    // The five layers: coloured glass, each the mark's shape at its own depth. Where they overlap,
    // fanned, they add like light; as they come into register each gel's colour slides into the
    // icon's own, and the stack becomes one sheet of it.
    float2 q = (p - g.at.xy) / zoom;
    float3 light = float3(0.0), inked = float3(0.0);
    float cover = 0.0;
    float reg = g.look.z;
    float3 lightDir = normalize(float3(-0.45, -0.60, 0.66));
    float3 nView = float3(r1.z, r2.z, r3.z);
    float spec = pow(saturate(dot(normalize(nView + float3(0, 0, 1)), lightDir)), 6.0);
    for (int i = 0; i < 5; i++) {
        float z = (float(i) - 2.0) * g.at.z;
        // The point on layer i (world depth z) that projects to q: P = q.x r1 + q.y r2 + w r3.
        float w = (z - q.x * r1.z - q.y * r2.z) / r3.z;
        float2 P = q.x * r1.xy + q.y * r2.xy + w * r3.xy;
        float along = P.y + g.mark.w * 0.5, across = P.x;
        float d = alignOutline(along, across, g.mark.w, g.mark.z);
        float fill = saturate(0.5 - d / max(fwidth(d), 1e-4));
        float edge = exp(-pow(d / (1.1 * zoom * 0.5 + 0.6), 2.0));
        float rimLit = saturate(0.55 + 0.45 * (-(across / (g.mark.z * 0.5)) * 0.5 - (along / g.mark.w - 0.5) * 0.8));
        float3 hue = mix(alignGel(i), alignInk(along, across, g.mark.w, g.mark.z), reg);
        float body = 0.278 * mix(mix(1.12, 0.88, saturate(along / g.mark.w)), 1.0, reg);
        light += hue * (fill * (body + spec * 0.35 * g.look.y * (1.0 - reg)) + edge * 0.55 * rimLit * (1.0 - reg));
        inked += hue * fill;
        cover += fill;
    }
    light *= g.look.x;
    col += light / (1.0 + 0.28 * light);
    // In register the sheet is painted OVER what is behind it, not added: added, it sat 15–30
    // levels lighter than the mark it hands to.
    col = mix(col, inked / max(cover, 1e-3), saturate(cover / 5.0) * reg * reg * g.look.x);

    // Registered, the mark itself.
    float2 m = p - g.mark.xy;
    float along = m.y, across = m.x - g.mark.z * 0.5;
    float d = alignOutline(along, across, g.mark.w, g.mark.z);
    float a = saturate(0.5 - d / max(fwidth(d), 1e-4));
    col = mix(col, alignInk(along, across, g.mark.w, g.mark.z), a * g.at.w);

    // The gate's own lit mark over it, which it has become; then the name.
    float4 pic = mark.sample(s, (p - g.markPic.xy) / g.markPic.zw) * g.landing.x;
    col = col * (1.0 - pic.a) + pic.rgb;
    float4 word = name.sample(s, (p - g.name.xy) / g.name.zw) * g.landing.z;
    col = col * (1.0 - word.a) + word.rgb;

    // Leaving: the lockup goes to the plain canvas first, fast, so it is never printed over the
    // app coming up underneath; then the stage lifts the canvas itself.
    col = mix(col, g.canvas.rgb, leaving);
    col += (alignHash(in.position.xy + fract(t * 9.0)) - 0.5) * (2.0 / 255.0);
    return float4(col, 1.0);
}
