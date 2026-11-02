import simd

/// One star as the GPU sees it. Layout matches `StarInstance` in Shaders.metal.
struct StarInstance {
    /// xyz: position in light years; w: normalized size 0...1.
    var positionSize: SIMD4<Float>
    /// rgb: linear color; a: unused.
    var color: SIMD4<Float>
}

/// Per-frame values. Layout matches `FrameUniforms` in Shaders.metal.
struct FrameUniforms {
    var viewProjection: simd_float4x4
    var viewportSize: SIMD2<Float>
    var minPointSize: Float
    var maxPointSize: Float
    var sizeExponent: Float
    var exposure: Float
    var saturation: Float
    var padding: Float = 0
}

/// One on-screen label. Layout matches `LabelInstance` in Shaders.metal.
struct LabelInstance {
    /// x, y, width, height in drawable pixels, from the top-left.
    var rect: SIMD4<Float>
    /// u, v, width, height in the atlas.
    var uvRect: SIMD4<Float>
    /// rgb: linear color; a: opacity.
    var color: SIMD4<Float>
}

/// One sphere of a Planetary System as the GPU sees it. Layout matches `SphereInstance` in Shaders.metal.
struct SphereInstance {
    /// xyz: position relative to the scene origin; w: radius, both in scene units.
    var positionRadius: SIMD4<Float>
    /// rgb: linear color; a: 1 for a light source (the star), 0 for a Body lit by the star.
    var color: SIMD4<Float>
}

/// Per-frame values for the spheres. Layout matches `SphereUniforms` in Shaders.metal.
struct SphereUniforms {
    var viewProjection: simd_float4x4
    /// Drawable size in pixels.
    var viewportSize: SIMD2<Float>
    var pixelsPerPoint: Float
    /// Smallest on-screen radius, in points.
    var minimumPointRadius: Float
    /// xyz: the camera's position relative to the scene origin.
    var eyePosition: SIMD4<Float>
    /// xyz: the camera's right direction.
    var cameraRight: SIMD4<Float>
    /// xyz: the camera's up direction.
    var cameraUp: SIMD4<Float>
    /// xyz: the star's position relative to the scene origin.
    var lightPosition: SIMD4<Float>
    /// The viewport's shorter side, in points.
    var shortSidePoints: Float
    var tanHalfFieldOfView: Float
    var padding: SIMD2<Float> = .zero
}

/// One Belt as the GPU sees it. Layout matches `BeltInstance` in Shaders.metal.
struct BeltInstance {
    /// xyz: the ring's center relative to the scene origin; w: the outer radius, in scene units.
    var centerOuter: SIMD4<Float>
    /// x: the inner radius; y: the width of the soft edges, both in scene units.
    var innerFade: SIMD4<Float>
    /// rgb: linear color; a: intensity.
    var color: SIMD4<Float>
}
