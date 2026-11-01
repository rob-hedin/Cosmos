import simd

/// Finds the star under a point on screen.
public enum StarPicker {
    /// Screen distances within this many points of the closest count as a tie.
    public static let tieTolerance: Float = 0.5

    /// Index of the visible star nearest to `point` (points, y down), within `maxDistance` points.
    /// Distance is measured to the edge of each star's drawn disc when `radii` (points, in
    /// `positions` order) is given, so a tap anywhere on a big bright star picks it rather than a
    /// faint star nearby. Stars behind the camera, past the far plane or centered off screen are
    /// ignored. Among stars within `tieTolerance` of the closest, the biggest disc wins, then the
    /// one nearest the camera, so the result doesn't depend on the order of `positions`.
    public static func nearest(
        to point: SIMD2<Float>,
        in positions: [SIMD3<Float>],
        radii: [Float]? = nil,
        camera: OrbitCamera,
        viewportSize: SIMD2<Float>,
        maxDistance: Float = 20
    ) -> Int? {
        let eye = camera.position
        let viewProjection = camera.viewProjection(aspectRatio: viewportSize.x / max(viewportSize.y, 1))
        var candidates: [(index: Int, screenDistance: Float, radius: Float, depth: Float)] = []
        for (index, position) in positions.enumerated() {
            guard let projected = camera.project(position, viewProjection: viewProjection, viewportSize: viewportSize),
                  projected.x >= 0, projected.x <= viewportSize.x,
                  projected.y >= 0, projected.y <= viewportSize.y
            else { continue }
            let radius = radii.map { index < $0.count ? $0[index] : 0 } ?? 0
            let screenDistance = max(simd_distance(projected, point) - radius, 0)
            guard screenDistance <= maxDistance else { continue }
            candidates.append((index, screenDistance, radius, simd_distance(position, eye)))
        }
        guard let closest = candidates.map(\.screenDistance).min() else { return nil }
        return candidates
            .filter { $0.screenDistance <= closest + tieTolerance }
            .min { (-$0.radius, $0.depth, $0.index) < (-$1.radius, $1.depth, $1.index) }?
            .index
    }
}
