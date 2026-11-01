import simd

/// Finds the star under a point on screen.
public enum StarPicker {
    /// Index of the star whose center projects nearest to `point` (points, y down), within
    /// `maxDistance` points. Stars behind the camera are ignored. Stars within half a point of
    /// each other on screen count as a tie, which goes to the one nearer the camera.
    public static func nearest(
        to point: SIMD2<Float>,
        in positions: [SIMD3<Float>],
        camera: OrbitCamera,
        viewportSize: SIMD2<Float>,
        maxDistance: Float = 20
    ) -> Int? {
        var best: (index: Int, screenDistance: Float, depth: Float)?
        let eye = camera.position
        for (index, position) in positions.enumerated() {
            guard let projected = camera.project(position, viewportSize: viewportSize) else { continue }
            let screenDistance = simd_distance(projected, point)
            guard screenDistance <= maxDistance else { continue }
            let depth = simd_distance(position, eye)
            if let current = best {
                let tied = abs(screenDistance - current.screenDistance) < 0.5
                if tied ? depth >= current.depth : screenDistance > current.screenDistance {
                    continue
                }
            }
            best = (index, screenDistance, depth)
        }
        return best?.index
    }
}
