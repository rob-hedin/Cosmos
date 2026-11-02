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

// MARK: Reference rings

struct LineVertexOut {
    float4 position [[position]];
};

/// Points of a line strip in light years (xyz; w unused).
vertex LineVertexOut lineVertex(uint vertexID [[vertex_id]],
                                const device float4 *points [[buffer(0)]],
                                constant FrameUniforms &uniforms [[buffer(1)]]) {
    LineVertexOut out;
    out.position = uniforms.viewProjection * float4(points[vertexID].xyz, 1);
    return out;
}

/// A flat linear color, added to what's there (rgb scaled by a).
fragment float4 lineFragment(constant float4 &color [[buffer(0)]]) {
    return float4(color.rgb * color.a, 1);
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

// MARK: Planetary systems

/// Points of a line strip (xyz, in scene units) moved by a per-draw offset, such as the position of
/// the orbit's Parent.
vertex LineVertexOut offsetLineVertex(uint vertexID [[vertex_id]],
                                      const device float4 *points [[buffer(0)]],
                                      constant FrameUniforms &uniforms [[buffer(1)]],
                                      constant float4 &offset [[buffer(2)]]) {
    LineVertexOut out;
    out.position = uniforms.viewProjection * float4(points[vertexID].xyz + offset.xyz, 1);
    return out;
}

// Layout must match BeltInstance in ShaderTypes.swift.
struct BeltInstance {
    float4 centerOuter;   // xyz: center relative to the scene origin, w: outer radius
    float4 innerFade;     // x: inner radius, y: soft edge width
    float4 color;         // rgb: linear color, a: intensity
};

struct BeltVertexOut {
    float4 position [[position]];
    float2 local;                 // position in the ring's plane, from its center
    float inner [[flat]];
    float outer [[flat]];
    float fade [[flat]];
    float4 color [[flat]];
};

/// A quad in the x-y plane around the Belt's center, big enough to hold the soft outer edge.
vertex BeltVertexOut beltVertex(uint vertexID [[vertex_id]],
                                uint instanceID [[instance_id]],
                                const device BeltInstance *belts [[buffer(0)]],
                                constant FrameUniforms &uniforms [[buffer(1)]]) {
    BeltInstance belt = belts[instanceID];
    float reach = belt.centerOuter.w + belt.innerFade.y;
    float2 local = corners[vertexID] * reach;

    BeltVertexOut out;
    out.position = uniforms.viewProjection * float4(belt.centerOuter.xyz + float3(local, 0), 1);
    out.local = local;
    out.inner = belt.innerFade.x;
    out.outer = belt.centerOuter.w;
    out.fade = max(belt.innerFade.y, 1e-9);
    out.color = belt.color;
    return out;
}

/// A faint annulus between the inner and outer edges, with soft edges, added to what is there.
fragment float4 beltFragment(BeltVertexOut in [[stage_in]]) {
    float r = length(in.local);
    float ring = 1.0 - smoothstep(in.outer - in.fade, in.outer + in.fade, r);
    if (in.inner > 0) {
        ring *= smoothstep(in.inner - in.fade, in.inner + in.fade, r);
    }
    if (ring <= 0) {
        discard_fragment();
    }
    return float4(in.color.rgb * (in.color.a * ring), 1);
}

// Layouts must match SphereInstance and SphereUniforms in ShaderTypes.swift.
struct SphereInstance {
    float4 positionRadius;   // xyz: position relative to the scene origin, w: radius (scene units)
    float4 color;            // rgb: linear color, a: 1 for a light source (the star)
};

struct SphereUniforms {
    float4x4 viewProjection;
    float2 viewportSize;         // drawable size in pixels
    float pixelsPerPoint;
    float minimumPointRadius;    // points
    float4 eyePosition;          // xyz: camera position relative to the scene origin
    float4 cameraRight;          // xyz
    float4 cameraUp;             // xyz
    float4 lightPosition;        // xyz: the star's position relative to the scene origin
    float shortSidePoints;       // the viewport's shorter side, in points
    float tanHalfFieldOfView;
    float2 padding;
};

struct SphereVertexOut {
    float4 position [[position]];
    float2 local;                    // -1...1 across the billboard
    float pixelRadius [[flat]];      // drawn radius in pixels
    float3 color [[flat]];
    float3 lightDirection [[flat]];  // toward the star, in the sphere's own frame (x right, y up, z toward the eye)
    float emissive [[flat]];
};

/// A camera-facing quad per sphere, as wide as the sphere looks: the same formula as
/// SphereProjection.pointRadius in Swift, so what is drawn is what is picked.
vertex SphereVertexOut sphereVertex(uint vertexID [[vertex_id]],
                                    uint instanceID [[instance_id]],
                                    const device SphereInstance *spheres [[buffer(0)]],
                                    constant SphereUniforms &uniforms [[buffer(1)]]) {
    SphereInstance sphere = spheres[instanceID];
    float3 center = sphere.positionRadius.xyz;
    float radius = sphere.positionRadius.w;
    float3 toEye = uniforms.eyePosition.xyz - center;
    float eyeDistance = length(toEye);

    float pointRadius;
    if (eyeDistance <= radius) {
        pointRadius = uniforms.shortSidePoints;
    } else {
        float apparent = tan(asin(radius / eyeDistance)) / uniforms.tanHalfFieldOfView * uniforms.shortSidePoints * 0.5;
        pointRadius = max(apparent, uniforms.minimumPointRadius);
    }
    float pixelRadius = pointRadius * uniforms.pixelsPerPoint;

    float4 clip = uniforms.viewProjection * float4(center, 1);
    float2 corner = corners[vertexID];
    clip.xy += corner * (2.0 * pixelRadius / uniforms.viewportSize) * clip.w;

    // The sphere's own frame faces the eye, with the camera's up as its up, so a lit side keeps
    // its orientation wherever the sphere sits in the view.
    float3 forward = eyeDistance > 1e-12 ? toEye / eyeDistance : cross(uniforms.cameraRight.xyz, uniforms.cameraUp.xyz);
    float3 right = normalize(cross(uniforms.cameraUp.xyz, forward));
    float3 up = cross(forward, right);
    float3 toLight = uniforms.lightPosition.xyz - center;
    float lightDistance = length(toLight);
    float3 light = lightDistance > 1e-12 ? toLight / lightDistance : forward;

    SphereVertexOut out;
    out.position = clip;
    out.local = corner;
    out.pixelRadius = pixelRadius;
    out.color = sphere.color.rgb;
    out.lightDirection = float3(dot(light, right), dot(light, up), dot(light, forward));
    out.emissive = sphere.color.a;
    return out;
}

/// A lit ball: Lambert shading plus a little ambient light, from the star. The star itself glows.
/// Output is premultiplied, with a one-pixel soft edge.
fragment float4 sphereFragment(SphereVertexOut in [[stage_in]]) {
    float r2 = dot(in.local, in.local);
    if (r2 > 1.0) {
        discard_fragment();
    }
    float coverage = clamp((1.0 - sqrt(r2)) * in.pixelRadius, 0.0, 1.0);
    float3 normal = float3(in.local, sqrt(1.0 - r2));
    float lambert = max(dot(normal, in.lightDirection), 0.0);
    float3 lit = in.color * (0.06 + lambert);
    float3 glowing = in.color * (0.7 + 0.3 * normal.z);
    float3 rgb = mix(lit, glowing, in.emissive);
    return float4(rgb * coverage, coverage);
}
