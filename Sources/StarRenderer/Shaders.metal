#include <metal_stdlib>
using namespace metal;

// Layouts must match StarInstance and FrameUniforms in ShaderTypes.swift.

struct StarInstance {
    float4 positionSize;   // xyz: light years, w: normalized size 0...1
    float4 color;          // rgb: linear color, a: unused
};

struct FrameUniforms {
    float4x4 viewProjection;
    float2 viewportSize;   // drawable size in pixels
    float minPointSize;    // pixels, for size 0
    float maxPointSize;    // pixels, for size 1
};

struct StarVertexOut {
    float4 position [[position]];
    float2 local;          // -1...1 across the billboard
    float3 color;
};

constant float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };

vertex StarVertexOut starVertex(uint vertexID [[vertex_id]],
                                uint instanceID [[instance_id]],
                                const device StarInstance *stars [[buffer(0)]],
                                constant FrameUniforms &uniforms [[buffer(1)]]) {
    StarInstance star = stars[instanceID];
    float2 corner = corners[vertexID];

    // Project the center, then grow the quad in screen space so a star keeps
    // its pixel size at any zoom.
    float4 clip = uniforms.viewProjection * float4(star.positionSize.xyz, 1);
    float diameter = mix(uniforms.minPointSize, uniforms.maxPointSize, star.positionSize.w);
    clip.xy += corner * (diameter / uniforms.viewportSize) * clip.w;

    StarVertexOut out;
    out.position = clip;
    out.local = corner;
    out.color = star.color.rgb;
    return out;
}

fragment float4 starFragment(StarVertexOut in [[stage_in]]) {
    float r2 = dot(in.local, in.local);
    if (r2 > 1) {
        discard_fragment();
    }
    // A bright core inside a soft Gaussian halo. Additive blending does the rest.
    float glow = exp(-r2 * 5.0) + 0.6 * exp(-r2 * 40.0);
    return float4(in.color * glow, 1);
}
