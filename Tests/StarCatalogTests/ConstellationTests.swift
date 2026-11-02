import Foundation
import Testing
@testable import StarCatalog

@Suite struct ConstellationTests {
    let constellations: [Constellation]

    init() throws {
        constellations = try Constellation.bundled()
    }

    @Test func allEightyEightAreBundled() {
        #expect(constellations.count == 88)
        #expect(Set(constellations.map(\.id)).count == 88)
        #expect(constellations.allSatisfy { !$0.lines.isEmpty && $0.lines.allSatisfy { $0.count >= 2 } })
        #expect(constellations.contains { $0.name == "Serpens" })
    }

    @Test func coordinatesAreInRange() {
        for constellation in constellations {
            for point in constellation.lines.joined() + [constellation.center] {
                #expect((0..<24).contains(point.rightAscensionHours))
                #expect((-90...90).contains(point.declinationDegrees))
            }
        }
    }

    @Test func orionIsComplete() throws {
        // Betelgeuse and Rigel are beyond 200 ly, but the figure still has them.
        let ori = try #require(constellations.first { $0.id == "Ori" })
        let points = ori.lines.joined()
        #expect(points.contains { abs($0.rightAscensionHours - 5.92) < 0.05 && abs($0.declinationDegrees - 7.4) < 0.2 })
        #expect(points.contains { abs($0.rightAscensionHours - 5.24) < 0.05 && abs($0.declinationDegrees + 8.2) < 0.2 })
    }

    @Test func directionsAreUnitVectors() {
        let polaris = SkyPosition(rightAscensionHours: 2.53, declinationDegrees: 89.26)
        let length = (polaris.direction * polaris.direction).sum().squareRoot()
        #expect(abs(length - 1) < 1e-9)
        #expect(polaris.direction.z > 0.99)
    }
}
