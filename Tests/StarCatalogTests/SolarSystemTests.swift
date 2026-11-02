import Testing
@testable import StarCatalog

@Suite struct SolarSystemTests {
    @Test func bundledSystemUsesCatalogSun() throws {
        let system = try PlanetarySystem.solarSystem()
        let catalog = try StarCatalog.bundled()

        #expect(system.name == "Solar System")
        #expect(system.centralStar == .sun)
        #expect(system.centralStar.location == catalog.location(named: "Sun"))
    }

    @Test func bundledBodiesAndBeltsMatchTheSolarInventory() throws {
        let system = try PlanetarySystem.solarSystem()
        let expected: [(String, Body.Kind, Parent)] = [
            ("Mercury", .planet, .centralStar), ("Venus", .planet, .centralStar),
            ("Earth", .planet, .centralStar), ("Mars", .planet, .centralStar),
            ("Jupiter", .planet, .centralStar), ("Saturn", .planet, .centralStar),
            ("Uranus", .planet, .centralStar), ("Neptune", .planet, .centralStar),
            ("Ceres", .dwarfPlanet, .centralStar), ("Pluto", .dwarfPlanet, .centralStar),
            ("Eris", .dwarfPlanet, .centralStar), ("Haumea", .dwarfPlanet, .centralStar),
            ("Makemake", .dwarfPlanet, .centralStar),
            ("Moon", .moon, .body("Earth")), ("Io", .moon, .body("Jupiter")),
            ("Europa", .moon, .body("Jupiter")), ("Ganymede", .moon, .body("Jupiter")),
            ("Callisto", .moon, .body("Jupiter")), ("Titan", .moon, .body("Saturn")),
            ("Triton", .moon, .body("Neptune")), ("Charon", .moon, .body("Pluto")),
        ]
        let actual = system.bodies.map { ($0.name, $0.kind, $0.parent) }

        #expect(actual.count == 21)
        let sameRows = actual.elementsEqual(expected) { (a: (String, Body.Kind, Parent), b: (String, Body.Kind, Parent)) -> Bool in
            let sameName: Bool = a.0 == b.0
            let sameKind: Bool = a.1 == b.1
            let sameParent: Bool = a.2 == b.2
            return sameName && sameKind && sameParent
        }
        #expect(sameRows)
        #expect(system.bodies.filter { $0.kind == .comet }.isEmpty)
        #expect(system.belts.map(\.name) == ["Asteroid belt", "Kuiper belt"])
        #expect(system.belts.allSatisfy { $0.parent == .centralStar })
    }

    @Test func planetsAreOrderedByDistanceAndEveryBodyHasMass() throws {
        let system = try PlanetarySystem.solarSystem()
        let planets = system.bodies.filter { $0.kind == .planet }
        #expect(planets.map(\.name) == ["Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"])
        #expect(zip(planets, planets.dropFirst()).allSatisfy { $0.0.orbit.distance < $0.1.orbit.distance })
        #expect(system.bodies.allSatisfy { $0.mass != nil })
    }

    @Test(arguments: [
        ("Earth", 365.25, 0.005),
        ("Jupiter", 4_332.6, 0.01),
        ("Neptune", 60_190, 0.01),
        ("Moon", 27.32, 0.02),
        ("Io", 1.769, 0.02),
        ("Charon", 6.387, 0.02),
    ])
    func derivedPeriodsAreNearObservedValues(name: String, expected: Double, relativeTolerance: Double) throws {
        let system = try PlanetarySystem.solarSystem()
        let body = try #require(system.body(named: name))
        let period = try #require(system.orbitalPeriod(of: body))
        #expect(abs(period - expected) / expected <= relativeTolerance)
    }

    @Test func builtInBeltsContainOnlyTheirIntendedBodies() throws {
        let system = try PlanetarySystem.solarSystem()
        for (bodyName, beltName) in [("Ceres", "Asteroid belt"), ("Pluto", "Kuiper belt"), ("Haumea", "Kuiper belt"), ("Makemake", "Kuiper belt")] {
            let body = try #require(system.body(named: bodyName))
            #expect(system.belt(containing: body)?.name == beltName)
        }
        for bodyName in ["Eris", "Earth", "Moon"] {
            let body = try #require(system.body(named: bodyName))
            #expect(system.belt(containing: body) == nil)
        }
    }
}
