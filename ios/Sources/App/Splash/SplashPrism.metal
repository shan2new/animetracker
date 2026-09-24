#include <metal_stdlib>
using namespace metal;

// PRISM — the app icon's ribbon, sculpted in glass, lit on a dark stage.
//
// The reference is the ident Apple TV shipped in November 2025: a solid glass logo on a
// blacked-out stage, shot in macro, coloured light moving through it — "reflection, colour and
// light" — and Netflix's ribbon-folded N: the brand's own mark as a real material, brief and
// confident. Here the mark is the icon's own: a thick glass bookmark ribbon (its bevels rounded
// like the Liquid Glass icon) with light in the icon's ramp — gold at the head, amber, coral at the
// tails — pouring down through it, bending hard at the bevels (a trace of dispersion there), a key
// light catching the edges; the coral full stop beside the tails, a glass bead with its own glow;
// the name beneath.

struct PrismParams {
    float4 view;     // width, height (points), scale (px/pt), film time
    float4 mark;     // the ribbon at rest: x, y (top left), width, height (points)
    float4 camera;   // zoom about the ribbon's centre, tilt (radians), reveal 0…1, pour 0…1
    float4 look;     // bead 0…1, name 0…1, glint sweep 0…1, spill 0…1
    float4 name;     // the name's box: x, y, w, h (points)
    float4 bead;     // the full stop: centre x, y, radius (points), _
    float4 canvas;   // sRGB
};

struct PrismVertex { float4 position [[position]]; };

vertex PrismVertex prismVertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    PrismVertex out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

static float prismHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

static float sdTriangle(float2 p, float2 p0, float2 p1, float2 p2) {
    float2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
    float2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
    float2 pq0 = v0 - e0 * saturate(dot(v0, e0) / dot(e0, e0));
    float2 pq1 = v1 - e1 * saturate(dot(v1, e1) / dot(e1, e1));
    float2 pq2 = v2 - e2 * saturate(dot(v2, e2) / dot(e2, e2));
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                       float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

static float smax(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return max(a, b) + h * h * k * 0.25;
}

/// The ribbon, in units of its width: x 0…1 across, y 0…aspect down; a notch cut up into its
/// foot. Signed distance, negative inside.
static float ribbon(float2 u, float aspect) {
    const float notch = 0.40;
    float box = sdRoundBox(u - float2(0.5, aspect * 0.5), float2(0.5, aspect * 0.5), 0.06);
    float tri = sdTriangle(u, float2(0.5, aspect - notch), float2(-0.5, aspect + notch), float2(1.5, aspect + notch));
    return smax(box, -tri, 0.05);
}

/// The light behind the glass: the icon's ramp pouring downward, gold at the head to coral at the
/// tails, with slow soft pools of brighter light travelling through it.
static float3 light(float2 u, float aspect, float pour, float time) {
    float y = u.y / aspect;                       // 0 head … 1 tails
    float3 gold  = float3(1.00, 0.78, 0.36);
    float3 amber = float3(1.00, 0.56, 0.24);
    float3 coral = float3(0.93, 0.30, 0.22);
    float3 deep  = float3(0.55, 0.10, 0.12);
    // The ramp runs the icon's diagonal, and the whole of it travels down as the light pours in.
    float k = saturate(y * 0.85 + u.x * 0.18 - (1.0 - pour) * 1.1 + 0.05);
    float3 c = k < 0.45 ? mix(gold, amber, k / 0.45) : (k < 0.80 ? mix(amber, coral, (k - 0.45) / 0.35) : mix(coral, deep, (k - 0.80) / 0.20));
    // Where the light has not reached yet, the glass is dark.
    float lit = smoothstep(-0.10, 0.25, pour * 1.35 - y);
    // Soft travelling pools.
    float pools = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float2 at = float2(0.3 + 0.35 * sin(time * (0.7 + fi * 0.23) + fi * 2.1),
                           fmod(pour * aspect * 1.25 + fi * 0.7 + time * 0.15, aspect + 0.6) - 0.3);
        float2 e = (u - at) / float2(0.55, 0.45);
        pools += exp(-dot(e, e) * 2.0) * (0.45 - fi * 0.08);
    }
    return c * lit * (0.62 + pools);
}

fragment float4 prismFragment(PrismVertex in [[stage_in]],
                              constant PrismParams& g [[buffer(0)]],
                              texture2d<float> name [[texture(0)]],
                              sampler s [[sampler(0)]]) {
    float time = g.view.w;
    float scale = g.view.z;
    float2 p = in.position.xy / scale;
    float3 col = g.canvas.rgb;

    // The camera: a slow pull back and a settling tilt, about the ribbon's centre.
    float2 centre = g.mark.xy + g.mark.zw * 0.5;
    float zoom = g.camera.x;
    float ct = cos(g.camera.y), st = sin(g.camera.y);
    float2 rel = (p - centre) / zoom;
    rel = float2(ct * rel.x - st * rel.y, st * rel.x + ct * rel.y);
    float2 w = centre + rel;                                  // world point, at rest
    float W = g.mark.z;
    float aspect = g.mark.w / W;
    float2 u = (w - g.mark.xy) / W;                           // ribbon units
    float reveal = g.camera.z;
    float pour = g.camera.w;

    float sd = ribbon(u, aspect);
    // The light that passes through the glass spills softly onto the stage around and below it.
    float outside = max(sd, 0.0);
    float3 spillLight = light(clamp(u, float2(0.0), float2(1.0, aspect)), aspect, pour, time);
    col += spillLight * g.look.w * 0.10 * exp(-outside * outside * 7.0) * smoothstep(-0.2, 0.6, u.y / aspect);

    if (sd < 0.02) {
        // Thick clear glass with rounded bevels. The FACE is clear — the dark stage seen through
        // it, a trace of the icon's ramp, a slow reflection — and the colour lives in the BEVELS,
        // where the studio lights around it refract: warm light whose hue follows the way each
        // edge faces, travelling round the rim as the lights turn. (An opaque tinted slab with
        // shaded bevels read as a 2008 button.)
        const float bevel = 0.15;
        float inside = max(-sd, 0.0);
        float t = saturate(inside / bevel);
        float e = 0.0025;
        float2 grad = float2(ribbon(u + float2(e, 0), aspect) - ribbon(u - float2(e, 0), aspect),
                             ribbon(u + float2(0, e), aspect) - ribbon(u - float2(0, e), aspect)) / (2.0 * e);
        float2 out2 = normalize(grad + 1e-5);
        float edgeness = pow(1.0 - t, 1.6);

        // The lights around the glass: the icon's warm spectrum on a slowly turning ring.
        float turn = time * 0.55 + pour * 2.2;
        float ang = atan2(out2.y, out2.x) + turn;
        float3 gold = float3(1.00, 0.78, 0.36), amber = float3(1.00, 0.52, 0.20);
        float3 coral = float3(0.96, 0.30, 0.24), rose = float3(0.92, 0.28, 0.50);
        float a = fract(ang / 6.28318);
        float3 hue = a < 0.25 ? mix(gold, amber, a / 0.25) : (a < 0.5 ? mix(amber, coral, (a - 0.25) / 0.25)
                   : (a < 0.75 ? mix(coral, rose, (a - 0.5) / 0.25) : mix(rose, gold, (a - 0.75) / 0.25)));
        float lobes = 0.55 + 0.45 * pow(0.5 + 0.5 * cos(ang * 2.0), 2.0);
        // A hair of dispersion across the bevel: warmer outside, cooler inside.
        float3 bevelLight = hue * lobes * edgeness * (1.35 + 0.35 * sin(t * 9.0 + time * 2.0));
        bevelLight *= float3(1.0 + 0.10 * (1.0 - t), 1.0, 1.0 - 0.10 * (1.0 - t));

        // Light carried along the edge inside the slab: a fine bright line just within the rim.
        float pipe = exp(-pow((t - 0.28) / 0.07, 2.0)) * 0.35;
        // The face: the stage through clear glass, the icon's ramp as a faint body colour, and a
        // slow soft reflection gliding across it.
        float y = u.y / aspect;
        float3 ramp = mix(float3(1.00, 0.72, 0.36), float3(0.92, 0.30, 0.22), saturate(y * 0.9 + u.x * 0.15));
        float3 face = g.canvas.rgb + ramp * (0.10 + 0.08 * pour);
        float band = dot(u - float2(0.5, aspect * 0.5), normalize(float2(0.62, -0.78))) - mix(-1.2, 1.0, fract(time * 0.28));
        face += exp(-band * band * 5.0) * 0.08;

        // The key light, upper left: crisp highlights on the bevels that face it.
        float facing = saturate(dot(out2, normalize(float2(-0.6, -0.8))));
        float spec = pow(facing, 6.0) * edgeness * 0.85 + pow(facing, 30.0) * exp(-pow((t - 0.12) / 0.06, 2.0)) * 0.9;
        // The glint as the lockup completes.
        float gs = g.look.z;
        float glint = 0.0;
        if (gs > 0.0 && gs < 1.0) {
            float gb = dot(u - float2(0.5, aspect * 0.5), normalize(float2(0.55, -0.83))) - mix(-1.6, 1.6, gs);
            glint = exp(-gb * gb * 16.0) * 0.35 * sin(gs * 3.14159);
        }
        float3 glass = face + bevelLight + hue * pipe + float3(1.0, 0.96, 0.92) * (spec + glint);

        // Lit rim-first: the light finds the edges before the body.
        float rimFirst = saturate(reveal * 1.8 - t * 0.8);
        float body = mix(rimFirst, 1.0, smoothstep(0.45, 1.0, reveal));
        float aa = 1.2 / (scale * zoom * W);
        float edge = smoothstep(0.0, -aa, sd);
        col = mix(col, glass, edge * body);
    }

    // The full stop: a bead of coral glass beside the tails, with its own small glow — in the
    // world, so it rides the camera with the ribbon.
    float2 bd = (w - g.bead.xy) / g.bead.z;
    float br = length(bd);
    float bead = g.look.x;
    float3 coral = float3(0.94, 0.34, 0.25);
    col += coral * bead * 0.30 * exp(-pow(max(br - 0.5, 0.0) / 1.8, 2.0));
    if (br < 1.0) {
        float3 n = float3(bd, sqrt(1.0 - br * br));
        float3 L = normalize(float3(-0.55, -0.70, 0.45));
        float diff = saturate(dot(n, float3(-L.x, -L.y, L.z)) * 0.5 + 0.55);
        float3 c = coral * (0.72 + 0.42 * diff);
        c += pow(1.0 - n.z, 2.5) * float3(1.0, 0.7, 0.55) * 0.32;
        float2 hs = (bd - float2(-0.34, -0.40)) / float2(0.30, 0.20);
        c += exp(-dot(hs, hs) * 2.0) * 0.42;
        float aa = 1.2 / (scale * zoom * g.bead.z);
        col = mix(col, c, smoothstep(1.0, 1.0 - aa, br) * bead);
    }

    // The name, beneath.
    // In its own inks: the letters white, the full stop the brand's coral (premultiplied).
    float2 nuv = (w - g.name.xy) / g.name.zw;
    float4 ink = name.sample(s, nuv);
    col = col * (1.0 - ink.a * g.look.y) + ink.rgb * g.look.y;

    col += (prismHash(in.position.xy + fract(time * 11.0)) - 0.5) * (1.2 / 255.0);
    return float4(col, 1.0);
}
