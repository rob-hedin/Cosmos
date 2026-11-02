import Testing
@testable import StarCatalog

@Suite struct PlanetarySystemValidationTests {
    @Test func unknownBodyAndBeltParentsAreReportedWithoutKindRules() {
        let child = makeBody("Child", kind: .planet, parent: .body("Vulcan"))
        let bodyProblems = problems(bodies: [child])
        #expect(containsExactly(bodyProblems, [.unknownParent(name: "Child", parent: "Vulcan")]))

        let belt = Belt(name: "Ring", parent: .body("Vulcan"), innerEdge: 1, outerEdge: 2)
        let beltProblems = problems(belts: [belt])
        #expect(containsExactly(beltProblems, [.unknownParent(name: "Ring", parent: "Vulcan")]))
    }

    @Test func parentLoopsAreReportedOnceWithoutIncludingBodiesThatLeadIntoThem() {
        let a = makeBody("A", kind: .moon, parent: .body("B"), mass: 1)
        let b = makeBody("B", kind: .moon, parent: .body("A"), mass: 1)
        let c = makeBody("C", kind: .planet, parent: .body("A"))
        let found = problems(bodies: [a, b, c])

        #expect(found.filter { if case .parentLoop = $0 { true } else { false } } == [.parentLoop(["A", "B"])])
        #expect(found.contains(.kindRuleBroken(body: "A", kind: .moon, parent: .body("B"))))
        #expect(found.contains(.kindRuleBroken(body: "B", kind: .moon, parent: .body("A"))))
        #expect(found.contains(.kindRuleBroken(body: "C", kind: .planet, parent: .body("A"))))
        #expect(!found.contains { if case .parentLoop(let names) = $0 { names.contains("C") } else { false } })
    }

    @Test func selfParentAndSeparateLoopsAreReported() {
        let selfParent = problems(bodies: [makeBody("Solo", kind: .moon, parent: .body("Solo"), mass: 1)])
        #expect(selfParent.filter { if case .parentLoop = $0 { true } else { false } } == [.parentLoop(["Solo"])])

        let bodies = [
            makeBody("A", kind: .moon, parent: .body("B"), mass: 1),
            makeBody("B", kind: .moon, parent: .body("A"), mass: 1),
            makeBody("C", kind: .moon, parent: .body("D"), mass: 1),
            makeBody("D", kind: .moon, parent: .body("C"), mass: 1),
        ]
        let loops = problems(bodies: bodies).compactMap { problem -> [String]? in
            guard case .parentLoop(let names) = problem else { return nil }
            return names
        }
        #expect(loops.count == 2)
        #expect(loops.contains(["A", "B"]))
        #expect(loops.contains(["C", "D"]))
    }

    @Test(arguments: [-1.0, 0.0, Double.nan, Double.infinity])
    func nonPositiveOrNonFiniteDistanceIsReported(distance: Double) {
        let found = problems(bodies: [makeBody("Bad orbit", orbit: Orbit(distance: distance))])
        #expect(found.count == 1)
        guard case let .some(.invalidDistance(name, value)) = found.first else {
            Issue.record("Expected an invalidDistance problem")
            return
        }
        #expect(name == "Bad orbit")
        #expect(distance.isNaN ? value.isNaN : value == distance)
    }

    @Test func invalidKindRelationshipsAreRejected() {
        let planetHost = makeBody("Planet host", kind: .planet, mass: 1)
        let moonHostMoon = makeBody("Moon host", kind: .moon, parent: .body("Planet host"), mass: 1)
        let cometHost = makeBody("Comet host", kind: .comet, mass: 1)
        let children = [
            makeBody("Star moon", kind: .moon, mass: 1),
            makeBody("Moon of moon", kind: .moon, parent: .body("Moon host"), mass: 1),
            makeBody("Moon of comet", kind: .moon, parent: .body("Comet host"), mass: 1),
            makeBody("Planet of planet", kind: .planet, parent: .body("Planet host")),
        ]
        let found = problems(bodies: [moonHostMoon, cometHost, planetHost] + children)
        let rules = found.filter { if case .kindRuleBroken = $0 { true } else { false } }
        #expect(Set(rules) == Set([
            .kindRuleBroken(body: "Star moon", kind: .moon, parent: .centralStar),
            .kindRuleBroken(body: "Moon of moon", kind: .moon, parent: .body("Moon host")),
            .kindRuleBroken(body: "Moon of comet", kind: .moon, parent: .body("Comet host")),
            .kindRuleBroken(body: "Planet of planet", kind: .planet, parent: .body("Planet host")),
        ]))
    }

    @Test func permittedKindsAndMoonParentsBuildSuccessfully() throws {
        let hosts = [
            makeBody("Planet", kind: .planet, mass: 1),
            makeBody("Dwarf", kind: .dwarfPlanet, mass: 1),
            makeBody("Asteroid", kind: .asteroid, mass: 1),
        ]
        let moons = [
            makeBody("Planet moon", kind: .moon, parent: .body("Planet")),
            makeBody("Dwarf moon", kind: .moon, parent: .body("Dwarf")),
            makeBody("Asteroid moon", kind: .moon, parent: .body("Asteroid")),
        ]
        let starOrbiters = [Body.Kind.planet, .dwarfPlanet, .asteroid, .comet].enumerated().map { index, kind in
            makeBody("Star orbiter \(index)", kind: kind)
        }
        let system = try PlanetarySystem(name: "Accepted", centralStar: .sun, bodies: hosts + moons + starOrbiters)
        #expect(system.bodies.count == 10)
    }

    @Test(arguments: [
        ("radius", 0.0), ("radius", -5.0), ("radius", Double.infinity), ("radius", Double.nan),
        ("mass", 0.0), ("mass", -1.0), ("mass", Double.infinity), ("mass", Double.nan),
        ("period", 0.0), ("period", -1.0), ("period", Double.infinity), ("period", Double.nan),
        ("eccentricity", -0.1), ("eccentricity", 1.0), ("eccentricity", 1.5),
        ("eccentricity", Double.infinity), ("eccentricity", Double.nan),
        ("inclination", Double.infinity), ("inclination", Double.nan),
        ("startingAngle", Double.infinity), ("startingAngle", Double.nan),
    ])
    func outOfRangeBodyValuesAreReported(field: String, value: Double) {
        let orbit = Orbit(
            distance: 1,
            period: field == "period" ? value : nil,
            eccentricity: field == "eccentricity" ? value : 0,
            inclination: field == "inclination" ? value : 0,
            startingAngle: field == "startingAngle" ? value : 0
        )
        let testBody = makeBody(
            "Numeric",
            orbit: orbit,
            radius: field == "radius" ? value : 1,
            mass: field == "mass" ? value : nil
        )
        let found = problems(bodies: [testBody])
        #expect(found.count == 1)
        #expect(hasInvalidValue(found, name: "Numeric", field: field, value: value))
    }

    @Test(arguments: [0.0, 0.99])
    func validEccentricitiesAreAccepted(eccentricity: Double) throws {
        let testBody = makeBody("Valid", orbit: Orbit(distance: 1, eccentricity: eccentricity))
        _ = try PlanetarySystem(name: "Valid", centralStar: .sun, bodies: [testBody])
    }

    @Test func duplicateNamesAreReportedForEachExtraOccurrence() {
        let repeated = problems(bodies: [makeBody("Twin"), makeBody("Twin"), makeBody("Twin")])
        #expect(repeated.filter { $0 == .duplicateName("Twin") }.count == 2)

        let beltName = Belt(name: "Shared", parent: .centralStar, innerEdge: 1, outerEdge: 2)
        let repeatsBelt = problems(bodies: [makeBody("Shared")], belts: [beltName])
        #expect(repeatsBelt.filter { $0 == .duplicateName("Shared") }.count == 1)

        let repeatsStar = problems(bodies: [makeBody("Sun")])
        #expect(repeatsStar.filter { $0 == .duplicateName("Sun") }.count == 1)
    }

    @Test(arguments: [
        (-1.0, 3.0), (2.0, 2.0), (3.0, 2.0), (1.0, Double.infinity),
    ])
    func invalidBeltEdgesAreRejected(inner: Double, outer: Double) {
        let belt = Belt(name: "Bad belt", parent: .centralStar, innerEdge: inner, outerEdge: outer)
        let found = problems(belts: [belt])
        #expect(containsExactly(found, [.invalidBeltEdges(belt: "Bad belt", inner: inner, outer: outer)]))
    }

    @Test func zeroInnerBeltEdgeIsValid() throws {
        let belt = Belt(name: "Valid belt", parent: .centralStar, innerEdge: 0, outerEdge: 1)
        _ = try PlanetarySystem(name: "Valid", centralStar: .sun, bodies: [], belts: [belt])
    }

    @Test func moonNeedsItsParentMassOnlyWhenItsPeriodMustBeDerived() throws {
        let moon = makeBody("Moon", kind: .moon, parent: .body("Planet"))
        let parentWithoutMass = makeBody("Planet", kind: .planet)
        let found = problems(bodies: [parentWithoutMass, moon])
        #expect(containsExactly(found, [.missingParentMass(body: "Moon", parent: "Planet")]))

        let explicitPeriodMoon = makeBody("Moon", kind: .moon, parent: .body("Planet"), orbit: Orbit(distance: 0.01, period: 1))
        _ = try PlanetarySystem(name: "Known period", centralStar: .sun, bodies: [parentWithoutMass, explicitPeriodMoon])

        let parentWithMass = makeBody("Planet", kind: .planet, mass: 1)
        _ = try PlanetarySystem(name: "Known parent mass", centralStar: .sun, bodies: [parentWithMass, moon])
    }

    @Test func validationReturnsTheFullSetOfIndependentProblems() {
        let bodies = [
            makeBody("Loop A", kind: .moon, parent: .body("Loop B"), mass: 1),
            makeBody("Loop B", kind: .moon, parent: .body("Loop A"), mass: 1),
            makeBody("Bad distance", orbit: Orbit(distance: -1)),
            makeBody("Bad kind", kind: .planet, parent: .body("Host")),
            makeBody("Unknown child", parent: .body("Vulcan")),
            makeBody("Host", kind: .planet, mass: 1),
        ]
        let expected: [PlanetarySystemProblem] = [
            .parentLoop(["Loop A", "Loop B"]),
            .kindRuleBroken(body: "Loop A", kind: .moon, parent: .body("Loop B")),
            .kindRuleBroken(body: "Loop B", kind: .moon, parent: .body("Loop A")),
            .invalidDistance(body: "Bad distance", distance: -1),
            .kindRuleBroken(body: "Bad kind", kind: .planet, parent: .body("Host")),
            .unknownParent(name: "Unknown child", parent: "Vulcan"),
        ]
        #expect(containsExactly(problems(bodies: bodies), expected))
    }

    @Test func eachProblemHasAUsefulDescriptionAndErrorListsOneProblemPerLine() {
        let samples: [(PlanetarySystemProblem, String)] = [
            (.duplicateName("Earth"), "Earth"),
            (.unknownParent(name: "Moon", parent: "Earth"), "Moon"),
            (.parentLoop(["A", "B"]), "A"),
            (.invalidDistance(body: "Mercury", distance: -1), "Mercury"),
            (.kindRuleBroken(body: "Moon", kind: .moon, parent: .centralStar), "Moon"),
            (.invalidValue(name: "Earth", field: "radius", value: 0), "Earth"),
            (.invalidBeltEdges(belt: "Asteroid belt", inner: 3, outer: 2), "Asteroid belt"),
            (.missingParentMass(body: "Moon", parent: "Earth"), "Moon"),
            (.unrecognizedSpectralType(star: "X", spectralType: "??"), "X"),
            (.unknownCatalogStar("Vulcan"), "Vulcan"),
            (.unknownKind(body: "Jupiter", value: "gas giant"), "Jupiter"),
            (.invalidColor(body: "Earth", value: "red"), "Earth"),
        ]

        for (problem, name) in samples {
            #expect(!problem.description.isEmpty)
            #expect(problem.description.contains(name))
        }

        let error = PlanetarySystemError(problems: samples.map(\.0))
        let lines = error.description.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == samples.count)
        #expect(lines == samples.map { Substring($0.0.description) })
    }

    @Test func invalidCatalogStarValuesJoinBodyProblemsAndValidCatalogStarsBuild() throws {
        let badRow = makeStar(id: 80, name: "Dim Star", spectralType: "K1V", absoluteMagnitude: 100_000)
        let badCentralStar = CentralStar(catalogStar: badRow)
        try #require(badCentralStar.radius == 0)

        let found = problems(
            centralStar: badCentralStar,
            bodies: [makeBody("Bad orbit", orbit: Orbit(distance: -1))]
        )
        #expect(containsExactly(found, [
            .invalidValue(name: "Dim Star", field: "radius", value: 0),
            .invalidDistance(body: "Bad orbit", distance: -1),
        ]))

        let ordinary = CentralStar(catalogStar: makeStar(id: 81, name: "Ordinary Star", spectralType: "K1V"))
        _ = try PlanetarySystem(name: "Valid star", centralStar: ordinary, bodies: [])
    }

    @Test(arguments: [
        ("red", -0.01 as Float), ("red", 1.01), ("red", Float.nan), ("red", Float.infinity), ("red", -Float.infinity),
        ("green", -0.01), ("green", 1.01), ("green", Float.nan), ("green", Float.infinity), ("green", -Float.infinity),
        ("blue", -0.01), ("blue", 1.01), ("blue", Float.nan), ("blue", Float.infinity), ("blue", -Float.infinity),
    ])
    func outOfRangeSwiftColorComponentIsReported(component: String, value: Float) {
        let color: SIMD3<Float>
        switch component {
        case "red": color = SIMD3(value, 0.5, 0.5)
        case "green": color = SIMD3(0.5, value, 0.5)
        default: color = SIMD3(0.5, 0.5, value)
        }
        let found = problems(bodies: [makeBody("Colored", color: color)])
        #expect(found.count == 1)
        #expect(hasInvalidValue(found, name: "Colored", field: "color.\(component)", value: Double(value)))
    }

    @Test func twoBadColorComponentsProduceTwoProblems() {
        let found = problems(bodies: [makeBody("Colored", color: SIMD3(-0.1, 1.1, 0.5))])
        #expect(found.count == 2)
        #expect(found.contains(.invalidValue(name: "Colored", field: "color.red", value: Double(Float(-0.1)))))
        #expect(found.contains(.invalidValue(name: "Colored", field: "color.green", value: Double(Float(1.1)))))
    }

    @Test(arguments: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 1), SIMD3<Float>(0, 0.5, 1)])
    func inRangeSwiftColorsAreAccepted(color: SIMD3<Float>) throws {
        _ = try PlanetarySystem(name: "Color", centralStar: .sun, bodies: [makeBody("Colored", color: color)])
    }
}

private func problems(
    centralStar: CentralStar = .sun,
    bodies: [Body] = [],
    belts: [Belt] = []
) -> [PlanetarySystemProblem] {
    do {
        _ = try PlanetarySystem(name: "Validation", centralStar: centralStar, bodies: bodies, belts: belts)
        return []
    } catch {
        return error.problems
    }
}

private func containsExactly(_ actual: [PlanetarySystemProblem], _ expected: [PlanetarySystemProblem]) -> Bool {
    actual.count == expected.count && Set(actual) == Set(expected)
}

private func hasInvalidValue(
    _ problems: [PlanetarySystemProblem],
    name: String,
    field: String,
    value expectedValue: Double
) -> Bool {
    problems.contains { problem in
        guard case .invalidValue(let problemName, let problemField, let value) = problem,
              problemName == name, problemField == field else { return false }
        return expectedValue.isNaN ? value.isNaN : value == expectedValue
    }
}

private func makeBody(
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
    absoluteMagnitude: Double = 5
) -> Star {
    Star(
        id: id,
        name: name,
        apparentMagnitude: 1,
        absoluteMagnitude: absoluteMagnitude,
        spectralType: spectralType,
        colorName: "Yellow",
        rightAscensionHours: 0,
        declinationDegrees: 0,
        distanceLightYears: 4
    )
}
