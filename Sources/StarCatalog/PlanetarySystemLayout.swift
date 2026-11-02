import Foundation

/// Something you can select in a Planetary System view.
public enum PlanetarySystemItem: Sendable, Hashable {
    case centralStar
    /// A Body, by name.
    case body(String)
}

/// How a Planetary System is laid out for viewing.
public enum PlanetarySystemScale: String, Sendable, Hashable, CaseIterable {
    /// Distances and sizes are compressed, each level on its own, so everything fits and stays visible.
    case compressed
    /// Distances and sizes are real: a scene unit is one AU.
    case trueScale
}

/// Where everything in a Planetary System goes in the view, in one scale. Positions are in scene
/// units (AU in True scale), with the Central Star at the origin.
///
/// In Compressed scale each level is compressed on its own. A level is the set of Bodies that share
/// a Parent, together with the Belts around that Parent. A level's distances are normalized by its
/// own reach, so changing one planet's moons never moves another level. The star's level maps its
/// reach to `systemRadius`; a Body's level of moons starts at `moonInnerFactor` times the Body's
/// drawn radius and ends at the Body's room, so moons stay outside their enlarged planet. A direction
/// is never changed; only distances from the Parent are.
public struct PlanetarySystemLayout: Sendable {
    /// Compressed: the scene distance the system's farthest reach maps to.
    public static let systemRadius = 10.0
    /// The power applied to a level's distances (as a fraction of its reach) in Compressed scale.
    public static let distanceExponent = 0.5
    /// The power applied to a Body's radius, as a multiple of Earth's, to get its relative drawn size.
    public static let sizeExponent = 0.5
    /// The share of the gap to the nearest neighbor that a Body's moons may use.
    public static let roomFraction = 0.4
    /// A Body's drawn radius is at most this share of its room.
    public static let sizeFraction = 0.3
    /// The closest any moon orbit gets: this times the Parent's drawn radius.
    public static let moonInnerFactor = 2.0
    /// No moon is drawn bigger than this share of its Parent.
    public static let maximumMoonToParentRatio = 0.5
    /// A Body as big as Earth is never drawn with a radius over this (scene units), so a small Body
    /// on its own does not swell to fill its room. Bigger and smaller Bodies scale from it.
    public static let maximumEarthSizedRadius = 0.05
    /// The star's radius is at most this share of the innermost periapsis.
    public static let starClearanceFraction = 0.5
    /// The star's radius, as a share of `systemRadius`, when nothing orbits it.
    public static let lonelyStarFraction = 0.05
    /// Room around a Body and its moons when framing it.
    public static let viewingSpanMargin = 1.25
    /// The view's span across a Body, in drawn radii, when it has no moons.
    public static let bodySpanFactor = 8.0
    /// The home view's span, in extents.
    public static let homeSpanFactor = 2.2

    public let system: PlanetarySystem
    public let scale: PlanetarySystemScale

    /// Everything the layout works out once, so frames only do orbital arithmetic.
    private let bodyIndices: [String: Int]
    private let parentIndices: [Int?]
    private let periods: [Double?]
    private let childIndices: [[Int]]
    private let starLevel: Level?
    private let bodyLevels: [Int: Level]
    private let orbitRadii: [Double]
    private let radii: [Double]
    private let starRadius: Double

    /// Drawn Bodies and the star never get farther from the origin than this, counting their drawn radii.
    public let extent: Double
    /// The smallest drawn radius of any item.
    public let smallestDrawnRadius: Double

    public init(system: PlanetarySystem, scale: PlanetarySystemScale) {
        self.system = system
        self.scale = scale

        let bodies = system.bodies
        var indices: [String: Int] = [:]
        for (index, body) in bodies.enumerated() where indices[body.name] == nil {
            indices[body.name] = index
        }
        let parents: [Int?] = bodies.map { body in
            if case .body(let name) = body.parent { indices[name] } else { nil }
        }
        var children = [[Int]](repeating: [], count: bodies.count)
        var topLevel: [Int] = []
        for index in bodies.indices {
            if let parent = parents[index] { children[parent].append(index) } else { topLevel.append(index) }
        }
        bodyIndices = indices
        parentIndices = parents
        childIndices = children
        periods = bodies.map { system.orbitalPeriod(of: $0) }

        var geometry = Geometry(count: bodies.count)
        switch scale {
        case .trueScale:
            for (index, body) in bodies.enumerated() {
                geometry.radii[index] = body.radius / Astrophysics.kilometersPerAU
                geometry.orbitRadii[index] = body.orbit.distance
            }
            geometry.starRadius = system.centralStar.radius
                * Astrophysics.kilometersPerSolarRadius / Astrophysics.kilometersPerAU
        case .compressed:
            geometry.compress(system: system, children: children, topLevel: topLevel)
        }
        starLevel = geometry.starLevel
        bodyLevels = geometry.bodyLevels
        orbitRadii = geometry.orbitRadii
        radii = geometry.radii
        starRadius = geometry.starRadius

        smallestDrawnRadius = min(geometry.starRadius, geometry.radii.min() ?? .infinity)
        extent = Self.computeExtent(
            system: system, scale: scale, indices: indices, parents: parents, radii: geometry.radii,
            starRadius: geometry.starRadius, starLevel: geometry.starLevel, bodyLevels: geometry.bodyLevels
        )
    }

    // MARK: Distances

    /// The level's distance mapping around `parent`, from a true distance (AU) to a scene distance.
    /// True scale: the distance itself. Compressed: the mapping of the level of Bodies and Belts
    /// that share this Parent; a Parent with nothing around it has no mapping, so the distance is
    /// returned as it is.
    public func sceneDistance(ofTrueDistance distance: Double, around parent: Parent) -> Double {
        switch scale {
        case .trueScale: distance
        case .compressed: level(of: parent)?.sceneDistance(distance) ?? distance
        }
    }

    private func level(of parent: Parent) -> Level? {
        switch parent {
        case .centralStar: starLevel
        case .body(let name): bodyIndices[name].flatMap { bodyLevels[$0] }
        }
    }

    /// Scene semi-major axis around the Parent: `sceneDistance(ofTrueDistance: a, around: parent)`.
    /// Nil for a Body that is not in the system.
    public func orbitRadius(of body: Body) -> Double? {
        guard bodyIndices[body.name] != nil else { return nil }
        return sceneDistance(ofTrueDistance: body.orbit.distance, around: body.parent)
    }

    /// The farthest any of the Body's children get from it, in scene units: the largest
    /// `sceneDistance(a(1+e))` over its children. 0 when it has none.
    public func moonReach(of body: Body) -> Double {
        guard let index = bodyIndices[body.name] else { return 0 }
        return childIndices[index].map { child in
            let orbit = system.bodies[child].orbit
            return sceneDistance(ofTrueDistance: orbit.distance * (1 + orbit.eccentricity), around: .body(body.name))
        }.max() ?? 0
    }

    /// A Belt's edges in scene units, around its Parent's position.
    public func beltRadii(of belt: Belt) -> ClosedRange<Double> {
        let inner = sceneDistance(ofTrueDistance: belt.innerEdge, around: belt.parent)
        let outer = sceneDistance(ofTrueDistance: belt.outerEdge, around: belt.parent)
        return inner...max(inner, outer)
    }

    /// The Body's orbit as a closed path relative to its Parent: `Orbit.pathOffsets(segments:)`, each
    /// point moved along its own direction to `sceneDistance(|p|)`. Empty for a Body not in the system.
    public func orbitPath(of body: Body, segments: Int) -> [SIMD3<Double>] {
        guard bodyIndices[body.name] != nil else { return [] }
        return body.orbit.pathOffsets(segments: segments).map { sceneOffset($0, around: body.parent) }
    }

    /// Moves an offset along its own direction to the scene distance of its length.
    private func sceneOffset(_ offset: SIMD3<Double>, around parent: Parent) -> SIMD3<Double> {
        guard scale == .compressed else { return offset }
        let length = (offset * offset).sum().squareRoot()
        guard length > 0 else { return offset }
        return offset * (sceneDistance(ofTrueDistance: length, around: parent) / length)
    }

    // MARK: Positions

    /// Scene position at `day`. `.centralStar` is the origin. Nil for a name not in the system.
    public func position(of item: PlanetarySystemItem, atDay day: Double) -> SIMD3<Double>? {
        switch item {
        case .centralStar:
            return .zero
        case .body(let name):
            guard let index = bodyIndices[name] else { return nil }
            var memo = [SIMD3<Double>?](repeating: nil, count: system.bodies.count)
            return position(ofBodyAt: index, atDay: day, memo: &memo)
        }
    }

    /// Every Body's position at `day`, in `system.bodies` order.
    public func bodyPositions(atDay day: Double) -> [SIMD3<Double>] {
        var memo = [SIMD3<Double>?](repeating: nil, count: system.bodies.count)
        return system.bodies.indices.map { position(ofBodyAt: $0, atDay: day, memo: &memo) }
    }

    /// A Body's Parent's position plus its own scene offset. Parents are worked out first and
    /// remembered, so each Body is computed once; the result is the same however it is reached.
    private func position(ofBodyAt index: Int, atDay day: Double, memo: inout [SIMD3<Double>?]) -> SIMD3<Double> {
        if let known = memo[index] { return known }
        let body = system.bodies[index]
        let parentPosition = parentIndices[index].map { position(ofBodyAt: $0, atDay: day, memo: &memo) } ?? .zero
        let trueOffset = body.orbit.offset(atDay: day, period: periods[index])
        let result = parentPosition + sceneOffset(trueOffset, around: body.parent)
        memo[index] = result
        return result
    }

    // MARK: Sizes and framing

    /// Drawn sphere radius in scene units. Nil for a name not in the system.
    public func drawnRadius(of item: PlanetarySystemItem) -> Double? {
        switch item {
        case .centralStar: starRadius
        case .body(let name): bodyIndices[name].map { radii[$0] }
        }
    }

    /// The span (scene units across the shorter side of the view) that frames an item. A Body:
    /// the larger of `2 × viewingSpanMargin ×` its `moonReach` and `bodySpanFactor ×` its drawn
    /// radius. The Central Star: `homeSpan`. Nil for a name not in the system.
    public func viewingSpan(of item: PlanetarySystemItem) -> Double? {
        switch item {
        case .centralStar:
            return homeSpan
        case .body(let name):
            guard let index = bodyIndices[name] else { return nil }
            return max(
                2 * Self.viewingSpanMargin * moonReach(of: system.bodies[index]),
                Self.bodySpanFactor * radii[index]
            )
        }
    }

    /// The span of the home view: `homeSpanFactor × extent`.
    public var homeSpan: Double {
        Self.homeSpanFactor * extent
    }

    private static func computeExtent(
        system: PlanetarySystem, scale: PlanetarySystemScale, indices: [String: Int], parents: [Int?], radii: [Double],
        starRadius: Double, starLevel: Level?, bodyLevels: [Int: Level]
    ) -> Double {
        func distance(_ distance: Double, around parent: Int?) -> Double {
            guard scale == .compressed else { return distance }
            let level = parent.map { bodyLevels[$0] } ?? starLevel
            return level?.sceneDistance(distance) ?? distance
        }
        // The farthest each Body can be from the star, the apoapsis out from each Parent in turn.
        var farthest = [Double?](repeating: nil, count: system.bodies.count)
        func farthestReach(_ index: Int) -> Double {
            if let known = farthest[index] { return known }
            let orbit = system.bodies[index].orbit
            let parent = parents[index]
            let reach = distance(orbit.distance * (1 + orbit.eccentricity), around: parent)
                + (parent.map(farthestReach) ?? 0)
            farthest[index] = reach
            return reach
        }
        var result = starRadius
        for index in system.bodies.indices {
            result = max(result, farthestReach(index) + radii[index])
        }
        for belt in system.belts {
            let parent: Int? = if case .body(let name) = belt.parent { indices[name] } else { nil }
            result = max(result, distance(belt.outerEdge, around: parent) + (parent.map(farthestReach) ?? 0))
        }
        return result
    }
}

// MARK: Compression

/// One level's mapping from true distance to scene distance:
/// `inner + (outer − inner) × (distance / reach)^distanceExponent`.
private struct Level: Sendable {
    /// Scene distance at a true distance of 0.
    let inner: Double
    /// Scene distance at the reach.
    let outer: Double
    /// True distance (AU) of the farthest apoapsis or Belt edge in the level.
    let reach: Double

    func sceneDistance(_ distance: Double) -> Double {
        guard reach > 0 else { return inner }
        let fraction = max(distance, 0) / reach
        return inner + (outer - inner) * pow(fraction, PlanetarySystemLayout.distanceExponent)
    }
}

/// The numbers a layout works out in one pass.
private struct Geometry {
    var starLevel: Level?
    var bodyLevels: [Int: Level] = [:]
    /// Scene semi-major axes around the Parent, per Body.
    var orbitRadii: [Double]
    var radii: [Double]
    var starRadius = 0.0

    init(count: Int) {
        orbitRadii = [Double](repeating: 0, count: count)
        radii = [Double](repeating: 0, count: count)
    }

    /// Works out every level top-down: the star's, then each Body's that has moons or Belts.
    mutating func compress(system: PlanetarySystem, children: [[Int]], topLevel: [Int]) {
        typealias Layout = PlanetarySystemLayout
        let bodies = system.bodies
        let earthRadius = Astrophysics.earthRadiusKilometers

        func reach(of members: [Int], belts: [Belt]) -> Double {
            max(
                members.map { bodies[$0].orbit.distance * (1 + bodies[$0].orbit.eccentricity) }.max() ?? 0,
                belts.map(\.outerEdge).max() ?? 0
            )
        }
        func relativeSize(_ index: Int) -> Double {
            pow(bodies[index].radius / earthRadius, Layout.sizeExponent)
        }

        /// Sizes and orbit radii for one level, then its Bodies' own levels. Returns the level's base size.
        func process(
            members: [Int], level: Level, surface: Double, parentBase: Double, parentRadius: Double?
        ) -> Double {
            var rooms: [Int: Double] = [:]
            for index in members {
                orbitRadii[index] = level.sceneDistance(bodies[index].orbit.distance)
            }
            for index in members {
                var gap = orbitRadii[index] - surface
                for other in members where orbitRadii[other] != orbitRadii[index] {
                    gap = min(gap, abs(orbitRadii[index] - orbitRadii[other]))
                }
                rooms[index] = Layout.roomFraction * gap
            }
            var base = parentBase
            for index in members {
                base = min(base, Layout.sizeFraction * (rooms[index] ?? 0) / relativeSize(index))
            }
            // Capping the whole level, not each Body, keeps the sizes in their real order.
            if let parentRadius, let largest = members.map(relativeSize).max() {
                base = min(base, Layout.maximumMoonToParentRatio * parentRadius / largest)
            }
            for index in members {
                radii[index] = base * relativeSize(index)
            }
            for index in members {
                let belts = system.belts.filter { $0.parent == .body(bodies[index].name) }
                let moonReach = reach(of: children[index], belts: belts)
                guard moonReach > 0 else { continue }
                let moonLevel = Level(
                    inner: Layout.moonInnerFactor * radii[index], outer: rooms[index] ?? 0, reach: moonReach
                )
                bodyLevels[index] = moonLevel
                if !children[index].isEmpty {
                    _ = process(
                        members: children[index], level: moonLevel, surface: radii[index],
                        parentBase: base, parentRadius: radii[index]
                    )
                }
            }
            return base
        }

        let starReach = reach(of: topLevel, belts: system.belts.filter { $0.parent == .centralStar })
        if starReach > 0 {
            starLevel = Level(inner: 0, outer: Layout.systemRadius, reach: starReach)
        }
        guard !topLevel.isEmpty, let starLevel else {
            starRadius = Layout.lonelyStarFraction * Layout.systemRadius
            return
        }
        let base = process(
            members: topLevel, level: starLevel, surface: 0, parentBase: Layout.maximumEarthSizedRadius, parentRadius: nil
        )
        let innermostPeriapsis = topLevel.map {
            starLevel.sceneDistance(bodies[$0].orbit.distance * (1 - bodies[$0].orbit.eccentricity))
        }.min() ?? 0
        let starSize = pow(
            system.centralStar.radius * Astrophysics.kilometersPerSolarRadius / earthRadius, Layout.sizeExponent
        )
        starRadius = min(base * starSize, Layout.starClearanceFraction * innermostPeriapsis)
    }
}
