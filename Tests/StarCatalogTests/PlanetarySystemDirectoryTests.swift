import Testing
@testable import StarCatalog

@Suite struct PlanetarySystemDirectoryTests {
    @Test func builtInDirectoryContainsOnlyTheSolarSystem() throws {
        let directory = PlanetarySystemDirectory.builtIn
        let solarSystem = try PlanetarySystem.solarSystem()

        #expect(directory.systems.count == 1)
        #expect(directory.systems == [solarSystem])
    }

    @Test func builtInDirectoryFindsTheSolarSystemForTheSun() throws {
        let solarSystem = try PlanetarySystem.solarSystem()
        let directory = PlanetarySystemDirectory.builtIn

        #expect(directory.system(for: StarLocation.sun) == solarSystem)
        #expect(directory.system(for: Star.sun) == solarSystem)
    }

    @Test(arguments: ["Sirius", "Proxima Centauri"])
    func builtInDirectoryDoesNotMatchOtherNamedCatalogStars(name: String) throws {
        let star = try #require(try StarCatalog.bundled().star(named: name))

        #expect(PlanetarySystemDirectory.builtIn.system(for: star) == nil)
    }

    @Test func builtInDirectoryDoesNotMatchFirstCatalogStarOrCatalogLocations() throws {
        let catalog = try StarCatalog.bundled()
        let firstStar = try #require(catalog.stars.first)
        let location = StarLocation(name: firstStar.name, position: firstStar.position, starID: firstStar.id)

        #expect(PlanetarySystemDirectory.builtIn.system(for: firstStar) == nil)
        #expect(PlanetarySystemDirectory.builtIn.system(for: location) == nil)
    }

    @Test func emptyDirectoryHasNoSystemsAndIsTheDefaultValue() {
        let empty = PlanetarySystemDirectory.empty

        #expect(empty.systems.isEmpty)
        #expect(empty.system(for: Star.sun) == nil)
        #expect(PlanetarySystemDirectory() == empty)
    }

    @Test func catalogStarSystemMatchesItsStarAndLocationOnly() throws {
        let catalog = try StarCatalog.bundled()
        let sirius = try #require(catalog.star(named: "Sirius"))
        let proxima = try #require(catalog.star(named: "Proxima Centauri"))
        let system = try makeSystem("Sirius system", centralStar: CentralStar(catalogStar: sirius))
        let directory = PlanetarySystemDirectory([system])
        let siriusLocation = StarLocation(name: sirius.name, position: sirius.position, starID: sirius.id)

        #expect(directory.system(for: sirius) == system)
        #expect(directory.system(for: siriusLocation) == system)
        #expect(directory.system(for: proxima) == nil)
        #expect(directory.system(for: Star.sun) == nil)
    }

    @Test func fromScratchCentralStarSystemDoesNotMatchCatalogStars() throws {
        let catalog = try StarCatalog.bundled()
        let sirius = try #require(catalog.star(named: "Sirius"))
        let proxima = try #require(catalog.star(named: "Proxima Centauri"))
        let firstStar = try #require(catalog.stars.first)
        let centralStar = try CentralStar(name: "Kepler-X", spectralType: "K2V")
        let system = try makeSystem("Kepler-X system", centralStar: centralStar)
        let directory = PlanetarySystemDirectory([system])

        #expect(centralStar.location == nil)
        #expect(directory.system(for: Star.sun) == nil)
        #expect(directory.system(for: sirius) == nil)
        #expect(directory.system(for: proxima) == nil)
        #expect(directory.system(for: firstStar) == nil)
    }

    @Test func firstMatchingSystemWinsAndInputOrderIsPreserved() throws {
        let catalog = try StarCatalog.bundled()
        let sirius = try #require(catalog.star(named: "Sirius"))
        let first = try makeSystem("First", centralStar: CentralStar(catalogStar: sirius))
        let second = try makeSystem("Second", centralStar: CentralStar(catalogStar: sirius))
        let directory = PlanetarySystemDirectory([first, second])

        #expect(directory.systems.map(\.name) == ["First", "Second"])
        #expect(directory.system(for: sirius) == first)
    }

    @Test func sunSentinelFromCatalogStarAndSunLocationBothMatch() throws {
        let systemFromCatalogSun = try makeSystem(
            "Catalog Sun system",
            centralStar: CentralStar(catalogStar: Star.sun)
        )
        let directory = PlanetarySystemDirectory([systemFromCatalogSun])
        let sentinelLocation = StarLocation(name: "Sun", position: .zero, starID: Star.sunID)
        let catalog = try StarCatalog.bundled()
        let sirius = try #require(catalog.star(named: "Sirius"))
        let proxima = try #require(catalog.star(named: "Proxima Centauri"))

        #expect(directory.system(for: StarLocation.sun) == systemFromCatalogSun)
        #expect(directory.system(for: Star.sun) == systemFromCatalogSun)
        #expect(directory.system(for: sentinelLocation) == systemFromCatalogSun)
        #expect(directory.system(for: sirius) == nil)
        #expect(directory.system(for: proxima) == nil)

        let systemFromCentralSun = try makeSystem("Central Sun system", centralStar: .sun)
        let centralSunDirectory = PlanetarySystemDirectory([systemFromCentralSun])
        #expect(centralSunDirectory.system(for: sentinelLocation) == systemFromCentralSun)
    }
}

private func makeSystem(_ name: String, centralStar: CentralStar) throws -> PlanetarySystem {
    try PlanetarySystem(
        name: name,
        centralStar: centralStar,
        bodies: [
            Body(
                name: "Test planet",
                kind: .planet,
                parent: .centralStar,
                orbit: Orbit(distance: 1),
                radius: 1
            ),
        ]
    )
}
