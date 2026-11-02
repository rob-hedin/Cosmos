import Foundation
import Testing
@testable import StarCatalog

@Suite struct ConstellationTests {
    let constellations: [Constellation]
    let catalog: StarCatalog

    init() throws {
        constellations = try Constellation.bundled()
        catalog = try StarCatalog.bundled()
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

    @Test func bigDipperStarsAreInTheCatalog() throws {
        let uma = try #require(constellations.first { $0.id == "UMa" })
        let names = Set(uma.lines.joined().compactMap { catalog.star(near: $0)?.name })
        for name in ["Dubhe", "Merak", "Phecda", "Megrez", "Alioth", "Mizar", "Alkaid"] {
            #expect(names.contains(name), "\(name)")
        }
    }

    @Test func orionsBrightStarsAreBeyondIt() throws {
        let ori = try #require(constellations.first { $0.id == "Ori" })
        // Betelgeuse is near RA 5.92h, Dec +7.4°; it's about 550 ly away.
        let betelgeuse = try #require(ori.lines.joined().first {
            abs($0.rightAscensionHours - 5.92) < 0.05 && abs($0.declinationDegrees - 7.4) < 0.2
        })
        #expect(catalog.star(near: betelgeuse) == nil)
    }

    /// Points whose stars lie beyond the catalog mustn't pick up an unrelated neighbor.
    @Test(arguments: [(10.27817, 23.4173), (10.37215, 41.4995)])
    func missingFigureStarsAreNotSubstituted(ra: Double, dec: Double) {
        #expect(catalog.star(near: SkyPosition(rightAscensionHours: ra, declinationDegrees: dec)) == nil)
    }

    @Test func directionsAreUnitVectors() {
        let polaris = SkyPosition(rightAscensionHours: 2.53, declinationDegrees: 89.26)
        let length = (polaris.direction * polaris.direction).sum().squareRoot()
        #expect(abs(length - 1) < 1e-9)
        #expect(polaris.direction.z > 0.99)
    }
}
