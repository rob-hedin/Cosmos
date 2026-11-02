import Foundation

extension PlanetarySystem {
    /// Loads a system from JSON. `catalog` resolves `centralStar.catalogName`; "Sun" and "Sol"
    /// resolve to `CentralStar.sun` with any catalog, including the default empty one.
    ///
    /// ```json
    /// {
    ///   "name": "Solar System",
    ///   "centralStar": { "catalogName": "Sun" },
    ///   "bodies": [
    ///     { "name": "Earth", "kind": "planet", "parent": "Sun", "distance": 1.0, "radius": 6371.0,
    ///       "mass": 1.0, "period": 365.256, "color": "#4F7FD0",
    ///       "eccentricity": 0.0167, "inclination": 0.0, "startingAngle": 100.0 }
    ///   ],
    ///   "belts": [ { "name": "Asteroid belt", "parent": "Sun", "innerEdge": 2.2, "outerEdge": 3.2 } ]
    /// }
    /// ```
    ///
    /// `centralStar` is either `{ "catalogName": String }` or
    /// `{ "name": String, "spectralType": String, "mass"?, "radius"?, "temperature"? }`; `catalogName`
    /// wins if both are present. `bodies` and `belts` are optional. A `parent` equal to the Central
    /// Star's name (exactly, case-sensitive) means the Central Star; anything else names a Body.
    /// `kind` is one of "planet", "dwarf planet", "moon", "asteroid" or "comet". `color` is "#RRGGBB".
    /// Units are as in `PlanetarySystem`: AU, km, Earth masses, days and degrees.
    ///
    /// Throws `DecodingError` for malformed JSON or a missing or mistyped required field, and
    /// `PlanetarySystemError` listing every content problem, including the ones only JSON can have.
    public init(json: Data, catalog: StarCatalog = StarCatalog(stars: [])) throws {
        let raw = try JSONDecoder().decode(RawSystem.self, from: json)
        var problems: [PlanetarySystemProblem] = []

        let centralStar: CentralStar?
        let starName: String
        switch raw.centralStar {
        case .catalog(let catalogName):
            centralStar = Self.resolve(catalogName: catalogName, in: catalog)
            // Parents name the star the catalog found ("Sol" finds "Sun"). If nothing matched, a
            // placeholder keeps Bodies that name the star from being reported as unknown Parents.
            starName = centralStar?.name ?? catalogName
            if centralStar == nil { problems.append(.unknownCatalogStar(catalogName)) }
        case .described(let name, let spectralType, let mass, let radius, let temperature):
            starName = name
            do {
                centralStar = try CentralStar(
                    name: name, spectralType: spectralType, mass: mass, radius: radius, temperature: temperature
                )
            } catch {
                centralStar = nil
                problems += error.problems
            }
        }

        var candidates: [BodyCandidate] = []
        for rawBody in raw.bodies ?? [] {
            let kind = Body.Kind(rawValue: rawBody.kind)
            if kind == nil { problems.append(.unknownKind(body: rawBody.name, value: rawBody.kind)) }

            var color: SIMD3<Float>?
            if let text = rawBody.color {
                color = Self.parseHexColor(text)
                if color == nil { problems.append(.invalidColor(body: rawBody.name, value: text)) }
            }

            candidates.append(BodyCandidate(
                name: rawBody.name,
                kind: kind,
                parent: rawBody.parent == starName ? .centralStar : .body(rawBody.parent),
                orbit: Orbit(
                    distance: rawBody.distance,
                    period: rawBody.period,
                    eccentricity: rawBody.eccentricity ?? 0,
                    inclination: rawBody.inclination ?? 0,
                    startingAngle: rawBody.startingAngle ?? 0
                ),
                radius: rawBody.radius,
                mass: rawBody.mass,
                color: color
            ))
        }

        let belts = (raw.belts ?? []).map { rawBelt in
            Belt(
                name: rawBelt.name,
                parent: rawBelt.parent == starName ? .centralStar : .body(rawBelt.parent),
                innerEdge: rawBelt.innerEdge,
                outerEdge: rawBelt.outerEdge
            )
        }

        problems += Self.validate(
            starName: starName,
            starValues: centralStar.map(StarValues.init),
            bodies: candidates,
            belts: belts
        )
        guard problems.isEmpty, let centralStar else { throw PlanetarySystemError(problems: problems) }

        // Nothing was reported, so every Body has a Kind.
        let bodies = candidates.compactMap { candidate in
            candidate.kind.map {
                Body(
                    name: candidate.name, kind: $0, parent: candidate.parent, orbit: candidate.orbit,
                    radius: candidate.radius, mass: candidate.mass, color: candidate.color
                )
            }
        }
        self.init(validatedName: raw.name, centralStar: centralStar, bodies: bodies, belts: belts)
    }

    /// Reads the file and calls `init(json:catalog:)`.
    public init(contentsOf url: URL, catalog: StarCatalog = StarCatalog(stars: [])) throws {
        try self.init(json: Data(contentsOf: url), catalog: catalog)
    }

    /// The built-in Solar System from the bundled `solar-system.json`. Its Central Star is the
    /// catalog's Sun (`CentralStar.sun`).
    /// Throws `StarCatalogError.resourceNotFound` when the resource is missing.
    public static func solarSystem() throws -> PlanetarySystem {
        guard let url = Bundle.module.url(forResource: "solar-system", withExtension: "json") else {
            throw StarCatalogError.resourceNotFound
        }
        return try PlanetarySystem(contentsOf: url)
    }

    /// "Sun" and "Sol" are the Sun; any other match must be a row in the catalog.
    private static func resolve(catalogName: String, in catalog: StarCatalog) -> CentralStar? {
        guard let location = catalog.location(named: catalogName) else { return nil }
        guard let starID = location.starID else { return .sun }
        return catalog.star(withID: starID).map(CentralStar.init(catalogStar:))
    }

    /// "#RRGGBB" in either case, as sRGB components in 0...1. Nil for anything else.
    private static func parseHexColor(_ text: String) -> SIMD3<Float>? {
        let bytes = Array(text.utf8)
        guard bytes.count == 7, bytes[0] == UInt8(ascii: "#") else { return nil }
        var digits: [Int] = []
        for byte in bytes.dropFirst() {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digits.append(Int(byte - UInt8(ascii: "0")))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digits.append(Int(byte - UInt8(ascii: "a")) + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digits.append(Int(byte - UInt8(ascii: "A")) + 10)
            default: return nil
            }
        }
        func component(_ high: Int, _ low: Int) -> Float {
            Float(Double(high * 16 + low) / 255)
        }
        return SIMD3(component(digits[0], digits[1]), component(digits[2], digits[3]), component(digits[4], digits[5]))
    }
}

// MARK: - Raw JSON records

private struct RawSystem: Decodable {
    let name: String
    let centralStar: RawCentralStar
    let bodies: [RawBody]?
    let belts: [RawBelt]?
}

private enum RawCentralStar: Decodable {
    case catalog(String)
    case described(name: String, spectralType: String, mass: Double?, radius: Double?, temperature: Double?)

    private enum CodingKeys: String, CodingKey {
        case catalogName, name, spectralType, mass, radius, temperature
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let catalogName = try container.decodeIfPresent(String.self, forKey: .catalogName) {
            self = .catalog(catalogName)
        } else {
            self = .described(
                name: try container.decode(String.self, forKey: .name),
                spectralType: try container.decode(String.self, forKey: .spectralType),
                mass: try container.decodeIfPresent(Double.self, forKey: .mass),
                radius: try container.decodeIfPresent(Double.self, forKey: .radius),
                temperature: try container.decodeIfPresent(Double.self, forKey: .temperature)
            )
        }
    }
}

private struct RawBody: Decodable {
    let name: String
    let kind: String
    let parent: String
    let distance: Double
    let radius: Double
    let mass: Double?
    let period: Double?
    let color: String?
    let eccentricity: Double?
    let inclination: Double?
    let startingAngle: Double?
}

private struct RawBelt: Decodable {
    let name: String
    let parent: String
    let innerEdge: Double
    let outerEdge: Double
}
