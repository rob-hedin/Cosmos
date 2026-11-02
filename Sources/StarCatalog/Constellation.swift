import Foundation

/// A direction on the sky, in the catalog's equatorial frame (J2000).
public struct SkyPosition: Sendable, Hashable {
    public let rightAscensionHours: Double
    public let declinationDegrees: Double

    public init(rightAscensionHours: Double, declinationDegrees: Double) {
        self.rightAscensionHours = rightAscensionHours
        self.declinationDegrees = declinationDegrees
    }

    /// Unit vector toward this direction, in the same frame as `Star.position`.
    public var direction: SIMD3<Double> {
        Astrophysics.position(
            rightAscensionHours: rightAscensionHours, declinationDegrees: declinationDegrees, distanceLightYears: 1
        )
    }
}

/// One of the 88 IAU constellations and its traditional stick figure.
public struct Constellation: Sendable, Hashable, Identifiable {
    /// The IAU abbreviation, such as "Ori".
    public let id: String
    public let name: String
    /// Where to put the name.
    public let center: SkyPosition
    /// The figure's polylines; each joins its points in order.
    public let lines: [[SkyPosition]]

    public init(id: String, name: String, center: SkyPosition, lines: [[SkyPosition]]) {
        self.id = id
        self.name = name
        self.center = center
        self.lines = lines
    }

    /// The bundled figures, converted from d3-celestial (BSD license; see
    /// `constellations-LICENSE.txt`). They include stars beyond 200 ly, such as most of Orion.
    public static func bundled() throws -> [Constellation] {
        guard let url = Bundle.module.url(forResource: "constellations", withExtension: "json") else {
            throw StarCatalogError.resourceNotFound
        }
        return try decode(Data(contentsOf: url))
    }

    /// Decodes `[{"id", "name", "center": [raHours, dec], "lines": [[[raHours, dec], ...], ...]}]`.
    static func decode(_ data: Data) throws -> [Constellation] {
        struct Raw: Decodable {
            let id: String
            let name: String
            let center: [Double]
            let lines: [[[Double]]]
        }
        func sky(_ pair: [Double]) -> SkyPosition? {
            pair.count == 2 ? SkyPosition(rightAscensionHours: pair[0], declinationDegrees: pair[1]) : nil
        }
        return try JSONDecoder().decode([Raw].self, from: data).compactMap { raw in
            guard let center = sky(raw.center) else { return nil }
            return Constellation(id: raw.id, name: raw.name, center: center,
                                 lines: raw.lines.map { $0.compactMap(sky) })
        }
    }
}

extension StarCatalog {
    /// The star nearest `sky`, within `toleranceDegrees`, such as the catalog star at one point
    /// of a constellation figure. Nil when the point's star lies beyond the catalog. The figures'
    /// points match their catalog stars to within 0.005°, while the nearest unrelated star is
    /// 0.09° away, so the default tolerance doesn't substitute a neighbor for a missing star.
    public func star(near sky: SkyPosition, toleranceDegrees: Double = 0.02, magnitudeLimit: Double = 7) -> Star? {
        let target = sky.direction
        var best: (star: Star, cosine: Double)?
        let threshold = cos(toleranceDegrees * .pi / 180)
        for star in stars where star.apparentMagnitude < magnitudeLimit {
            let distance = star.distanceLightYears
            guard distance > 0, distance.isFinite else { continue }
            let cosine = (SIMD3<Double>(star.position) / distance * target).sum()
            guard cosine >= threshold, cosine > best?.cosine ?? -2 else { continue }
            best = (star, cosine)
        }
        return best?.star
    }
}
