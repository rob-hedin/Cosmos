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
    float sizeExponent;    // > 1 keeps most stars small and lets the few bright ones stand out
    float exposure;        // overall brightness per star
    float saturation;      // 1 = true blackbody color; higher exaggerates the tint
    float padding;
};

struct StarVertexOut {
    float4 position [[position]];
    float2 local;          // -1...1 across the billboard
    float3 color;          // already scaled by intensity
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
    float size = pow(star.positionSize.w, uniforms.sizeExponent);
    float diameter = mix(uniforms.minPointSize, uniforms.maxPointSize, size);
    clip.xy += corner * (diameter / uniforms.viewportSize) * clip.w;

    // Blackbody colors are pale; push them away from gray so the tint reads.
    float3 color = star.color.rgb;
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = max(mix(float3(luma), color, uniforms.saturation), 0.0);
    // Faint stars are dimmer as well as smaller, so dense regions don't wash out.
    float intensity = mix(0.3, 1.0, size) * uniforms.exposure;

    StarVertexOut out;
    out.position = clip;
    out.local = corner;
    out.color = color * intensity;
    return out;
}

fragment float4 starFragment(StarVertexOut in [[stage_in]]) {
    float r2 = dot(in.local, in.local);
    if (r2 > 1) {
        discard_fragment();
    }
    // A tight bright core with a faint halo. Additive blending does the rest.
    float glow = 0.85 * exp(-r2 * 10.0) + 0.15 * exp(-r2 * 3.0);
    return float4(in.color * glow, 1);
}

/// A thin ring around the selected star. Drawn with the star vertex shader, one instance.
fragment float4 ringFragment(StarVertexOut in [[stage_in]]) {
    float r = length(in.local);
    float ring = smoothstep(0.70, 0.78, r) * (1.0 - smoothstep(0.86, 0.94, r));
    if (ring <= 0) {
        discard_fragment();
    }
    return float4(in.color * ring, 1);
}

// MARK: Labels

// Layout must match LabelInstance in ShaderTypes.swift.
struct LabelInstance {
    float4 rect;     // x, y, width, height in drawable pixels, from the top-left
    float4 uvRect;   // u, v, width, height in the atlas
    float4 color;    // rgb: linear color, a: opacity
};

struct LabelVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex LabelVertexOut labelVertex(uint vertexID [[vertex_id]],
                                  uint instanceID [[instance_id]],
                                  const device LabelInstance *labels [[buffer(0)]],
                                  constant float2 &viewportSize [[buffer(1)]]) {
    LabelInstance label = labels[instanceID];
    float2 unit = (corners[vertexID] + 1.0) * 0.5;   // 0...1, y down
    float2 pixel = label.rect.xy + unit * label.rect.zw;

    LabelVertexOut out;
    out.position = float4(pixel.x / viewportSize.x * 2.0 - 1.0, 1.0 - pixel.y / viewportSize.y * 2.0, 0, 1);
    out.uv = label.uvRect.xy + unit * label.uvRect.zw;
    out.color = label.color;
    return out;
}

fragment float4 labelFragment(LabelVertexOut in [[stage_in]],
                              texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float coverage = atlas.sample(linearSampler, in.uv).r * in.color.a;
    return float4(in.color.rgb * coverage, coverage);   // premultiplied
}
