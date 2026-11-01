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
}
