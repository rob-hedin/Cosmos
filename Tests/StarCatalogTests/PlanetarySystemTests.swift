import Testing
@testable import StarCatalog

@Suite struct CentralStarTests {
    @Test func sunHasCatalogSolarValues() {
        #expect(CentralStar.sun.name == "Sun")
        #expect(CentralStar.sun.spectralType == "G2V")
        #expect(CentralStar.sun.mass == 1)
        #expect(CentralStar.sun.radius == 1)
        #expect(CentralStar.sun.temperature == Astrophysics.solarTemperature)
        #expect(CentralStar.sun.location == .sun)
    }

    @Test func catalogStarCopiesPropertiesAndEstimatesMassFromType() throws {
        let star = makeStar(id: 42, name: "Orange Star", spectralType: "K1V", rightAscensionHours: 6, distanceLightYears: 4)
        let centralStar = CentralStar(catalogStar: star)

        #expect(centralStar.name == star.name)
        #expect(centralStar.spectralType == star.spectralType)
        #expect(centralStar.temperature == star.temperature)
        #expect(centralStar.radius == star.estimatedRadius)
        #expect(centralStar.mass == Astrophysics.estimatedMass(spectralType: "K1V"))
        #expect(centralStar.location?.starID == star.id)
        #expect(centralStar.location?.position == star.position)
    }

    @Test func catalogStarWithoutTypeEstimatesMassFromTemperature() {
        let star = makeStar(id: 43, name: "Unclassified Star", spectralType: nil, colorName: "Red")
        let centralStar = CentralStar(catalogStar: star)

        #expect(centralStar.spectralType == nil)
        #expect(centralStar.mass == Astrophysics.estimatedMass(temperature: star.temperature))
    }

    @Test func fromScratchStarEstimatesOmittedValuesAndKeepsGivenValues() throws {
        let estimated = try CentralStar(name: "Kepler-x", spectralType: "M3V")
        #expect(estimated.mass == Astrophysics.estimatedMass(spectralType: "M3V"))
        #expect(estimated.radius == Astrophysics.estimatedRadius(spectralType: "M3V"))
        #expect(estimated.temperature == Astrophysics.temperature(spectralType: "M3V"))
        #expect(estimated.location == nil)

        let specified = try CentralStar(name: "Measured", spectralType: "G2V", mass: 1.2, radius: 1.3, temperature: 5_900)
        #expect(specified.mass == 1.2)
        #expect(specified.radius == 1.3)
        #expect(specified.temperature == 5_900)
    }

    @Test func unrecognizedTypeThrowsOnlyWhenAnEstimateIsNeeded() throws {
        let error = #expect(throws: PlanetarySystemError.self) {
            try CentralStar(name: "X", spectralType: "??")
        }
        #expect(error?.problems.contains(.unrecognizedSpectralType(star: "X", spectralType: "??")) == true)

        let fullySpecified = try CentralStar(name: "X", spectralType: "??", mass: 2, radius: 3, temperature: 4_000)
        #expect(fullySpecified.mass == 2)
        #expect(fullySpecified.radius == 3)
        #expect(fullySpecified.temperature == 4_000)
    }

    @Test func invalidGivenValuesAreCollectedTogether() {
        let error = #expect(throws: PlanetarySystemError.self) {
            try CentralStar(name: "X", spectralType: "G2V", mass: -1, radius: 0)
        }
        let expected: [PlanetarySystemProblem] = [
            .invalidValue(name: "X", field: "mass", value: -1),
            .invalidValue(name: "X", field: "radius", value: 0),
        ]
        #expect(error?.problems.count == expected.count)
        #expect(Set(error?.problems ?? []) == Set(expected))
    }
}

@Suite struct PlanetarySystemTests {
    @Test func validSystemPreservesOrderAndLooksUpExactNames() throws {
        let system = try fixture()

        #expect(system.name == "Fixture")
        #expect(system.bodies.map(\.name) == ["Earth", "Moon", "Ceres", "Vesta"])
        #expect(system.belts.map(\.name) == ["Kuiper belt", "Asteroid belt"])
        #expect(system.body(named: "Earth") == system.bodies[0])
        #expect(system.body(named: "earth") == nil)
        #expect(system.body(named: "missing") == nil)
    }

    @Test func childrenAreReturnedInInputOrderForEachParent() throws {
        let system = try fixture()
        #expect(system.children(of: .centralStar).map(\.name) == ["Earth", "Ceres", "Vesta"])
        #expect(system.children(of: .body("Earth")).map(\.name) == ["Moon"])
        #expect(system.children(of: .body("unknown")) == [])
    }

    @Test func parentMassesConvertEarthMassesToSolarMasses() throws {
        let system = try fixture()
        #expect(system.mass(of: .centralStar) == 1)
        #expect(system.mass(of: .body("Earth")) == 1 / Astrophysics.earthMassesPerSolarMass)
        #expect(system.mass(of: .body("Vesta")) == nil)
        #expect(system.mass(of: .body("unknown")) == nil)
    }

    @Test func orbitalPeriodUsesGivenOrDerivedPeriodAndReturnsNilForUnknownBody() throws {
        let known = body("Known", orbit: Orbit(distance: 2, period: 123.5))
        let unknownMass = body("Massless", orbit: Orbit(distance: 1))
        let massive = body("Massive", orbit: Orbit(distance: 1), mass: Astrophysics.earthMassesPerSolarMass)
        let system = try PlanetarySystem(name: "Periods", centralStar: .sun, bodies: [known, unknownMass, massive])
        #expect(system.orbitalPeriod(of: known) == 123.5)
        #expect(system.orbitalPeriod(of: unknownMass) == 365.25)
        #expect(system.orbitalPeriod(of: massive) == Astrophysics.orbitalPeriod(semiMajorAxis: 1, totalMass: 2))
        #expect(system.orbitalPeriod(of: body("Outside")) == nil)

        let heavyStar = try CentralStar(name: "Heavy", spectralType: "G2V", mass: 4)
        let aroundHeavyStar = try PlanetarySystem(
            name: "Heavy system",
            centralStar: heavyStar,
            bodies: [body("Planet", orbit: Orbit(distance: 1))]
        )
        #expect(aroundHeavyStar.orbitalPeriod(of: try #require(aroundHeavyStar.body(named: "Planet"))) == 182.625)
    }

    @Test func beltLookupRequiresMatchingParentAndIncludesEdges() throws {
        let planet = body("Planet", orbit: Orbit(distance: 2.2))
        let moon = body("Moon", kind: .moon, parent: .body("Planet"), orbit: Orbit(distance: 2.5, period: 1))
        let outer = body("Outer", orbit: Orbit(distance: 3))
        let system = try PlanetarySystem(
            name: "Belts",
            centralStar: .sun,
            bodies: [planet, moon, outer],
            belts: [
                Belt(name: "Star belt", parent: .centralStar, innerEdge: 2.2, outerEdge: 3),
                Belt(name: "Later star belt", parent: .centralStar, innerEdge: 2, outerEdge: 3.5),
                Belt(name: "Planet belt", parent: .body("Planet"), innerEdge: 2.4, outerEdge: 2.6),
            ]
        )

        #expect(system.belt(containing: planet)?.name == "Star belt")
        #expect(system.belt(containing: moon)?.name == "Planet belt")
        #expect(system.belt(containing: outer)?.name == "Star belt")

        let host = body("Host", kind: .planet, mass: 1)
        let foreignParentBody = body("Foreign child", kind: .moon, parent: .body("Host"), orbit: Orbit(distance: 2.5, period: 1))
        let foreignOnlyRange = try PlanetarySystem(
            name: "Different parent",
            centralStar: .sun,
            bodies: [host, foreignParentBody],
            belts: [Belt(name: "Star belt", parent: .centralStar, innerEdge: 2, outerEdge: 3)]
        )
        #expect(foreignOnlyRange.belt(containing: foreignParentBody) == nil)
    }

    @Test func bodyKindsAndOrbitDefaultsMatchThePublicModel() {
        #expect(Body.Kind.allCases == [.planet, .dwarfPlanet, .moon, .asteroid, .comet])
        #expect(Body.Kind.allCases.map(\.rawValue) == ["planet", "dwarf planet", "moon", "asteroid", "comet"])

        let orbit = Orbit(distance: 2)
        #expect(orbit.period == nil)
        #expect(orbit.eccentricity == 0)
        #expect(orbit.inclination == 0)
        #expect(orbit.startingAngle == 0)
    }
}

private func fixture(centralStar: CentralStar = .sun) throws(PlanetarySystemError) -> PlanetarySystem {
    let earth = body("Earth", kind: .planet, orbit: Orbit(distance: 1), radius: 6_371, mass: 1)
    let moon = body("Moon", kind: .moon, parent: .body("Earth"), orbit: Orbit(distance: 0.00257, period: 27.3), radius: 1_737, mass: 0.0123)
    let ceres = body("Ceres", kind: .dwarfPlanet, orbit: Orbit(distance: 2.77), radius: 470, mass: 0.000157)
    let vesta = body("Vesta", kind: .asteroid, orbit: Orbit(distance: 2.36), radius: 263)
    return try PlanetarySystem(
        name: "Fixture",
        centralStar: centralStar,
        bodies: [earth, moon, ceres, vesta],
        belts: [
            Belt(name: "Kuiper belt", parent: .centralStar, innerEdge: 30, outerEdge: 50),
            Belt(name: "Asteroid belt", parent: .centralStar, innerEdge: 2.2, outerEdge: 3.2),
        ]
    )
}

private func body(
    _ name: String,
    kind: Body.Kind = .planet,
    parent: Parent = .centralStar,
    orbit: Orbit = Orbit(distance: 1),
    radius: Double = 1,
    mass: Double? = nil,
    color: SIMD3<Float>? = nil
) -> Body {
    Body(name: name, kind: kind, parent: parent, orbit: orbit, radius: radius, mass: mass, color: color)
}

private func makeStar(
    id: Int,
    name: String,
    spectralType: String?,
    colorName: String = "Yellow",
    absoluteMagnitude: Double = 5,
    colorIndex: Double? = nil,
    rightAscensionHours: Double = 0,
    distanceLightYears: Double = 4
) -> Star {
    Star(
        id: id,
        name: name,
        apparentMagnitude: 1,
        absoluteMagnitude: absoluteMagnitude,
        spectralType: spectralType,
        colorIndex: colorIndex,
        colorName: colorName,
        rightAscensionHours: rightAscensionHours,
        declinationDegrees: 0,
        distanceLightYears: distanceLightYears
    )
}
