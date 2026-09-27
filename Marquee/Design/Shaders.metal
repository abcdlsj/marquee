#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A soft specular band that slides across the poster as the phone tilts,
// plus a razor-thin highlight riding on it, like light on a lacquered one-sheet.
[[ stitchable ]] half4 sheen(float2 position, half4 color, float4 bounds, float2 tilt, float strength) {
    float2 uv = position / bounds.zw;
    float d = (uv.x * 0.75 + uv.y * 0.66) - (0.72 + tilt.x * 0.85 - tilt.y * 0.6);
    float band = exp(-d * d * 22.0);
    float edge = exp(-d * d * 520.0) * 0.55;
    half3 light = half3(1.0, 0.96, 0.9) * half((band * 0.32 + edge) * strength);
    return half4(color.rgb + light * color.a, color.a);
}
