#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Radial zoom smear + chromatic fringe emanating from `center` (the ember dot, in the
// layer's local space) — the splash's camera push. A gaussian blur is uniform in every
// direction; a real camera push smears along rays from the point you're diving into,
// with the lens splitting color at the smear's edges. strength 0 = passthrough.
[[ stitchable ]] half4 emberZoom(float2 position, SwiftUI::Layer layer,
                                 float2 center, float strength) {
    if (strength < 0.001) return layer.sample(position);
    float2 dir = position - center;
    half4 acc = half4(0);
    const int N = 10;
    for (int i = 0; i < N; ++i) {
        float t = float(i) / float(N - 1);
        float s = 1.0 - strength * 0.18 * t;   // sample inward along the ray
        half4 c = layer.sample(center + dir * s);
        // chromatic fringe: red pulled toward the center, blue pushed past it
        c.r = layer.sample(center + dir * (s - strength * 0.012)).r;
        c.b = layer.sample(center + dir * (s + strength * 0.012)).b;
        acc += c;
    }
    return acc / half(N);
}

// Fine film grain. `time` arrives 24fps-quantized from Swift so the grain flickers at
// cinema cadence, not display cadence.
[[ stitchable ]] half4 filmGrain(float2 position, half4 color, float time, float intensity) {
    float n = fract(sin(dot(position * 1.37 + time * 61.7,
                            float2(12.9898, 78.233))) * 43758.5453);
    return half4(color.rgb + half3(half(n) - 0.5h) * half(intensity) * color.a, color.a);
}
