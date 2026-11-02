import Foundation
import Testing
@testable import StarCatalog

@Suite struct PlanetarySystemTests {
    let catalog: StarCatalog
    let solar: PlanetarySystem

    init() throws {
        catalog = try StarCatalog.bundled()
        solar = try PlanetarySystem.solarSystem(catalog: catalog)
    }

    private func planet(_ name: String, _ distance: Double, parent: String = "Star", kind: BodyKind = .planet) -> Body {
        Body(name: name, kind: kind, parent: parent, orbit: Orbit(distanceAU: distance), radiusKilometers: 1000, massEarths: 1)
    }

    private func problems(_ spec: PlanetarySystemSpec) -> [PlanetarySystemProblem] {
        do {
            _ = try PlanetarySystem(spec, catalog: catalog)
            return []
        } catch let error as PlanetarySystemError {
            return error.problems
        } catch {
            Issue.record("Unexpected error \(error)")
            return []
        }
    }

    // MARK: Built-in Solar System

    @Test func solarSystemIsTiedToTheCatalogSun() {
        #expect(solar.star.catalogLocation == .sun)
        #expect(solar.star.massSolar == 1)
        #expect(solar.star.temperatureKelvin == Astrophysics.solarTemperature)
    }

    @Test func solarSystemHasTheAgreedBodies() {
        let planets = solar.bodies.filter { $0.kind == .planet }.map(\.name)
        #expect(planets == ["Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"])
        #expect(Set(solar.bodies.filter { $0.kind == .dwarfPlanet }.map(\.name))
            == ["Ceres", "Pluto", "Eris", "Haumea", "Makemake"])
        #expect(Set(solar.bodies.filter { $0.kind == .moon }.map(\.name))
            == ["Moon", "Io", "Europa", "Ganymede", "Callisto", "Titan", "Triton", "Charon"])
        #expect(!solar.bodies.contains { $0.kind == .comet })
        #expect(solar.belts.map(\.name) == ["Asteroid belt", "Kuiper belt"])
    }

    @Test func periodsComeFromKeplersThirdLaw() throws {
        let earth = try #require(solar.body(named: "Earth"))
        #expect(abs(solar.periodDays(of: earth) - 365.25) < 1)
        let jupiter = try #require(solar.body(named: "Jupiter"))
        #expect(abs(solar.periodDays(of: jupiter) - 4332.6) < 5)
        let moon = try #require(solar.body(named: "Moon"))
        #expect(abs(solar.periodDays(of: moon) - 27.32) < 0.2)
    }

    @Test func moonsNestUnderTheirPlanet() throws {
        #expect(solar.bodies(orbiting: "Jupiter").map(\.name) == ["Io", "Europa", "Ganymede", "Callisto"])
        let charon = try #require(solar.body(named: "Charon"))
        #expect(solar.parentBody(of: charon)?.name == "Pluto")
        let earth = try #require(solar.body(named: "Earth"))
        #expect(solar.parentBody(of: earth) == nil)
    }

    @Test func ceresLiesWithinTheAsteroidBelt() throws {
        func belt(_ name: String) throws -> String? {
            solar.belt(containing: try #require(solar.body(named: name)))?.name
        }
        #expect(try belt("Ceres") == "Asteroid belt")
        #expect(try belt("Pluto") == "Kuiper belt")
        #expect(try belt("Earth") == nil)
        #expect(try belt("Eris") == nil)
    }

    @Test func solarSystemLoadsWithoutTheCatalog() throws {
        #expect(try PlanetarySystem.solarSystem().star.catalogLocation == .sun)
    }

    // MARK: Central Star

    @Test func catalogStarsFillInTheirOwnValues() throws {
        let spec = PlanetarySystemSpec(star: CentralStarSpec(name: "Proxima Centauri"), bodies: [planet("b", 0.0485, parent: "Proxima Centauri")])
        let system = try PlanetarySystem(spec, catalog: catalog)
        let proxima = try #require(catalog.star(named: "Proxima Centauri"))
        #expect(system.star.catalogLocation?.starID == proxima.id)
        #expect(system.star.temperatureKelvin == proxima.temperature)
        #expect(system.star.massSolar < 0.5)
    }

    @Test func givenStarValuesOverrideTheCatalog() throws {
        let spec = PlanetarySystemSpec(star: CentralStarSpec(name: "Proxima Centauri", massSolar: 0.122))
        #expect(try PlanetarySystem(spec, catalog: catalog).star.massSolar == 0.122)
    }

    @Test func starsFromScratchAreEstimatedFromTheirSpectralType() throws {
        let spec = PlanetarySystemSpec(star: CentralStarSpec(name: "Nowhere", spectralType: "K2V"))
        let star = try PlanetarySystem(spec, catalog: catalog).star
        #expect(star.catalogLocation == nil)
        #expect(star.massSolar == 0.75)
        #expect(star.temperatureKelvin == 4_400)
    }

    @Test func starsFromScratchNeedAUsableSpectralType() {
        #expect(problems(PlanetarySystemSpec(star: CentralStarSpec(name: "Nowhere"))) == [.starNeedsSpectralType("Nowhere")])
        #expect(problems(PlanetarySystemSpec(star: CentralStarSpec(name: "Nowhere", spectralType: "??"))) == [.unknownSpectralType("??")])
    }

    // MARK: Checks

    private var star: CentralStarSpec { CentralStarSpec(name: "Star", spectralType: "G2V") }

    @Test func orbitsWithOnlyADistanceAreAccepted() throws {
        let system = try PlanetarySystem(PlanetarySystemSpec(star: star, bodies: [planet("A", 1)]))
        #expect(abs(system.periodDays(of: system.bodies[0]) - 365.25) < 1)
    }

    @Test func givenPeriodsAreKept() throws {
        var body = planet("A", 1)
        body.orbit.periodDays = 100
        let system = try PlanetarySystem(PlanetarySystemSpec(star: star, bodies: [body]))
        #expect(system.periodDays(of: body) == 100)
    }

    @Test func everyProblemIsReportedAtOnce() {
        var bad = planet("A", -1)
        bad.radiusKilometers = 0
        bad.orbit.eccentricity = 1
        bad.color = "red"
        let found = problems(PlanetarySystemSpec(star: star, bodies: [bad, planet("B", 1, parent: "Nowhere")]))
        #expect(found == [
            .nonPositiveDistance("A"),
            .nonPositiveRadius("A"),
            .eccentricityOutOfRange("A"),
            .invalidColor(body: "A", color: "red"),
            .unknownParent(body: "B", parent: "Nowhere"),
        ])
    }

    @Test func namesMustBeUnique() {
        let found = problems(PlanetarySystemSpec(star: star, bodies: [planet("A", 1), planet("A", 2), planet("Star", 3)]))
        #expect(found == [.duplicateName("A"), .duplicateName("Star")])
    }

    @Test func kindRulesAreEnforced() {
        let found = problems(PlanetarySystemSpec(star: star, bodies: [
            planet("P", 1),
            planet("M", 0.01, parent: "Star", kind: .moon),
            planet("Q", 0.01, parent: "P", kind: .planet),
            planet("Moonmoon", 0.001, parent: "Lunar", kind: .moon),
            planet("Lunar", 0.002, parent: "P", kind: .moon),
        ]))
        #expect(found == [
            .kindCannotOrbit(body: "M", kind: .moon, parent: "Star"),
            .kindCannotOrbit(body: "Q", kind: .planet, parent: "P"),
            .kindCannotOrbit(body: "Moonmoon", kind: .moon, parent: "Lunar"),
        ])
    }

    @Test func asteroidsMayHaveMoons() throws {
        let spec = PlanetarySystemSpec(star: star, bodies: [
            planet("Didymos", 1.64, kind: .asteroid),
            planet("Dimorphos", 0.0000079, parent: "Didymos", kind: .moon),
        ])
        #expect(try PlanetarySystem(spec).bodies.count == 2)
    }

    @Test func loopsAreRejected() {
        let found = problems(PlanetarySystemSpec(star: star, bodies: [planet("A", 1, parent: "B"), planet("B", 1, parent: "A")]))
        #expect(found.count == 2)
        #expect(found.allSatisfy { if case .kindCannotOrbit = $0 { true } else { false } })
    }

    @Test func moonsNeedAPeriodOrAParentMass() {
        var parent = planet("P", 1)
        parent.massEarths = nil
        let found = problems(PlanetarySystemSpec(star: star, bodies: [parent, planet("M", 0.01, parent: "P", kind: .moon)]))
        #expect(found == [.periodNeedsParentMass(body: "M", parent: "P")])
    }

    @Test func beltsAreChecked() {
        let found = problems(PlanetarySystemSpec(star: star, belts: [
            Belt(name: "Backwards", parent: "Star", innerEdgeAU: 3, outerEdgeAU: 2),
            Belt(name: "Lost", parent: "Nowhere", innerEdgeAU: 1, outerEdgeAU: 2),
        ]))
        #expect(found == [.invalidBeltEdges("Backwards"), .unknownBeltParent(belt: "Lost", parent: "Nowhere")])
    }

    // MARK: JSON

    @Test func minimalJSONDecodes() throws {
        let json = Data("""
        {"star": {"name": "Star", "spectralType": "M4V"},
         "bodies": [{"name": "b", "kind": "planet", "parent": "Star", "orbit": {"distanceAU": 0.05}, "radiusKilometers": 7000}]}
        """.utf8)
        let system = try PlanetarySystem(json: json)
        #expect(system.bodies.first?.orbit.eccentricity == nil)
        #expect(system.belts.isEmpty)
    }

    @Test func specsRoundTripThroughJSON() throws {
        let spec = PlanetarySystemSpec(star: star, bodies: [planet("A", 1)], belts: [Belt(name: "B", parent: "Star", innerEdgeAU: 2, outerEdgeAU: 3)])
        let decoded = try JSONDecoder().decode(PlanetarySystemSpec.self, from: JSONEncoder().encode(spec))
        #expect(decoded == spec)
    }
}
