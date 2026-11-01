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

    public init(id: Int, anchor: SIMD2<Float>, radius: Float, size: SIMD2<Float>, priority: Float) {
        self.id = id
        self.anchor = anchor
        self.radius = radius
        self.size = size
        self.priority = priority
    }
}

/// Places labels to the right of their stars, most important first, skipping any that would
/// overlap a placed label or leave the viewport.
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
        let ordered = candidates.sorted { ($0.priority, $0.id) < ($1.priority, $1.id) }
        var placed: [(placement: Placement, size: SIMD2<Float>)] = []
        for candidate in ordered {
            guard placed.count < maxCount else { break }
            let origin = SIMD2(candidate.anchor.x + candidate.radius + gap, candidate.anchor.y - candidate.size.y / 2)
            let far = origin + candidate.size
            guard origin.x >= 0, origin.y >= 0, far.x <= viewport.x, far.y <= viewport.y else { continue }
            let overlaps = placed.contains { other in
                let otherFar = other.placement.origin + other.size
                return origin.x < otherFar.x + spacing && other.placement.origin.x < far.x + spacing
                    && origin.y < otherFar.y + spacing && other.placement.origin.y < far.y + spacing
            }
            if !overlaps {
                placed.append((Placement(id: candidate.id, origin: origin), candidate.size))
            }
        }
        return placed.map(\.placement)
    }
}
