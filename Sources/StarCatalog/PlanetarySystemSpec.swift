import Foundation

// The input an app gives to describe a Planetary System, as Swift values or as JSON with the
// same field names. `PlanetarySystem` checks it and fills in what was left out.

/// What sort of Body something is. In JSON: "planet", "dwarfPlanet", "moon", "asteroid" or "comet".
public enum BodyKind: String, Codable, Sendable, CaseIterable {
    case planet
    case dwarfPlanet
    case moon
    case asteroid
    case comet

    /// Whether a Body of this Kind may orbit the Central Star directly. A moon orbits another Body.
    public var orbitsStar: Bool { self != .moon }

    /// Kinds a moon may orbit. Asteroids are included, for asteroid moons such as Dimorphos.
    public static let moonParents: Set<BodyKind> = [.planet, .dwarfPlanet, .asteroid]
}

/// The star at the middle of a Planetary System.
///
/// Name a catalog star (or "Sun") and pass the catalog when building the system: its values are
/// used, and any given here override them. For a star that isn't in the catalog, `spectralType`
/// is required and the rest are estimated from it.
public struct CentralStarSpec: Codable, Sendable, Hashable {
    public var name: String
    /// Such as "G2V" or "M5.5Ve".
    public var spectralType: String?
    /// Solar masses.
    public var massSolar: Double?
    /// Solar radii.
    public var radiusSolar: Double?
    /// Kelvin.
    public var temperatureKelvin: Double?

    public init(
        name: String,
        spectralType: String? = nil,
        massSolar: Double? = nil,
        radiusSolar: Double? = nil,
        temperatureKelvin: Double? = nil
    ) {
        self.name = name
        self.spectralType = spectralType
        self.massSolar = massSolar
        self.radiusSolar = radiusSolar
        self.temperatureKelvin = temperatureKelvin
    }
}

/// The path a Body follows around its Parent. Only the distance is required; with nothing else,
/// the orbit is circular, flat, and its period comes from the Parent's mass.
public struct Orbit: Codable, Sendable, Hashable {
    /// Semi-major axis in AU, for moons too (the Moon is at 0.00257 AU).
    public var distanceAU: Double
    /// 0 for a circle, up to (but not including) 1. Nil means 0.
    public var eccentricity: Double?
    /// Tilt from the Parent's reference plane, in degrees. Nil means 0.
    public var inclinationDegrees: Double?
    /// Longitude of the ascending node, in degrees. Nil means 0.
    public var ascendingNodeDegrees: Double?
    /// Argument of periapsis, in degrees. Nil means 0.
    public var periapsisArgumentDegrees: Double?
    /// Where the Body starts along its orbit (mean anomaly), in degrees. Nil means 0.
    public var startAngleDegrees: Double?
    /// Days per orbit. Nil means worked out from the Parent's mass.
    public var periodDays: Double?

    public init(
        distanceAU: Double,
        eccentricity: Double? = nil,
        inclinationDegrees: Double? = nil,
        ascendingNodeDegrees: Double? = nil,
        periapsisArgumentDegrees: Double? = nil,
        startAngleDegrees: Double? = nil,
        periodDays: Double? = nil
    ) {
        self.distanceAU = distanceAU
        self.eccentricity = eccentricity
        self.inclinationDegrees = inclinationDegrees
        self.ascendingNodeDegrees = ascendingNodeDegrees
        self.periapsisArgumentDegrees = periapsisArgumentDegrees
        self.startAngleDegrees = startAngleDegrees
        self.periodDays = periodDays
    }
}

/// Anything with its own orbit in a Planetary System that is not a star.
public struct Body: Codable, Sendable, Hashable, Identifiable {
    /// Names are unique within a system, so they serve as IDs.
    public var id: String { name }

    public var name: String
    public var kind: BodyKind
    /// The name of what this Body orbits: the Central Star or another Body.
    public var parent: String
    public var orbit: Orbit
    /// Mean radius in kilometers.
    public var radiusKilometers: Double
    /// Earth masses. Needed on a Parent whose moons give no period.
    public var massEarths: Double?
    /// "#RRGGBB". Nil means the view's default for the Kind.
    public var color: String?

    public init(
        name: String,
        kind: BodyKind,
        parent: String,
        orbit: Orbit,
        radiusKilometers: Double,
        massEarths: Double? = nil,
        color: String? = nil
    ) {
        self.name = name
        self.kind = kind
        self.parent = parent
        self.orbit = orbit
        self.radiusKilometers = radiusKilometers
        self.massEarths = massEarths
        self.color = color
    }

    /// The color as linear RGB, or nil when none was given or it isn't "#RRGGBB".
    public var rgbColor: SIMD3<Float>? { color.flatMap(Self.parseHexColor) }

    static func parseHexColor(_ text: String) -> SIMD3<Float>? {
        let hex = text.hasPrefix("#") ? text.dropFirst() : Substring(text)
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        func channel(_ shift: UInt32) -> Float {
            let c = Double((value >> shift) & 0xFF) / 255
            return Float(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
        }
        return SIMD3(channel(16), channel(8), channel(0))
    }
}

/// A region of many small bodies around a Parent, drawn as a ring.
public struct Belt: Codable, Sendable, Hashable, Identifiable {
    public var id: String { name }

    public var name: String
    /// The name of what the Belt circles: usually the Central Star.
    public var parent: String
    /// AU from the Parent.
    public var innerEdgeAU: Double
    /// AU from the Parent.
    public var outerEdgeAU: Double

    public init(name: String, parent: String, innerEdgeAU: Double, outerEdgeAU: Double) {
        self.name = name
        self.parent = parent
        self.innerEdgeAU = innerEdgeAU
        self.outerEdgeAU = outerEdgeAU
    }

    public func contains(distanceAU: Double) -> Bool {
        (innerEdgeAU...outerEdgeAU).contains(distanceAU)
    }
}

/// Everything an app supplies for one Planetary System.
public struct PlanetarySystemSpec: Codable, Sendable, Hashable {
    public var star: CentralStarSpec
    public var bodies: [Body]
    public var belts: [Belt]

    public init(star: CentralStarSpec, bodies: [Body] = [], belts: [Belt] = []) {
        self.star = star
        self.bodies = bodies
        self.belts = belts
    }

    /// `belts` may be left out of the JSON.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        star = try container.decode(CentralStarSpec.self, forKey: .star)
        bodies = try container.decodeIfPresent([Body].self, forKey: .bodies) ?? []
        belts = try container.decodeIfPresent([Belt].self, forKey: .belts) ?? []
    }
}
