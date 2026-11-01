import simd

/// A camera that circles a target point. Orientation is a quaternion, so rotation has no gimbal lock.
///
/// World space is the catalog's equatorial frame: +z toward the north celestial pole.
public struct OrbitCamera: Sendable, Equatable {
    /// The point the camera looks at and orbits, in light years.
    public var target: SIMD3<Float> = .zero
    /// Distance from the target, in light years.
    public var distance: Float = 450
    /// Rotation from camera space (looking down -z, +y up) into world space.
    public var orientation: simd_quatf = OrbitCamera.northUp
    /// Field of view across the shorter side of the viewport (height in landscape, width in portrait), in radians.
    public var fieldOfView: Float = .pi / 3
    public var nearPlane: Float = 0.05
    public var farPlane: Float = 5_000

    /// Looks at the target from the -y side, with the north celestial pole up.
    public static let northUp = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))

    public init() {}

    /// Camera position in world space.
    public var position: SIMD3<Float> {
        target + orientation.act(SIMD3(0, 0, distance))
    }

    /// Camera up direction in world space.
    public var up: SIMD3<Float> {
        orientation.act(SIMD3(0, 1, 0))
    }

    public var viewMatrix: simd_float4x4 {
        .lookAt(eye: position, target: target, up: up)
    }

    public func projectionMatrix(aspectRatio: Float) -> simd_float4x4 {
        .perspective(fieldOfView: fieldOfView, aspectRatio: aspectRatio, near: nearPlane, far: farPlane)
    }

    public func viewProjection(aspectRatio: Float) -> simd_float4x4 {
        projectionMatrix(aspectRatio: aspectRatio) * viewMatrix
    }

    /// Where a world point lands in a viewport, in points from the top-left corner (y down).
    /// Returns nil for points behind the camera or outside the near and far planes.
    public func project(_ point: SIMD3<Float>, viewportSize: SIMD2<Float>) -> SIMD2<Float>? {
        guard viewportSize.x > 0, viewportSize.y > 0 else { return nil }
        let clip = viewProjection(aspectRatio: viewportSize.x / viewportSize.y) * SIMD4(point, 1)
        guard clip.w > nearPlane, clip.w < farPlane else { return nil }
        let ndc = SIMD2(clip.x, clip.y) / clip.w
        return SIMD2((ndc.x + 1) / 2 * viewportSize.x, (1 - ndc.y) / 2 * viewportSize.y)
    }

    // MARK: Manipulation

    /// Closest and farthest the camera may get to its target, in light years.
    public static let distanceRange: ClosedRange<Float> = 0.5...2_000

    /// Camera right direction in world space.
    public var right: SIMD3<Float> {
        orientation.act(SIMD3(1, 0, 0))
    }

    /// Orbits around the target so the scene follows a drag. `angles` is in radians,
    /// in screen convention: +x is a drag to the right, +y a drag downward.
    public mutating func rotate(by angles: SIMD2<Float>) {
        let yaw = simd_quatf(angle: -angles.x, axis: SIMD3(0, 1, 0))
        let pitch = simd_quatf(angle: -angles.y, axis: SIMD3(1, 0, 0))
        orientation = simd_normalize(orientation * yaw * pitch)
    }

    /// Spins the view about its line of sight, in radians (counterclockwise on screen when positive).
    public mutating func roll(by angle: Float) {
        orientation = simd_normalize(orientation * simd_quatf(angle: -angle, axis: SIMD3(0, 0, 1)))
    }

    /// Multiplies the distance to the target: below 1 moves closer, above 1 moves away.
    public mutating func zoom(by factor: Float) {
        guard factor.isFinite, factor > 0 else { return }
        distance = min(max(distance * factor, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
    }

    /// Slides the target so the scene follows a drag of `points` (screen convention, +y downward)
    /// in a viewport whose shorter side is `viewportShortSide` points.
    public mutating func pan(byPoints points: SIMD2<Float>, viewportShortSide: Float) {
        guard viewportShortSide > 0 else { return }
        let worldPerPoint = 2 * distance * tan(fieldOfView / 2) / viewportShortSide
        target += (-right * points.x + up * points.y) * worldPerPoint
    }

    /// Back to the default view of the whole catalog.
    public mutating func reset() {
        let home = OrbitCamera()
        target = home.target
        distance = home.distance
        orientation = home.orientation
    }
}

extension simd_float4x4 {
    /// Right-handed view matrix.
    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(target - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)
        return simd_float4x4(columns: (
            SIMD4(s.x, u.x, -f.x, 0),
            SIMD4(s.y, u.y, -f.y, 0),
            SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }

    /// Right-handed perspective projection with Metal's 0...1 depth range.
    /// The field of view spans the shorter side, so the same scene fits in landscape and portrait.
    static func perspective(fieldOfView: Float, aspectRatio: Float, near: Float, far: Float) -> simd_float4x4 {
        let scale = 1 / tan(fieldOfView / 2)
        let xs = aspectRatio >= 1 ? scale / aspectRatio : scale
        let ys = aspectRatio >= 1 ? scale : scale * aspectRatio
        let zs = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4(xs, 0, 0, 0),
            SIMD4(0, ys, 0, 0),
            SIMD4(0, 0, zs, -1),
            SIMD4(0, 0, zs * near, 0)
        ))
    }
}
