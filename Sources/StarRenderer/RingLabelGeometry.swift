import simd

/// Where to label a reference ring centered on the origin in the z = 0 plane.
enum RingLabelGeometry {
    /// The point where a ring of `radius` crosses the horizontal screen line through the origin,
    /// on the right-hand side. That screen line, seen from `eye`, is the plane through the eye that
    /// contains the camera's `right` direction and the origin. Nil when the ring doesn't cross the
    /// plane (it lies wholly above or below the line), or the crossing is behind the camera.
    static func point(radius: Float, eye: SIMD3<Float>, right: SIMD3<Float>, forward: SIMD3<Float>) -> SIMD3<Float>? {
        let normal = simd_cross(right, -eye)
        let inPlane = SIMD2(normal.x, normal.y)
        let reach = radius * simd_length(inPlane)
        guard reach > 1e-6 else { return nil }
        // radius * (n.x cos θ + n.y sin θ) = n · eye
        let cosine = simd_dot(normal, eye) / reach
        guard abs(cosine) <= 1 else { return nil }
        let center = atan2(inPlane.y, inPlane.x)
        let spread = acos(cosine)
        let crossings = [center + spread, center - spread].map { radius * SIMD3(cos($0), sin($0), 0) }
        // Rightmost on screen: horizontal screen position goes with (right · v) / (forward · v).
        func screenX(_ point: SIMD3<Float>) -> Float {
            let v = point - eye
            return simd_dot(v, right) / simd_dot(v, forward)
        }
        return crossings
            .filter { simd_dot($0 - eye, forward) > 0 }
            .max { screenX($0) < screenX($1) }
    }
}
