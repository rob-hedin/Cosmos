import Foundation

/// One thing wrong with a `PlanetarySystemSpec`. Building a system reports every problem at once.
public enum PlanetarySystemProblem: Error, Sendable, Hashable, CustomStringConvertible {
    case emptyName
    /// Two of the star and Bodies share a name, or two Belts do.
    case duplicateName(String)
    /// The star isn't in the catalog and has no spectral type to estimate it from.
    case starNeedsSpectralType(String)
    case unknownSpectralType(String)
    /// A star value given as zero or less: "massSolar", "radiusSolar" or "temperatureKelvin".
    case nonPositiveStarValue(String)
    case unknownParent(body: String, parent: String)
    /// A Kind rule is broken: a moon must orbit a planet, dwarf planet or asteroid, and every
    /// other Kind must orbit the Central Star. This also catches loops, such as A orbiting B
    /// while B orbits A.
    case kindCannotOrbit(body: String, kind: BodyKind, parent: String)
    case nonPositiveDistance(String)
    case nonPositiveRadius(String)
    case nonPositiveMass(String)
    case nonPositivePeriod(String)
    /// Eccentricity must be at least 0 and less than 1.
    case eccentricityOutOfRange(String)
    /// The Body gives no period, and its Parent Body gives no mass to work one out from.
    case periodNeedsParentMass(body: String, parent: String)
    case invalidColor(body: String, color: String)
    /// A Belt's inner edge must be at least 0 and its outer edge beyond it.
    case invalidBeltEdges(String)
    case unknownBeltParent(belt: String, parent: String)

    public var description: String {
        switch self {
        case .emptyName: "A name is empty."
        case .duplicateName(let name): "\"\(name)\" is used more than once."
        case .starNeedsSpectralType(let name): "\"\(name)\" isn't in the catalog, so it needs a spectral type."
        case .unknownSpectralType(let type): "Spectral type \"\(type)\" has no class letter (O, B, A, F, G, K, M, L, T or D)."
        case .nonPositiveStarValue(let field): "The star's \(field) must be greater than 0."
        case .unknownParent(let body, let parent): "\"\(body)\" orbits \"\(parent)\", which isn't in the system."
        case .kindCannotOrbit(let body, let kind, let parent): "\"\(body)\" is a \(kind.rawValue), so it can't orbit \"\(parent)\"."
        case .nonPositiveDistance(let body): "\"\(body)\" needs a distance greater than 0."
        case .nonPositiveRadius(let body): "\"\(body)\" needs a radius greater than 0."
        case .nonPositiveMass(let body): "\"\(body)\" has a mass of 0 or less."
        case .nonPositivePeriod(let body): "\"\(body)\" has a period of 0 or less."
        case .eccentricityOutOfRange(let body): "\"\(body)\" needs an eccentricity from 0 up to, but not including, 1."
        case .periodNeedsParentMass(let body, let parent): "\"\(body)\" needs a period, or \"\(parent)\" needs a mass."
        case .invalidColor(let body, let color): "\"\(body)\" has color \"\(color)\"; use \"#RRGGBB\"."
        case .invalidBeltEdges(let belt): "\"\(belt)\" needs an inner edge of 0 or more and an outer edge beyond it."
        case .unknownBeltParent(let belt, let parent): "\"\(belt)\" circles \"\(parent)\", which isn't in the system."
        }
    }
}

/// Thrown when a `PlanetarySystemSpec` can't be built. Lists every problem found.
public struct PlanetarySystemError: Error, Sendable, Hashable, CustomStringConvertible {
    public let problems: [PlanetarySystemProblem]

    public var description: String {
        problems.map(\.description).joined(separator: "\n")
    }
}

/// The Central Star with every value filled in.
public struct CentralStar: Sendable, Hashable {
    public let name: String
    public let spectralType: String?
    /// Solar masses.
    public let massSolar: Double
    /// Solar radii.
    public let radiusSolar: Double
    /// Kelvin.
    public let temperatureKelvin: Double
    /// Linear RGB, brightest channel 1.
    public let color: SIMD3<Float>
    /// Where the star sits in the catalog, or nil for a star described from scratch.
    public let catalogLocation: StarLocation?
}

/// A Central Star and everything that orbits it, checked and ready to draw.
public struct PlanetarySystem: Sendable, Hashable {
    public let star: CentralStar
    /// In the order given.
    public let bodies: [Body]
    public let belts: [Belt]
    private let periodsByName: [String: Double]

    /// Checks `spec` and fills in what it leaves out. When `catalog` is given and has a star of
    /// the same name, its values are used for the Central Star. "Sun" and "Sol" always match the
    /// Sun. Throws `PlanetarySystemError` listing every problem.
    public init(_ spec: PlanetarySystemSpec, catalog: StarCatalog? = nil) throws {
        var problems: [PlanetarySystemProblem] = []
        let star = Self.resolveStar(spec.star, catalog: catalog ?? StarCatalog(stars: []), problems: &problems)
        let bodiesByName = Dictionary(spec.bodies.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        // Names
        var seen: Set<String> = []
        for name in [spec.star.name] + spec.bodies.map(\.name) {
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                problems.append(.emptyName)
            } else if !seen.insert(name).inserted {
                problems.append(.duplicateName(name))
            }
        }
        var beltNames: Set<String> = []
        for belt in spec.belts where !beltNames.insert(belt.name).inserted {
            problems.append(.duplicateName(belt.name))
        }

        // Bodies
        var periods: [String: Double] = [:]
        for body in spec.bodies {
            let orbit = body.orbit
            if !(orbit.distanceAU > 0) { problems.append(.nonPositiveDistance(body.name)) }
            if !(body.radiusKilometers > 0) { problems.append(.nonPositiveRadius(body.name)) }
            if let mass = body.massEarths, !(mass > 0) { problems.append(.nonPositiveMass(body.name)) }
            if let e = orbit.eccentricity, !(0..<1).contains(e) { problems.append(.eccentricityOutOfRange(body.name)) }
            if let color = body.color, body.rgbColor == nil { problems.append(.invalidColor(body: body.name, color: color)) }

            let ownMass = (body.massEarths ?? 0) * Astrophysics.earthMassInSolarMasses
            if body.parent == spec.star.name {
                if !body.kind.orbitsStar {
                    problems.append(.kindCannotOrbit(body: body.name, kind: body.kind, parent: body.parent))
                }
                if let given = orbit.periodDays {
                    if given > 0 { periods[body.name] = given } else { problems.append(.nonPositivePeriod(body.name)) }
                } else if orbit.distanceAU > 0 {
                    periods[body.name] = Astrophysics.orbitalPeriodDays(
                        semiMajorAxisAU: orbit.distanceAU, totalMassSolar: star.massSolar + ownMass
                    )
                }
            } else if let parent = bodiesByName[body.parent] {
                if body.kind != .moon || !BodyKind.moonParents.contains(parent.kind) {
                    problems.append(.kindCannotOrbit(body: body.name, kind: body.kind, parent: body.parent))
                }
                if let given = orbit.periodDays {
                    if given > 0 { periods[body.name] = given } else { problems.append(.nonPositivePeriod(body.name)) }
                } else if let parentMass = parent.massEarths, parentMass > 0 {
                    if orbit.distanceAU > 0 {
                        periods[body.name] = Astrophysics.orbitalPeriodDays(
                            semiMajorAxisAU: orbit.distanceAU,
                            totalMassSolar: parentMass * Astrophysics.earthMassInSolarMasses + ownMass
                        )
                    }
                } else {
                    problems.append(.periodNeedsParentMass(body: body.name, parent: body.parent))
                }
            } else {
                problems.append(.unknownParent(body: body.name, parent: body.parent))
            }
        }

        // Belts
        for belt in spec.belts {
            if !(belt.innerEdgeAU >= 0 && belt.outerEdgeAU > belt.innerEdgeAU) {
                problems.append(.invalidBeltEdges(belt.name))
            }
            if belt.parent != spec.star.name && bodiesByName[belt.parent] == nil {
                problems.append(.unknownBeltParent(belt: belt.name, parent: belt.parent))
            }
        }

        guard problems.isEmpty else { throw PlanetarySystemError(problems: problems) }
        self.star = star
        bodies = spec.bodies
        belts = spec.belts
        periodsByName = periods
    }

    /// Decodes a `PlanetarySystemSpec` from JSON and checks it.
    public init(json: Data, catalog: StarCatalog? = nil) throws {
        try self.init(JSONDecoder().decode(PlanetarySystemSpec.self, from: json), catalog: catalog)
    }

    public init(contentsOf url: URL, catalog: StarCatalog? = nil) throws {
        try self.init(json: Data(contentsOf: url), catalog: catalog)
    }

    /// The built-in Solar System, tied to the catalog's Sun.
    public static func solarSystem(catalog: StarCatalog? = nil) throws -> PlanetarySystem {
        guard let url = Bundle.module.url(forResource: "solar-system", withExtension: "json") else {
            throw StarCatalogError.resourceNotFound
        }
        return try PlanetarySystem(contentsOf: url, catalog: catalog)
    }

    // MARK: Lookups

    public func body(named name: String) -> Body? {
        bodies.first { $0.name == name }
    }

    /// Bodies that orbit the named Body, or the Central Star, in the order given.
    public func bodies(orbiting name: String) -> [Body] {
        bodies.filter { $0.parent == name }
    }

    /// The Parent Body, or nil when the Body orbits the Central Star.
    public func parentBody(of body: Body) -> Body? {
        self.body(named: body.parent)
    }

    /// Days per orbit: as given, or worked out from the Parent's mass.
    public func periodDays(of body: Body) -> Double {
        periodsByName[body.name] ?? 0
    }

    /// The Belt the Body lies within, if any: one with the same Parent that spans its distance.
    public func belt(containing body: Body) -> Belt? {
        belts.first { $0.parent == body.parent && $0.contains(distanceAU: body.orbit.distanceAU) }
    }

    // MARK: Central Star

    private static func resolveStar(
        _ spec: CentralStarSpec,
        catalog: StarCatalog,
        problems: inout [PlanetarySystemProblem]
    ) -> CentralStar {
        var spectralType = spec.spectralType
        var mass: Double?
        var radius: Double?
        var temperature: Double?
        let location = catalog.location(named: spec.name)

        if let location, let id = location.starID, let star = catalog.star(withID: id) {
            spectralType = spectralType ?? star.spectralType
            temperature = star.temperature
            radius = star.estimatedRadius
            mass = Astrophysics.estimatedMass(luminosity: star.luminosity, spectralType: star.spectralType)
        } else if location != nil {
            // The Sun.
            spectralType = spectralType ?? "G2V"
            temperature = Astrophysics.solarTemperature
            radius = 1
            mass = 1
        } else if let type = spectralType {
            temperature = Astrophysics.temperature(spectralType: type)
            radius = Astrophysics.estimatedRadius(spectralType: type)
            mass = Astrophysics.estimatedMass(spectralType: type)
            if temperature == nil { problems.append(.unknownSpectralType(type)) }
        } else {
            problems.append(.starNeedsSpectralType(spec.name))
        }

        func given(_ value: Double?, _ field: String) -> Double? {
            guard let value else { return nil }
            if !(value > 0) { problems.append(.nonPositiveStarValue(field)) }
            return value
        }
        mass = given(spec.massSolar, "massSolar") ?? mass
        radius = given(spec.radiusSolar, "radiusSolar") ?? radius
        temperature = given(spec.temperatureKelvin, "temperatureKelvin") ?? temperature

        let kelvin = temperature ?? Astrophysics.fallbackTemperature
        return CentralStar(
            name: spec.name,
            spectralType: spectralType,
            massSolar: mass ?? 1,
            radiusSolar: radius ?? 1,
            temperatureKelvin: kelvin,
            color: Astrophysics.color(temperature: kelvin),
            catalogLocation: location
        )
    }
}
