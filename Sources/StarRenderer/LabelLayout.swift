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
    public struct Placement: Sendable, Equatable {
        public var id: Int
        /// Top-left corner of the label, in points.
        public var origin: SIMD2<Float>
    }

    public static func place(
        _ candidates: [LabelCandidate],
        in viewport: SIMD2<Float>,
        maxCount: Int,
        gap: Float = 3,
        spacing: Float = 2
    ) -> [Placement] {
        let pinned = candidates.filter(\.isPinned)
        let ordered = pinned + candidates.filter { !$0.isPinned }.sorted { ($0.priority, $0.id) < ($1.priority, $1.id) }
        var placed: [(placement: Placement, size: SIMD2<Float>)] = []

        func fits(_ origin: SIMD2<Float>, _ size: SIMD2<Float>) -> Bool {
            let far = origin + size
            return origin.x >= 0 && origin.y >= 0 && far.x <= viewport.x && far.y <= viewport.y
        }

        for candidate in ordered {
            let size = candidate.size
            let top = candidate.anchor.y - size.y / 2
            let right = SIMD2(candidate.anchor.x + candidate.radius + gap, top)

            if candidate.isPinned {
                let left = SIMD2(candidate.anchor.x - candidate.radius - gap - size.x, top)
                var origin = fits(right, size) ? right : fits(left, size) ? left : right
                origin = simd_clamp(origin, .zero, simd_max(viewport - size, .zero))
                placed.append((Placement(id: candidate.id, origin: origin), size))
                continue
            }

            guard placed.count < maxCount else { break }
            let origin = right
            let far = origin + size
            guard fits(origin, size) else { continue }
            let overlaps = placed.contains { other in
                let otherFar = other.placement.origin + other.size
                return origin.x < otherFar.x + spacing && other.placement.origin.x < far.x + spacing
                    && origin.y < otherFar.y + spacing && other.placement.origin.y < far.y + spacing
            }
            if !overlaps {
                placed.append((Placement(id: candidate.id, origin: origin), size))
            }
        }
        return placed.map(\.placement)
    }
}
