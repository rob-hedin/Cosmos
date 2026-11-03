import simd

/// Colours shared by the planetary system renderer and its tests. Linear RGB unless named otherwise.
enum PlanetaryPalette {
    /// The Belts' dusty tint, in linear RGB.
    static let beltTint: SIMD3<Float> = SIMD3(0.55, 0.5, 0.42)

    /// How strongly a Belt adds its tint to what's behind it, at the middle of the ring. Belts are
    /// faint: at the middle of the ring they show as about 13 % grey, roughly a quarter of the
    /// dimmest unselected orbit line, so the orbits and Bodies in front of them stay easy to see.
    static let beltIntensity: Float = 0.03

    /// What `PlanetarySystemRenderer` passes as `BeltInstance.color`: rgb the tint, a the intensity.
    static var beltColor: SIMD4<Float> { SIMD4(beltTint, beltIntensity) }

    /// The factor an unselected orbit line's colour is multiplied by.
    static let unselectedOrbitDimming: Float = 0.35

    /// Converts sRGB components (0...1) to linear.
    static func linear(fromSRGB color: SIMD3<Float>) -> SIMD3<Float> {
        func channel(_ c: Float) -> Float {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return SIMD3(channel(color.x), channel(color.y), channel(color.z))
    }

    /// Rec. 709 relative luminance of a linear colour: 0.2126 r + 0.7152 g + 0.0722 b.
    static func luminance(_ linear: SIMD3<Float>) -> Float {
        0.2126 * linear.x + 0.7152 * linear.y + 0.0722 * linear.z
    }
}
