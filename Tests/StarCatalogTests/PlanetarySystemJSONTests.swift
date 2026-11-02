import Foundation
import Testing
@testable import StarCatalog

@Suite struct PlanetarySystemJSONTests {
    @Test func jsonWithEveryOptionalBodyFieldMatchesSwiftValueConstruction() throws {
        let source = """
        {
          "name": "JSON System",
          "centralStar": { "name": "Helios", "spectralType": "G2V", "mass": 1.2, "radius": 1.1, "temperature": 5900 },
          "bodies": [
            { "name": "Ember", "kind": "planet", "parent": "Helios", "distance": 1.5, "radius": 2000,
              "mass": 0.8, "period": 500, "color": "#FF8000", "eccentricity": 0.2, "inclination": 4,
              "startingAngle": 10 },
            { "name": "Cinder", "kind": "moon", "parent": "Ember", "distance": 0.01, "radius": 500, "mass": 0.1,
              "period": 2 }
          ],
          "belts": [{ "name": "Debris belt", "parent": "Helios", "innerEdge": 2, "outerEdge": 3 }]
        }
        """
        let parsed = try PlanetarySystem(json: Data(source.utf8))
        let centralStar = try CentralStar(name: "Helios", spectralType: "G2V", mass: 1.2, radius: 1.1, temperature: 5_900)
        let expected = try PlanetarySystem(
            name: "JSON System",
            centralStar: centralStar,
            bodies: [
                Body(
                    name: "Ember",
                    kind: .planet,
                    parent: .centralStar,
                    orbit: Orbit(distance: 1.5, period: 500, eccentricity: 0.2, inclination: 4, startingAngle: 10),
                    radius: 2_000,
                    mass: 0.8,
                    color: SIMD3(1, Float(128.0 / 255.0), 0)
                ),
                Body(name: "Cinder", kind: .moon, parent: .body("Ember"), orbit: Orbit(distance: 0.01, period: 2), radius: 500, mass: 0.1),
            ],
            belts: [Belt(name: "Debris belt", parent: .centralStar, innerEdge: 2, outerEdge: 3)]
        )

        #expect(parsed == expected)
        let orange = try #require(parsed.body(named: "Ember")?.color)
        #expect(abs(orange.x - 1) < 1e-6)
        #expect(abs(orange.y - Float(128.0 / 255.0)) < 1e-6)
        #expect(abs(orange.z) < 1e-6)
    }

    @Test func optionalCollectionsDefaultToEmpty() throws {
        let system = try PlanetarySystem(json: Data(#"{"name":"Empty","centralStar":{"catalogName":"Sun"}}"#.utf8))
        #expect(system.bodies == [])
        #expect(system.belts == [])
    }

    @Test func parentNameEqualToCentralStarMapsToCentralStar() throws {
        let source = #"{"name":"Parents","centralStar":{"name":"Helios","spectralType":"G2V"},"bodies":[{"name":"Host","kind":"planet","parent":"Helios","distance":1,"radius":1,"mass":1},{"name":"Moon","kind":"moon","parent":"Host","distance":0.1,"radius":1,"period":1}]}"#
        let system = try PlanetarySystem(json: Data(source.utf8))
        #expect(system.body(named: "Host")?.parent == .centralStar)
        #expect(system.body(named: "Moon")?.parent == .body("Host"))
    }

    @Test func catalogStarsAndSunAliasesResolveThroughTheInjectedCatalog() throws {
        let star = makeStar(id: 17, name: "Rigil Kentaurus", spectralType: "K1V")
        let catalog = StarCatalog(stars: [star])
        let source = #"{"name":"Catalog system","centralStar":{"catalogName":"Rigil Kentaurus","name":"Ignored name","spectralType":"??"}}"#
        let system = try PlanetarySystem(json: Data(source.utf8), catalog: catalog)
        #expect(system.centralStar == CentralStar(catalogStar: star))

        for alias in ["Sun", "sol"] {
            let aliasJSON = """
            {"name":"Solar","centralStar":{"catalogName":"\(alias)"}}
            """
            let solar = try PlanetarySystem(json: Data(aliasJSON.utf8))
            #expect(solar.centralStar == .sun)
        }
    }

    @Test func unknownCatalogStarIsReportedWithBodyProblems() {
        let source = #"{"name":"Unknown","centralStar":{"catalogName":"Vulcan"},"bodies":[{"name":"Lost","kind":"planet","parent":"Nowhere","distance":1,"radius":1},{"name":"Placeholder child","kind":"planet","parent":"Vulcan","distance":1,"radius":1}]}"#
        let error = #expect(throws: PlanetarySystemError.self) {
            try PlanetarySystem(json: Data(source.utf8))
        }
        #expect(error?.problems.contains(.unknownCatalogStar("Vulcan")) == true)
        #expect(error?.problems.contains(.unknownParent(name: "Lost", parent: "Nowhere")) == true)
        #expect(error?.problems.contains(.unknownParent(name: "Placeholder child", parent: "Vulcan")) == false)
    }

    @Test(arguments: ["red", "#12345"])
    func invalidHexColorIsReported(bodyColor: String) {
        let source = """
        {"name":"Colors","centralStar":{"catalogName":"Sun"},"bodies":[
          {"name":"Earth","kind":"planet","parent":"Sun","distance":1,"radius":1,"color":"\(bodyColor)"}
        ]}
        """
        let error = #expect(throws: PlanetarySystemError.self) {
            try PlanetarySystem(json: Data(source.utf8))
        }
        #expect(error?.problems.contains(.invalidColor(body: "Earth", value: bodyColor)) == true)
    }

    @Test func jsonContentProblemsAreAggregated() {
        let source = #"{"name":"Bad input","centralStar":{"catalogName":"Sun"},"bodies":[{"name":"Unknown kind","kind":"gas giant","parent":"Sun","distance":1,"radius":1},{"name":"Bad color","kind":"planet","parent":"Sun","distance":1,"radius":1,"color":"red"},{"name":"Bad distance","kind":"asteroid","parent":"Sun","distance":-1,"radius":1},{"name":"Lost","kind":"planet","parent":"Vulcan","distance":1,"radius":1}]}"#
        let error = #expect(throws: PlanetarySystemError.self) {
            try PlanetarySystem(json: Data(source.utf8))
        }
        let expected: [PlanetarySystemProblem] = [
            .unknownKind(body: "Unknown kind", value: "gas giant"),
            .invalidColor(body: "Bad color", value: "red"),
            .invalidDistance(body: "Bad distance", distance: -1),
            .unknownParent(name: "Lost", parent: "Vulcan"),
        ]
        #expect(error?.problems.count == expected.count)
        #expect(Set(error?.problems ?? []) == Set(expected))
    }

    @Test func unknownKindStillResolvesAsAParentWithoutKindRuleErrors() {
        let source = #"{"name":"Unknown kind parent","centralStar":{"catalogName":"Sun"},"bodies":[{"name":"Unclassified","kind":"gas giant","parent":"Sun","distance":1,"radius":1,"mass":1},{"name":"Moon","kind":"moon","parent":"Unclassified","distance":0.1,"radius":1,"period":1}]}"#
        let error = #expect(throws: PlanetarySystemError.self) {
            try PlanetarySystem(json: Data(source.utf8))
        }
        #expect(error?.problems == [.unknownKind(body: "Unclassified", value: "gas giant")])
    }

    @Test func unknownScratchSpectralTypeJoinsOtherJsonProblems() {
        let source = #"{"name":"Bad star","centralStar":{"name":"X","spectralType":"??"},"bodies":[{"name":"Colored","kind":"planet","parent":"X","distance":1,"radius":1,"color":"orange"}]}"#
        let error = #expect(throws: PlanetarySystemError.self) {
            try PlanetarySystem(json: Data(source.utf8))
        }
        #expect(error?.problems.contains(.unrecognizedSpectralType(star: "X", spectralType: "??")) == true)
        #expect(error?.problems.contains(.invalidColor(body: "Colored", value: "orange")) == true)
    }

    @Test func invalidCatalogStarIsMergedWithJsonOnlyProblems() throws {
        let badStar = makeStar(id: 91, name: "Dim Star", spectralType: "K1V", absoluteMagnitude: 100_000)
        let catalog = StarCatalog(stars: [badStar])
        let source = #"{"name":"Bad catalog system","centralStar":{"catalogName":"Dim Star"},"bodies":[{"name":"Unknown","kind":"gas giant","parent":"Dim Star","distance":1,"radius":1}]}"#

        let centralStar = CentralStar(catalogStar: badStar)
        #expect(centralStar.radius == 0)
        let error = #expect(throws: PlanetarySystemError.self) {
            try PlanetarySystem(json: Data(source.utf8), catalog: catalog)
        }
        #expect(error?.problems.contains(.invalidValue(name: "Dim Star", field: "radius", value: 0)) == true)
        #expect(error?.problems.contains(.unknownKind(body: "Unknown", value: "gas giant")) == true)
    }

    @Test(arguments: ["not JSON", #"{"name":"Missing distance","centralStar":{"catalogName":"Sun"},"bodies":[{"name":"Earth","kind":"planet","parent":"Sun","radius":1}]}"#])
    func malformedJsonThrowsDecodingError(source: String) {
        do {
            _ = try PlanetarySystem(json: Data(source.utf8))
            Issue.record("Expected malformed JSON to throw")
        } catch {
            #expect(error is DecodingError)
            #expect(!(error is PlanetarySystemError))
        }
    }

    @Test func missingFileThrowsAFileError() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("planetary-system-never-created-\(UUID().uuidString).json")
        do {
            _ = try PlanetarySystem(contentsOf: url)
            Issue.record("Expected the missing file to throw")
        } catch {
            #expect(!(error is PlanetarySystemError))
        }
    }
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
        rightAscensionHours: 2,
        declinationDegrees: 10,
        distanceLightYears: 4
    )
}
