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
