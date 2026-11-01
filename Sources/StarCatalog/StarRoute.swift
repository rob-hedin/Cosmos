import Foundation

/// A place in the catalog that can be looked up by name: a star, or the Sun at the origin
/// (which isn't a row in the catalog).
public struct StarLocation: Sendable, Hashable {
    /// The name to show, such as "Sun" or "Rigil Kentaurus".
    public let name: String
    /// Light years from the Sun, in the catalog's equatorial frame.
    public let position: SIMD3<Float>
    /// The catalog star, or nil for the Sun.
    public let starID: Star.ID?

    public init(name: String, position: SIMD3<Float>, starID: Star.ID?) {
        self.name = name
        self.position = position
        self.starID = starID
    }

    public static let sun = StarLocation(name: "Sun", position: .zero, starID: nil)

    /// Straight-line distance, in light years.
    public func distance(to other: StarLocation) -> Double {
        let d = SIMD3<Double>(other.position) - SIMD3<Double>(position)
        return (d * d).sum().squareRoot()
    }
}

extension StarCatalog {
    /// Common names that the catalog files under another name.
    static let aliases: [String: String] = [
        "alpha centauri": "Rigil Kentaurus",
        "alpha centauri a": "Rigil Kentaurus",
        "alpha centauri b": "Toliman",
        "alpha centauri c": "Proxima Centauri",
        "proxima": "Proxima Centauri",
        "barnards star": "Barnard's Star",
    ]

    /// Finds a star by name, ignoring case and spacing. Also understands "Sun" and "Sol",
    /// a few common aliases such as "Alpha Centauri", and catalog numbers such as "HIP 71683"
    /// or "HD 128620".
    public func location(named name: String) -> StarLocation? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.lowercased().split(separator: " ").joined(separator: " ")
        if key == "sun" || key == "sol" {
            return .sun
        }
        let star = star(named: trimmed)
            ?? Self.aliases[key.replacingOccurrences(of: "'", with: "")].flatMap { star(named: $0) }
            ?? star(catalogNumber: key)
        return star.map { StarLocation(name: $0.name, position: $0.position, starID: $0.id) }
    }

    /// "hip 71683" or "hd 128620" (lowercased, single spaces), by the catalog's HIP or HD column.
    private func star(catalogNumber key: String) -> Star? {
        let parts = key.split(separator: " ")
        guard parts.count == 2, let number = Int(parts[1]) else { return nil }
        switch parts[0] {
        case "hip": return stars.first { $0.hipparcosID == number }
        case "hd": return stars.first { $0.henryDraperID == number }
        default: return nil
        }
    }
}

/// An ordered list of stars to visit, with the distance of each leg.
public struct StarRoute: Sendable, Equatable {
    public struct Leg: Sendable, Equatable {
        public let from: StarLocation
        public let to: StarLocation
        /// Light years.
        public let distance: Double
    }

    /// The stops that were found, in order.
    public let stops: [StarLocation]
    /// Requested names that matched nothing, in order.
    public let unresolved: [String]

    /// Looks up each name in `catalog`. Names that match nothing are kept in `unresolved` and
    /// left out of the route, so the remaining stops still connect.
    public init(_ names: [String], in catalog: StarCatalog) {
        var stops: [StarLocation] = []
        var unresolved: [String] = []
        for name in names where !name.trimmingCharacters(in: .whitespaces).isEmpty {
            if let location = catalog.location(named: name) {
                stops.append(location)
            } else {
                unresolved.append(name)
            }
        }
        self.init(stops: stops, unresolved: unresolved)
    }

    public init(stops: [StarLocation], unresolved: [String] = []) {
        self.stops = stops
        self.unresolved = unresolved
    }

    public var legs: [Leg] {
        zip(stops, stops.dropFirst()).map { Leg(from: $0, to: $1, distance: $0.distance(to: $1)) }
    }

    /// Sum of the legs, in light years.
    public var totalDistance: Double {
        legs.reduce(0) { $0 + $1.distance }
    }

    /// How far the farthest stop is from the first, in light years: the radius a view centered
    /// on the first stop needs to show them all.
    public var reachFromFirstStop: Double {
        guard let first = stops.first else { return 0 }
        return stops.map { first.distance(to: $0) }.max() ?? 0
    }
}
