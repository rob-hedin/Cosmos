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
    /// Vertical field of view, in radians.
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
    static func perspective(fieldOfView: Float, aspectRatio: Float, near: Float, far: Float) -> simd_float4x4 {
        let ys = 1 / tan(fieldOfView / 2)
        let xs = ys / aspectRatio
        let zs = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4(xs, 0, 0, 0),
            SIMD4(0, ys, 0, 0),
            SIMD4(0, 0, zs, -1),
            SIMD4(0, 0, zs * near, 0)
        ))
    }
}
