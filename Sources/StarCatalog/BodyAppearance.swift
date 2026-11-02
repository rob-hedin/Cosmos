extension Body.Kind {
    /// "Planet", "Dwarf planet", "Moon", "Asteroid" or "Comet".
    public var displayName: String {
        switch self {
        case .planet: "Planet"
        case .dwarfPlanet: "Dwarf planet"
        case .moon: "Moon"
        case .asteroid: "Asteroid"
        case .comet: "Comet"
        }
    }

    /// The sRGB color (components in 0...1) used for a Body of this Kind that has no color of its own.
    /// Every Kind has a different one.
    public var defaultColor: SIMD3<Float> {
        switch self {
        case .planet: SIMD3(0.62, 0.68, 0.78)
        case .dwarfPlanet: SIMD3(0.74, 0.66, 0.56)
        case .moon: SIMD3(0.70, 0.70, 0.70)
        case .asteroid: SIMD3(0.55, 0.50, 0.45)
        case .comet: SIMD3(0.78, 0.88, 0.96)
        }
    }
}

extension Body {
    /// The Body's own `color`, or its Kind's `defaultColor` when it has none. sRGB, components in 0...1.
    public var displayColor: SIMD3<Float> {
        color ?? kind.defaultColor
    }
}
