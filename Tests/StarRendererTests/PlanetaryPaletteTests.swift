import Foundation
import simd
import Testing
import StarCatalog
@testable import StarRenderer

@Suite struct PlanetaryPaletteTests {
    @Test func beltColorCombinesTheNamedTintAndIntensity() {
        #expect(PlanetaryPalette.beltColor == SIMD4(PlanetaryPalette.beltTint, PlanetaryPalette.beltIntensity))
    }

    @Test func beltPeakLuminanceIsAtMostAQuarterOfTheDimmestSolarSystemOrbit() throws {
        let system = try PlanetarySystem.solarSystem()
        let dimmestOrbitLuminance = try #require(system.bodies.map { body in
            PlanetaryPalette.luminance(PlanetaryPalette.linear(fromSRGB: body.displayColor))
                * PlanetaryPalette.unselectedOrbitDimming
        }.min())
        let beltPeakLuminance = PlanetaryPalette.luminance(PlanetaryPalette.beltTint)
            * PlanetaryPalette.beltIntensity

        #expect(beltPeakLuminance <= 0.25 * dimmestOrbitLuminance)
    }

    @Test func beltPeakLuminanceEncodesToVisibleButFaintSRGB() {
        let peakLinearLuminance = PlanetaryPalette.luminance(PlanetaryPalette.beltTint)
            * PlanetaryPalette.beltIntensity
        let peakSRGBLuminance = encodeSRGB(peakLinearLuminance)

        #expect((0.06...0.15).contains(peakSRGBLuminance))
    }

    @Test(arguments: [
        LinearConversionSample(srgb: 0, linear: 0),
        LinearConversionSample(srgb: 1, linear: 1),
        LinearConversionSample(srgb: 0.04045, linear: 0.04045 / 12.92),
        LinearConversionSample(srgb: 0.5, linear: 0.2140),
    ])
    func sRGBConversionMatchesTheLegacyValuesInEveryChannel(sample: LinearConversionSample) {
        let converted = PlanetaryPalette.linear(fromSRGB: SIMD3(repeating: sample.srgb))

        #expect(abs(converted.x - sample.linear) < 1e-4)
        #expect(abs(converted.y - sample.linear) < 1e-4)
        #expect(abs(converted.z - sample.linear) < 1e-4)
    }

    @Test func whiteHasUnitRelativeLuminance() {
        #expect(abs(PlanetaryPalette.luminance(SIMD3(1, 1, 1)) - 1) < 1e-6)
    }
}

struct LinearConversionSample: Sendable {
    let srgb: Float
    let linear: Float
}

private func encodeSRGB(_ linear: Float) -> Float {
    if linear <= 0.0031308 {
        return 12.92 * linear
    }
    return Float(1.055 * pow(Double(linear), 1 / 2.4) - 0.055)
}
