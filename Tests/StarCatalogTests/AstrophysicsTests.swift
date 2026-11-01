import Foundation
import Testing
@testable import StarCatalog

@Suite struct AstrophysicsTests {
    @Test func positionFollowsEquatorialAxes() {
        let east = Astrophysics.position(rightAscensionHours: 6, declinationDegrees: 0, distanceLightYears: 10)
        #expect(abs(east.x) < 1e-9)
        #expect(abs(east.y - 10) < 1e-9)

        let pole = Astrophysics.position(rightAscensionHours: 3, declinationDegrees: 90, distanceLightYears: 5)
        #expect(abs(pole.z - 5) < 1e-9)
    }

    @Test func sunHasUnitLuminosity() {
        #expect(abs(Astrophysics.luminosity(absoluteMagnitude: 4.83) - 1) < 1e-12)
        // Five magnitudes brighter is 100 times more luminous.
        #expect(abs(Astrophysics.luminosity(absoluteMagnitude: -0.17) - 100) < 1e-9)
    }

    @Test func sunColorIndexGivesSolarTemperature() {
        let t = Astrophysics.temperature(colorIndex: 0.65)
        #expect(abs(t - 5_778) < 25)
    }

    @Test func sunHasUnitRadius() {
        let r = Astrophysics.estimatedRadius(luminosity: 1, temperature: Astrophysics.solarTemperature)
        #expect(abs(r - 1) < 1e-12)
    }

    @Test(arguments: [
        ("G2V", "G"), ("dM4", "M"), ("sdM1", "M"), ("gK0", "K"), ("k-m", "K"),
        ("m", "M"), ("DA2", "D"), ("A1V", "A"), ("M:", "M"),
    ])
    func spectralClassParsing(type: String, expected: String) {
        #expect(Astrophysics.spectralClass(of: type) == Character(expected))
    }

    @Test func spectralClassMissing() {
        #expect(Astrophysics.spectralClass(of: "") == nil)
        #expect(Astrophysics.temperature(spectralType: "?") == nil)
    }

    @Test func hotStarsAreBlueAndCoolStarsAreRed() {
        let hot = Astrophysics.color(temperature: 20_000)
        let cool = Astrophysics.color(temperature: 3_200)
        #expect(hot.z > hot.x)
        #expect(cool.x > cool.z)
        for c in [hot, cool] {
            #expect(abs(c.max() - 1) < 1e-6)
            #expect(c.min() >= 0)
        }
    }
}
