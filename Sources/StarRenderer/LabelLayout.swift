import simd

/// A label that would like a place on screen.
public struct LabelCandidate: Sendable, Equatable {
    public var id: Int
    /// Where the star is, in points from the top-left (y down).
    public var anchor: SIMD2<Float>
    /// Radius of the star's drawn disc, in points; the label starts just past it.
    public var radius: Float
    /// Label size in points.
    public var size: SIMD2<Float>
    /// Lower goes first. The renderer uses apparent magnitude from the camera, so brighter wins.
    public var priority: Float
    /// A pinned label (the selected star's) is always placed: it goes first, moves to the left of
    /// its star if the right side doesn't fit, and is kept inside the viewport as a last resort.
    public var isPinned: Bool

    public init(
        id: Int, anchor: SIMD2<Float>, radius: Float, size: SIMD2<Float>, priority: Float, isPinned: Bool = false
    ) {
        self.id = id
        self.anchor = anchor
        self.radius = radius
        self.size = size
        self.priority = priority
        self.isPinned = isPinned
    }
}

/// Places labels to the right of their stars, most important first, skipping any that would
/// overlap a placed label or leave the viewport. Pinned labels go first and are never skipped.
public enum LabelLayout {
    /// A rectangle in points from the top-left (y down).
    public struct Rect: Sendable, Equatable {
        public var origin: SIMD2<Float>
        public var size: SIMD2<Float>

        public init(origin: SIMD2<Float>, size: SIMD2<Float>) {
            self.origin = origin
            self.size = size
        }
    }

    public struct Placement: Sendable, Equatable {
        public var id: Int
        /// Top-left corner of the label, in points.
        public var origin: SIMD2<Float>
    }

    public static func place(
        _ candidates: [LabelCandidate],
        in viewport: SIMD2<Float>,
        insets: SIMD4<Float> = .zero,
        avoiding obstacles: [Rect] = [],
        maxCount: Int,
        gap: Float = 3,
        spacing: Float = 2
    ) -> [Placement] {
        let pinned = candidates.filter(\.isPinned)
        let ordered = pinned + candidates.filter { !$0.isPinned }.sorted { ($0.priority, $0.id) < ($1.priority, $1.id) }
        // Usable area: the viewport less insets (top, left, bottom, right).
        let low = SIMD2(insets.y, insets.x)
        let high = viewport - SIMD2(insets.w, insets.z)
        var placed: [(placement: Placement, size: SIMD2<Float>)] = []
        var count = 0

        func overlaps(_ origin: SIMD2<Float>, _ size: SIMD2<Float>, _ other: SIMD2<Float>, _ otherSize: SIMD2<Float>) -> Bool {
            let far = origin + size
            let otherFar = other + otherSize
            return origin.x < otherFar.x + spacing && other.x < far.x + spacing
                && origin.y < otherFar.y + spacing && other.y < far.y + spacing
        }

        for candidate in ordered {
            let size = candidate.size
            let top = candidate.anchor.y - size.y / 2
            let right = SIMD2(candidate.anchor.x + candidate.radius + gap, top)

            if candidate.isPinned {
                // Try right, left, above and below the star for a spot that's on screen and clear of
                // obstacles. Failing that, pick a side by horizontal room and clamp onto the screen.
                let left = SIMD2(candidate.anchor.x - candidate.radius - gap - size.x, top)
                let centerX = candidate.anchor.x - size.x / 2
                let above = SIMD2(centerX, candidate.anchor.y - candidate.radius - gap - size.y)
                let below = SIMD2(centerX, candidate.anchor.y + candidate.radius + gap)
                // If the star is under an obstacle, also try just outside each of its edges.
                let besideObstacles = obstacles.flatMap { box -> [SIMD2<Float>] in
                    let far = box.origin + box.size
                    return [
                        SIMD2(far.x + gap, top),
                        SIMD2(centerX, box.origin.y - gap - size.y),
                        SIMD2(box.origin.x - gap - size.x, top),
                        SIMD2(centerX, far.y + gap),
                    ]
                }
                let clear = ([right, left, above, below] + besideObstacles).first { origin in
                    let far = origin + size
                    return origin.x >= low.x && origin.y >= low.y && far.x <= high.x && far.y <= high.y
                        && !obstacles.contains { overlaps(origin, size, $0.origin, $0.size) }
                }
                var origin = clear ?? (right.x + size.x <= high.x || left.x < low.x ? right : left)
                origin = simd_clamp(origin, low, simd_max(high - size, low))
                placed.append((Placement(id: candidate.id, origin: origin), size))
                count += 1
                continue
            }

            guard count < maxCount else { break }
            let origin = right
            let far = origin + size
            guard origin.x >= low.x, origin.y >= low.y, far.x <= high.x, far.y <= high.y else { continue }
            let blocked = placed.contains { overlaps(origin, size, $0.placement.origin, $0.size) }
                || obstacles.contains { overlaps(origin, size, $0.origin, $0.size) }
            if !blocked {
                placed.append((Placement(id: candidate.id, origin: origin), size))
                count += 1
            }
        }
        return placed.map(\.placement)
    }
}
