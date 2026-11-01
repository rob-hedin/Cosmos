import simd

/// Finds the star under a point on screen.
public enum StarPicker {
    /// Screen distances within this many points of the closest count as a tie.
    public static let tieTolerance: Float = 0.5

    /// Index of the visible star whose center projects nearest to `point` (points, y down),
    /// within `maxDistance` points. Stars behind the camera, past the far plane or centered off
    /// screen are ignored. Among stars within `tieTolerance` of the closest, the one nearest the
    /// camera wins, so the result doesn't depend on the order of `positions`.
    public static func nearest(
        to point: SIMD2<Float>,
        in positions: [SIMD3<Float>],
        camera: OrbitCamera,
        viewportSize: SIMD2<Float>,
        maxDistance: Float = 20
    ) -> Int? {
        let eye = camera.position
        var candidates: [(index: Int, screenDistance: Float, depth: Float)] = []
        for (index, position) in positions.enumerated() {
            guard let projected = camera.project(position, viewportSize: viewportSize),
                  projected.x >= 0, projected.x <= viewportSize.x,
                  projected.y >= 0, projected.y <= viewportSize.y
            else { continue }
            let screenDistance = simd_distance(projected, point)
            guard screenDistance <= maxDistance else { continue }
            candidates.append((index, screenDistance, simd_distance(position, eye)))
        }
        guard let closest = candidates.map(\.screenDistance).min() else { return nil }
        return candidates
            .filter { $0.screenDistance <= closest + tieTolerance }
            .min { ($0.depth, $0.index) < ($1.depth, $1.index) }?
            .index
    }
}
