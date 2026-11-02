import Foundation
import simd
import StarCatalog

// Everything about a Planetary System view that is not drawing. These types use `simd` and
// `OrbitCamera` but no Metal, so they run (and are tested) without a display.

/// One frame's items, positioned relative to an origin, ready for the GPU and for picking.
public struct PlanetarySceneSnapshot: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let item: PlanetarySystemItem
        /// `Float(layout position − origin)`, worked out in `Double` before converting, so True
        /// scale close-ups stay steady far from the star.
        public let position: SIMD3<Float>
        /// Drawn radius, in scene units.
        public let radius: Float
    }

    /// The Central Star first, then the Bodies in `system.bodies` order.
    public let entries: [Entry]

    /// The items of `layout` at `day`, with positions relative to `origin` (scene units).
    public init(layout: PlanetarySystemLayout, day: Double, origin: SIMD3<Double>) {
        func entry(_ item: PlanetarySystemItem, at position: SIMD3<Double>) -> Entry {
            let relative = position - origin
            return Entry(
                item: item,
                position: SIMD3(Float(relative.x), Float(relative.y), Float(relative.z)),
                radius: Float(layout.drawnRadius(of: item) ?? 0)
            )
        }
        let bodies = layout.system.bodies
        let positions = layout.bodyPositions(atDay: day)
        entries = [entry(.centralStar, at: .zero)]
            + bodies.indices.map { entry(.body(bodies[$0].name), at: positions[$0]) }
    }
}

/// How big a sphere looks on screen.
public enum SphereProjection {
    /// On-screen radius in points of a sphere of `radius` at `center`:
    /// `tan(asin(radius / d)) / tan(fov / 2) × shortSide / 2`, where `d` is the distance from the
    /// eye, and never below `minimum`. Returns `viewportShortSide` when the eye is inside the sphere.
    public static func pointRadius(
        radius: Float, center: SIMD3<Float>, camera: OrbitCamera,
        viewportShortSide: Float, minimum: Float
    ) -> Float {
        let distance = simd_distance(camera.position, center)
        guard distance > radius else { return viewportShortSide }
        let projected = tan(asin(radius / distance)) / tan(camera.fieldOfView / 2) * viewportShortSide / 2
        return max(projected, minimum)
    }
}

/// Picks the sphere under a point the way the spheres are drawn: front-most visible disc first.
public enum PlanetaryPicker {
    /// One sphere as drawn on screen.
    public struct Disc: Sendable, Equatable {
        /// Points from the top-left (y down).
        public var center: SIMD2<Float>
        /// On-screen radius in points, after the minimum.
        public var radius: Float
        /// Eye distance to the sphere's center, which is the draw-sort key.
        public var depth: Float

        public init(center: SIMD2<Float>, radius: Float, depth: Float) {
            self.center = center
            self.radius = radius
            self.depth = depth
        }
    }

    /// The index into `discs` of the item under `point`:
    /// 1. Among the discs that contain `point` (distance to the center at most the radius), the one
    ///    with the smallest depth, which is the one drawn last in the far-to-near sort, so the
    ///    visible sphere wins.
    /// 2. Only if no disc contains `point`: the disc whose edge is nearest, within `tolerance`
    ///    points; ties (within `StarPicker.tieTolerance`) go to the smaller depth, then the lower index.
    ///
    /// Nil when neither finds one. Discs are not filtered here; the caller drops off-screen ones.
    public static func pick(_ point: SIMD2<Float>, in discs: [Disc], tolerance: Float) -> Int? {
        var front: Int?
        for (index, disc) in discs.enumerated() where simd_distance(disc.center, point) <= disc.radius {
            if let current = front, discs[current].depth <= disc.depth { continue }
            front = index
        }
        if let front { return front }

        let nearby = discs.enumerated()
            .map { (index: $0.offset, edge: simd_distance($0.element.center, point) - $0.element.radius, depth: $0.element.depth) }
            .filter { $0.edge <= tolerance }
        guard let closest = nearby.map(\.edge).min() else { return nil }
        return nearby
            .filter { $0.edge <= closest + StarPicker.tieTolerance }
            .min { ($0.depth, $0.index) < ($1.depth, $1.index) }?
            .index
    }
}

/// Which names to show in a Planetary System view, and in what order of importance.
public enum PlanetaryLabels {
    /// A moon's name is left out (unless the moon is selected) when its anchor is within this many
    /// points of its Parent's drawn edge on screen.
    public static let minimumMoonSeparation: Float = 14

    /// One candidate per entry that projects on screen; its `id` is the entry's index. The selected
    /// item is pinned. Priority is `rank × 1000 − on-screen radius`, where rank is 0 for the star,
    /// 1 for a planet, 2 for a dwarf planet, 3 for an asteroid or comet and 4 for a moon (any Body
    /// whose Parent is a Body). Lower goes first. A moon crowded against its Parent has no candidate
    /// unless it is selected. `labelSizes` runs parallel to `snapshot.entries`.
    public static func candidates(
        for snapshot: PlanetarySceneSnapshot, in system: PlanetarySystem, camera: OrbitCamera,
        viewportSize: SIMD2<Float>, labelSizes: [SIMD2<Float>], minimumPointRadius: Float,
        selection: PlanetarySystemItem?
    ) -> [LabelCandidate] {
        guard viewportSize.x > 0, viewportSize.y > 0 else { return [] }
        let viewProjection = camera.viewProjection(aspectRatio: viewportSize.x / viewportSize.y)
        let shortSide = min(viewportSize.x, viewportSize.y)

        struct Placed {
            var anchor: SIMD2<Float>
            var radius: Float
        }
        var placed = [Placed?](repeating: nil, count: snapshot.entries.count)
        var indexByItem: [PlanetarySystemItem: Int] = [:]
        for (index, entry) in snapshot.entries.enumerated() {
            indexByItem[entry.item] = index
            guard let anchor = camera.project(entry.position, viewProjection: viewProjection, viewportSize: viewportSize),
                  anchor.x >= 0, anchor.x <= viewportSize.x, anchor.y >= 0, anchor.y <= viewportSize.y
            else { continue }
            let radius = SphereProjection.pointRadius(
                radius: entry.radius, center: entry.position, camera: camera,
                viewportShortSide: shortSide, minimum: minimumPointRadius
            )
            placed[index] = Placed(anchor: anchor, radius: radius)
        }

        var candidates: [LabelCandidate] = []
        for (index, entry) in snapshot.entries.enumerated() {
            guard let own = placed[index] else { continue }
            let isSelected = entry.item == selection
            var rank: Float = 0
            if case .body(let name) = entry.item, let body = system.body(named: name) {
                switch body.kind {
                case .planet: rank = 1
                case .dwarfPlanet: rank = 2
                case .asteroid, .comet: rank = 3
                case .moon: rank = 4
                }
                if case .body(let parentName) = body.parent {
                    // Any Body whose Parent is a Body counts as a moon.
                    rank = 4
                    if !isSelected, let parentIndex = indexByItem[.body(parentName)], let parent = placed[parentIndex],
                       simd_distance(own.anchor, parent.anchor) - parent.radius <= minimumMoonSeparation {
                        continue
                    }
                }
            }
            candidates.append(LabelCandidate(
                id: index, anchor: own.anchor, radius: own.radius,
                size: index < labelSizes.count ? labelSizes[index] : .zero,
                priority: rank * 1_000 - own.radius, isPinned: isSelected
            ))
        }
        return candidates
    }
}

/// Everything about a Planetary System view except drawing: the layout, clock, camera, following
/// and flights. Time is passed in, so tests drive it without a display.
///
/// Positions are worked out in `Double` and drawn relative to an `origin`, which is the followed
/// item's position, so close-ups stay steady even in True scale. The camera's `target` is relative
/// to that origin.
public struct PlanetarySceneState: Sendable {
    /// Seconds a flight to an item takes.
    public static let flightDuration: Double = 0.8
    /// The near clip plane, as a share of the camera's distance.
    public static let nearPlaneFraction: Float = 0.01
    /// The far clip plane lies this many extents beyond the camera's distance.
    public static let farPlaneExtents: Float = 3
    /// The farthest the camera may get from its target, in extents.
    public static let maximumDistanceExtents: Float = 20

    public let system: PlanetarySystem
    public private(set) var layout: PlanetarySystemLayout

    public var scale: PlanetarySystemScale { layout.scale }

    /// The clock. Setting one whose `isPaused` goes from true to false clears the time baseline, so
    /// the next `step(to:)` only records the time (no frames arrive while paused, and the paused
    /// interval must not count). Changing only the speed or the day keeps the baseline.
    public var clock: SimulationClock {
        didSet {
            if oldValue.isPaused, !clock.isPaused { lastStepTime = nil }
        }
    }

    /// Smallest on-screen sphere radius, in points; the shader uses the same value.
    public var minimumPointRadius: Float = 2.5

    /// The camera. Its target is relative to `origin`. Every change re-fits the clip planes:
    /// near = distance × `nearPlaneFraction`, far = distance + `farPlaneExtents` × the layout's extent.
    public var camera: OrbitCamera {
        didSet {
            // Assigning inside the observer replaces the value just set, without observing again.
            camera = Self.clipPlanesFitted(camera, extent: layout.extent)
        }
    }

    /// The world point (scene units) that GPU positions are relative to.
    public private(set) var origin: SIMD3<Double> = .zero

    /// The item the camera follows, set when a flight lands. Nil after a pan, a reset or a cancelled flight.
    public private(set) var followed: PlanetarySystemItem?

    public var isFlying: Bool { flight != nil }

    private struct Flight: Sendable {
        let item: PlanetarySystemItem
        /// The world point the camera looked at when the flight began.
        let fromTarget: SIMD3<Double>
        let fromDistance: Float
        let toDistance: Float
        let start: Double
        let duration: Double
    }
    private var flight: Flight?
    private var lastStepTime: Double?

    /// Starts at the home view: origin 0, target 0, orientation `OrbitCamera.home`, and the distance
    /// from `camera.center(on: .zero, span: homeSpan)`. Distance limits are
    /// `2 × smallestDrawnRadius` to `maximumDistanceExtents × extent`.
    public init(system: PlanetarySystem, scale: PlanetarySystemScale = .compressed, clock: SimulationClock = SimulationClock()) {
        self.system = system
        self.clock = clock
        let layout = PlanetarySystemLayout(system: system, scale: scale)
        self.layout = layout
        camera = Self.clipPlanesFitted(Self.homeCamera(for: layout, from: OrbitCamera()), extent: layout.extent)
    }

    // MARK: Time

    /// Advances to `time` (monotonic seconds). With no baseline (the first call, or the first after
    /// unpausing) the clock only records the time. After that: the clock advances by the elapsed
    /// time, then any flight, then the origin follows the followed item. Every call, paused or not,
    /// records `time` as the new baseline.
    public mutating func step(to time: Double) {
        if let lastStepTime {
            clock.advance(bySeconds: time - lastStepTime)
        }
        lastStepTime = time
        advanceFlight(to: time)
        if let followed, let position = layout.position(of: followed, atDay: clock.day) {
            origin = position
        }
    }

    private mutating func advanceFlight(to time: Double) {
        guard let flight else { return }
        guard let itemPosition = layout.position(of: flight.item, atDay: clock.day) else {
            self.flight = nil
            return
        }
        let progress = min(max((time - flight.start) / flight.duration, 0), 1)
        if progress >= 1 {
            self.flight = nil
            follow(flight.item, at: itemPosition, distance: flight.toDistance)
            return
        }
        let eased = progress * progress * (3 - 2 * progress)
        // Aim at where the item is now, so the flight lands on a moving Body. The origin goes with
        // the aim point, which keeps every drawn position small and the camera's target at 0.
        origin = flight.fromTarget + (itemPosition - flight.fromTarget) * eased
        var camera = self.camera
        camera.target = .zero
        // Interpolate distance in log space so zooming in feels even.
        let from = log(Double(flight.fromDistance)), to = log(Double(flight.toDistance))
        camera.distance = Float(exp(from + (to - from) * eased))
        self.camera = camera
    }

    // MARK: Moving the camera

    /// Glides to `item` and then follows it. The target point is the item's position each step, so
    /// the flight lands on a moving Body. The distance is interpolated in log space to the item's
    /// viewing distance (`viewingSpan / 2 / tan(fov / 2)`), with smoothstep easing. Sets the
    /// distance limits for the item: the lower limit is twice its drawn radius. Does nothing for an
    /// item that is not in the system.
    public mutating func fly(to item: PlanetarySystemItem, at time: Double, duration: Double = flightDuration) {
        guard layout.position(of: item, atDay: clock.day) != nil, let distance = viewingDistance(of: item) else { return }
        flight = Flight(
            item: item,
            fromTarget: origin + SIMD3<Double>(camera.target),
            fromDistance: camera.distance,
            toDistance: distance,
            start: time,
            duration: max(duration, 0.01)
        )
        followed = nil
        camera.distanceLimits = limits(forItem: item)
    }

    /// Stops a flight where it is. The item is not followed.
    public mutating func cancelFlight() {
        flight = nil
    }

    /// Pans like `OrbitCamera.pan` and stops following (and flying). The origin stays put.
    public mutating func pan(byPoints points: SIMD2<Float>, viewportShortSide: Float) {
        flight = nil
        followed = nil
        camera.pan(byPoints: points, viewportShortSide: viewportShortSide)
    }

    /// Back to the home view, following nothing, with no flight. The clock is unchanged.
    public mutating func resetView() {
        flight = nil
        goHome()
    }

    /// Rebuilds the layout. Any flight lands at once. When following an item (or flying to one),
    /// it keeps following it: the origin is its new position and the distance its viewing distance
    /// in the new scale. Otherwise the view goes to the new scale's home view. The clock is unchanged.
    public mutating func setScale(_ scale: PlanetarySystemScale) {
        guard scale != layout.scale else { return }
        let item = flight?.item ?? followed
        flight = nil
        layout = PlanetarySystemLayout(system: system, scale: scale)
        if let item, let position = layout.position(of: item, atDay: clock.day), let distance = viewingDistance(of: item) {
            camera.distanceLimits = limits(forItem: item)
            follow(item, at: position, distance: distance)
        } else {
            goHome()
        }
    }

    private mutating func goHome() {
        followed = nil
        origin = .zero
        camera = Self.homeCamera(for: layout, from: camera)
    }

    /// Centers on `item` at `position` and follows it from `distance`.
    private mutating func follow(_ item: PlanetarySystemItem, at position: SIMD3<Double>, distance: Float) {
        followed = item
        origin = position
        var camera = self.camera
        camera.target = .zero
        camera.distance = distance
        self.camera = camera
    }

    /// The distance at which `item` fills its viewing span.
    private func viewingDistance(of item: PlanetarySystemItem) -> Float? {
        guard let span = layout.viewingSpan(of: item) else { return nil }
        return Float(span / 2 / tan(Double(camera.fieldOfView) / 2))
    }

    private func limits(forItem item: PlanetarySystemItem) -> ClosedRange<Float> {
        let radius = Float(2 * (layout.drawnRadius(of: item) ?? layout.smallestDrawnRadius))
        let upper = Float(Double(Self.maximumDistanceExtents) * layout.extent)
        return min(radius, upper)...upper
    }

    private static func homeCamera(for layout: PlanetarySystemLayout, from base: OrbitCamera) -> OrbitCamera {
        var camera = base
        camera.target = .zero
        camera.orientation = OrbitCamera.home
        let lower = Float(2 * layout.smallestDrawnRadius)
        let upper = Float(Double(maximumDistanceExtents) * layout.extent)
        camera.distanceLimits = min(lower, upper)...upper
        camera.center(on: .zero, span: Float(layout.homeSpan))
        return camera
    }

    /// The camera with its clip planes fitted to its distance and the scene's extent.
    private static func clipPlanesFitted(_ camera: OrbitCamera, extent: Double) -> OrbitCamera {
        var fitted = camera
        fitted.nearPlane = camera.distance * nearPlaneFraction
        fitted.farPlane = camera.distance + farPlaneExtents * Float(extent)
        return fitted
    }

    // MARK: Frames and picking

    /// The current frame: the layout at the clock's day, relative to the origin.
    public func snapshot() -> PlanetarySceneSnapshot {
        PlanetarySceneSnapshot(layout: layout, day: clock.day, origin: origin)
    }

    /// The item under `point` (points from the top-left, y down): `PlanetaryPicker.pick` over the
    /// entries that project on screen (in front of the eye, before the far plane, center inside the
    /// viewport), with radii from `SphereProjection.pointRadius` at `minimumPointRadius` and depth
    /// as the eye distance, which are the values the renderer sorts and sizes by.
    public func item(at point: SIMD2<Float>, viewportSize: SIMD2<Float>, tolerance: Float = 20) -> PlanetarySystemItem? {
        guard viewportSize.x > 0, viewportSize.y > 0 else { return nil }
        let snapshot = snapshot()
        let viewProjection = camera.viewProjection(aspectRatio: viewportSize.x / viewportSize.y)
        let eye = camera.position
        let shortSide = min(viewportSize.x, viewportSize.y)
        var discs: [PlanetaryPicker.Disc] = []
        var items: [PlanetarySystemItem] = []
        for entry in snapshot.entries {
            guard let center = camera.project(entry.position, viewProjection: viewProjection, viewportSize: viewportSize),
                  center.x >= 0, center.x <= viewportSize.x, center.y >= 0, center.y <= viewportSize.y
            else { continue }
            discs.append(PlanetaryPicker.Disc(
                center: center,
                radius: SphereProjection.pointRadius(
                    radius: entry.radius, center: entry.position, camera: camera,
                    viewportShortSide: shortSide, minimum: minimumPointRadius
                ),
                depth: simd_distance(eye, entry.position)
            ))
            items.append(entry.item)
        }
        return PlanetaryPicker.pick(point, in: discs, tolerance: tolerance).map { items[$0] }
    }
}
