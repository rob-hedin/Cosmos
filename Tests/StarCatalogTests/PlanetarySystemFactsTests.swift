import Foundation
import Testing
@testable import StarCatalog

@Suite struct PlanetarySystemFactsTests {
    @Test func earthFactsHaveTheSpecifiedRowsInOrder() throws {
        let system = try PlanetarySystem.solarSystem()
        let facts = try #require(PlanetarySystemFacts(item: .body("Earth"), in: system, locale: Locale(identifier: "en_US")))
        #expect(facts.title == "Earth")
        #expect(facts.rows == [
            .init(label: "Kind", value: "Planet"), .init(label: "Parent", value: "Sun"),
            .init(label: "Distance", value: "1 AU"), .init(label: "Period", value: "365 days"),
            .init(label: "Radius", value: "6,371 km"), .init(label: "Mass", value: "1 M⊕"),
        ])
    }

    @Test func ceresFactsIncludeItsBeltAsTheLastRow() throws {
        let system = try PlanetarySystem.solarSystem()
        let facts = try #require(PlanetarySystemFacts(item: .body("Ceres"), in: system, locale: Locale(identifier: "en_US")))
        #expect(facts.row(label: "Kind") == "Dwarf planet")
        #expect(facts.row(label: "Distance") == "2.77 AU")
        #expect(facts.row(label: "Period") == "4.61 years")
        #expect(facts.row(label: "Radius") == "470 km")
        #expect(facts.row(label: "Mass") == "0.000157 M⊕")
        #expect(facts.rows.last == .init(label: "Belt", value: "Asteroid belt"))
    }

    @Test func moonAndJupiterDistancesPeriodsAndMassesAreFormatted() throws {
        let system = try PlanetarySystem.solarSystem()
        let moon = try #require(PlanetarySystemFacts(item: .body("Moon"), in: system, locale: Locale(identifier: "en_US")))
        #expect(moon.row(label: "Parent") == "Earth")
        #expect(moon.row(label: "Distance") == "384,407 km")
        #expect(moon.row(label: "Period") == "27.3 days")

        let jupiter = try #require(PlanetarySystemFacts(item: .body("Jupiter"), in: system, locale: Locale(identifier: "en_US")))
        #expect(jupiter.row(label: "Distance") == "5.2 AU")
        #expect(jupiter.row(label: "Period") == "11.9 years")
        #expect(jupiter.row(label: "Mass") == "318 M⊕")
    }

    @Test func masslessBodiesOmitMassAndKnownPeriodsUseSingularAndYearUnits() throws {
        let planet = Body(name: "Small", kind: .planet, parent: .centralStar, orbit: Orbit(distance: 1, period: 1), radius: 100)
        let outer = Body(name: "Outer", kind: .planet, parent: .centralStar, orbit: Orbit(distance: 3, period: 800), radius: 100)
        let system = try PlanetarySystem(name: "Formatting", centralStar: .sun, bodies: [planet, outer])
        let short = try #require(PlanetarySystemFacts(item: .body("Small"), in: system, locale: Locale(identifier: "en_US")))
        let long = try #require(PlanetarySystemFacts(item: .body("Outer"), in: system, locale: Locale(identifier: "en_US")))
        #expect(short.row(label: "Period") == "1 day")
        #expect(long.row(label: "Period") == "2.19 years")
        #expect(!short.rows.contains { $0.label == "Mass" })
        #expect(!long.rows.contains { $0.label == "Mass" })
    }

    @Test func solarStarAndCatalogStarWithoutSpectralTypeHaveFacts() throws {
        let solar = try PlanetarySystem.solarSystem()
        let sun = try #require(PlanetarySystemFacts(item: .centralStar, in: solar, locale: Locale(identifier: "en_US")))
        #expect(sun.title == "Sun")
        #expect(sun.rows == [
            .init(label: "Kind", value: "Star"), .init(label: "Spectral type", value: "G2V"),
            .init(label: "Mass", value: "1 M☉"), .init(label: "Radius", value: "1 R☉"),
            .init(label: "Temperature", value: "5,772 K"),
        ])

        let catalogStar = Star(
            id: 901, name: "Unclassified", apparentMagnitude: 1, absoluteMagnitude: 5,
            spectralType: nil, colorIndex: nil, colorName: "Yellow", rightAscensionHours: 0,
            declinationDegrees: 0, distanceLightYears: 4
        )
        let unknownTypeSystem = try PlanetarySystem(name: "Other", centralStar: CentralStar(catalogStar: catalogStar), bodies: [])
        let unknownType = try #require(PlanetarySystemFacts(item: .centralStar, in: unknownTypeSystem, locale: Locale(identifier: "en_US")))
        #expect(unknownType.row(label: "Spectral type") == "Unknown")
        #expect(PlanetarySystemFacts(item: .body("Missing"), in: solar, locale: Locale(identifier: "en_US")) == nil)
    }
}

private extension PlanetarySystemFacts {
    func row(label: String) -> String? { rows.first { $0.label == label }?.value }
}
