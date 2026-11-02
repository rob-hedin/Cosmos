import Foundation

/// What a Body orbits.
public enum Parent: Sendable, Hashable {
    /// The system's Central Star.
    case centralStar
    /// Another Body, by name.
    case body(String)
}

/// The path a Body follows around its Parent. Only the distance is required;
/// the defaults give a circular, flat orbit starting at angle 0.
public struct Orbit: Sendable, Hashable {
    /// Semi-major axis in AU. Must be finite and above 0.
    public let distance: Double
    /// Orbital period in days, when known. When nil, `PlanetarySystem.orbitalPeriod(of:)` derives it.
    public let period: Double?
    /// 0 ≤ e < 1. Default 0.
    public let eccentricity: Double
    /// Degrees, relative to the Parent's reference plane. Default 0. Must be finite.
    public let inclination: Double
    /// Where the Body starts along its orbit, in degrees. Default 0. Must be finite.
    public let startingAngle: Double

    public init(
        distance: Double,
        period: Double? = nil,
        eccentricity: Double = 0,
        inclination: Double = 0,
        startingAngle: Double = 0
    ) {
        self.distance = distance
        self.period = period
        self.eccentricity = eccentricity
        self.inclination = inclination
        self.startingAngle = startingAngle
    }
}

/// Anything with its own orbit in a Planetary System that is not a star.
public struct Body: Sendable, Hashable, Identifiable {
    /// What sort of Body it is.
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case planet
        case dwarfPlanet = "dwarf planet"
        case moon, asteroid, comet
    }

    /// Names are unique within a system, so the name is the ID.
    public var id: String { name }
    public let name: String
    public let kind: Kind
    public let parent: Parent
    public let orbit: Orbit
    /// Mean radius in km. Must be finite and above 0.
    public let radius: Double
    /// Earth masses, when known. Must be finite and above 0 when given.
    public let mass: Double?
    /// sRGB components in 0...1, when given (checked by `PlanetarySystem.init`; NaN and
    /// infinities are rejected). Nil means the view picks a default per Kind.
    public let color: SIMD3<Float>?

    public init(
        name: String,
        kind: Kind,
        parent: Parent,
        orbit: Orbit,
        radius: Double,
        mass: Double? = nil,
        color: SIMD3<Float>? = nil
    ) {
        self.name = name
        self.kind = kind
        self.parent = parent
        self.orbit = orbit
        self.radius = radius
        self.mass = mass
        self.color = color
    }
}

/// A region of many small bodies around a Parent, drawn as a ring.
public struct Belt: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let parent: Parent
    /// AU. 0 ≤ innerEdge < outerEdge, both finite.
    public let innerEdge: Double
    public let outerEdge: Double

    public init(name: String, parent: Parent, innerEdge: Double, outerEdge: Double) {
        self.name = name
        self.parent = parent
        self.innerEdge = innerEdge
        self.outerEdge = outerEdge
    }
}

/// A Central Star with every Body and Belt that orbits it. Always valid once built.
///
/// Distances are in AU, Body radii in km, Body masses in Earth masses, star masses in solar masses
/// and periods in days. Names are matched exactly (case-sensitive).
public struct PlanetarySystem: Sendable, Hashable {
    public let name: String
    public let centralStar: CentralStar
    /// In input order.
    public let bodies: [Body]
    /// In input order.
    public let belts: [Belt]

    /// Checks the input and throws every problem found: an unknown Parent, a Parent loop, a bad
    /// distance, a broken Kind rule, a repeated name, an out-of-range value or a Belt with bad edges.
    public init(
        name: String,
        centralStar: CentralStar,
        bodies: [Body],
        belts: [Belt] = []
    ) throws(PlanetarySystemError) {
        let problems = Self.validate(
            starName: centralStar.name,
            starValues: StarValues(centralStar),
            bodies: bodies.map(BodyCandidate.init),
            belts: belts
        )
        guard problems.isEmpty else { throw PlanetarySystemError(problems: problems) }
        self.init(validatedName: name, centralStar: centralStar, bodies: bodies, belts: belts)
    }

    /// For input that has already passed `validate`.
    init(validatedName name: String, centralStar: CentralStar, bodies: [Body], belts: [Belt]) {
        self.name = name
        self.centralStar = centralStar
        self.bodies = bodies
        self.belts = belts
    }

    /// The Body with this exact name.
    public func body(named name: String) -> Body? {
        bodies.first { $0.name == name }
    }

    /// Bodies whose Parent is `parent`, in input order.
    public func children(of parent: Parent) -> [Body] {
        bodies.filter { $0.parent == parent }
    }

    /// Mass of a Parent in solar masses: the star's mass, or the Body's mass divided by
    /// `Astrophysics.earthMassesPerSolarMass`. Nil for an unknown Body or a Body with no mass.
    public func mass(of parent: Parent) -> Double? {
        switch parent {
        case .centralStar:
            centralStar.mass
        case .body(let name):
            body(named: name)?.mass.map { $0 / Astrophysics.earthMassesPerSolarMass }
        }
    }

    /// Days: the Orbit's period when given, else Kepler's third law from the distance and the
    /// Parent's mass plus the Body's own (0 when unknown). Nil when no Body with `body.name`
    /// is in the system.
    public func orbitalPeriod(of body: Body) -> Double? {
        guard self.body(named: body.name) != nil else { return nil }
        if let period = body.orbit.period { return period }
        guard let parentMass = mass(of: body.parent) else { return nil }
        let ownMass = (body.mass ?? 0) / Astrophysics.earthMassesPerSolarMass
        return Astrophysics.orbitalPeriod(semiMajorAxis: body.orbit.distance, totalMass: parentMass + ownMass)
    }

    /// The first Belt (input order) with the same Parent whose edges contain the Body's
    /// distance (`innerEdge <= distance <= outerEdge`), else nil.
    public func belt(containing body: Body) -> Belt? {
        belts.first {
            $0.parent == body.parent && $0.innerEdge <= body.orbit.distance && body.orbit.distance <= $0.outerEdge
        }
    }
}
