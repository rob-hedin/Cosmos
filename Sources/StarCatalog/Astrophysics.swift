import Foundation

/// Conversions from catalog values to the quantities the renderer needs.
public enum Astrophysics {
    /// Absolute visual magnitude of the Sun.
    public static let solarAbsoluteMagnitude = 4.83

    /// Effective temperature of the Sun, in kelvin.
    public static let solarTemperature = 5772.0

    /// Temperature used when a star has no B-V, spectral type or color name.
    public static let fallbackTemperature = 5800.0

    // MARK: Position

    /// Cartesian position in light years, Sun at the origin, in the equatorial frame:
    /// +x toward RA 0h on the celestial equator, +y toward RA 6h, +z toward the north celestial pole.
    public static func position(
        rightAscensionHours: Double,
        declinationDegrees: Double,
        distanceLightYears: Double
    ) -> SIMD3<Double> {
        let ra = rightAscensionHours * 15 * .pi / 180
        let dec = declinationDegrees * .pi / 180
        let d = distanceLightYears
        return SIMD3(d * cos(dec) * cos(ra), d * cos(dec) * sin(ra), d * sin(dec))
    }

    // MARK: Luminosity and size

    /// Visual luminosity in solar units, from absolute magnitude.
    public static func luminosity(absoluteMagnitude: Double) -> Double {
        pow(10, -0.4 * (absoluteMagnitude - solarAbsoluteMagnitude))
    }

    /// Estimated radius in solar radii, from the Stefan-Boltzmann law: R ∝ √L / T².
    /// This is an estimate: it uses visual rather than bolometric luminosity.
    public static func estimatedRadius(luminosity: Double, temperature: Double) -> Double {
        luminosity.squareRoot() * pow(solarTemperature / temperature, 2)
    }

    // MARK: Temperature

    /// Effective temperature in kelvin from the B-V color index (Ballesteros 2012).
    public static func temperature(colorIndex bv: Double) -> Double {
        4600 * (1 / (0.92 * bv + 1.7) + 1 / (0.92 * bv + 0.62))
    }

    /// Typical temperature for the spectral class of a type string such as "G2V", "dM4", "k-m" or "DA2".
    /// Returns nil when no class letter is found.
    public static func temperature(spectralType: String) -> Double? {
        guard let spectralClass = spectralClass(of: spectralType) else { return nil }
        return classTemperatures[spectralClass]
    }

    /// Typical temperature for the catalog's color name, such as "Orange".
    public static func temperature(colorName: String) -> Double? {
        colorNameTemperatures[colorName]
    }

    /// The spectral class letter of a type string. Prefers an uppercase letter, so luminosity
    /// prefixes like "d", "sd" and "g" are skipped; falls back to a lowercase class letter ("m", "k-m").
    static func spectralClass(of spectralType: String) -> Character? {
        if let upper = spectralType.first(where: { "OBAFGKMLTD".contains($0) }) {
            return upper
        }
        if let lower = spectralType.first(where: { "obafgkm".contains($0) }) {
            return Character(lower.uppercased())
        }
        return nil
    }

    private static let classTemperatures: [Character: Double] = [
        "O": 35_000, "B": 20_000, "A": 8_500, "F": 6_500, "G": 5_600,
        "K": 4_400, "M": 3_200, "L": 2_000, "T": 1_300, "D": 10_000,
    ]

    private static let colorNameTemperatures: [String: Double] = [
        "Blue": 20_000, "Blue-white": 11_000, "White": 8_500, "Yellow-white": 6_500,
        "Yellow": 5_600, "Orange": 4_400, "Red": 3_200, "White dwarf": 10_000,
    ]

    // MARK: Color

    /// Linear RGB color of a blackbody at the given temperature, scaled so the brightest
    /// channel is 1. Uses Tanner Helland's fit to the CIE blackbody colors.
    public static func color(temperature: Double) -> SIMD3<Float> {
        let t = min(max(temperature, 1_000), 40_000) / 100

        let red: Double = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let green: Double = t <= 66
            ? 99.4708025861 * log(t) - 161.1195681661
            : 288.1221695283 * pow(t - 60, -0.0755148492)
        let blue: Double = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)

        let srgb = SIMD3(red, green, blue).clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 255)) / 255
        let linear = SIMD3(linearize(srgb.x), linearize(srgb.y), linearize(srgb.z))
        let peak = max(linear.max(), .ulpOfOne)
        return SIMD3<Float>(linear / peak)
    }

    private static func linearize(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
}
