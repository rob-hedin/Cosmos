import simd
import Testing
@testable import StarRenderer

@Suite struct StarPickerTests {
    let viewport = SIMD2<Float>(800, 600)

    @Test func targetProjectsToViewportCenter() throws {
        let p = try #require(OrbitCamera().project(.zero, viewportSize: viewport))
        #expect(abs(p.x - 400) < 1e-3 && abs(p.y - 300) < 1e-3)
    }

    @Test func northProjectsAboveCenter() throws {
        let p = try #require(OrbitCamera().project(SIMD3(0, 0, 50), viewportSize: viewport))
        #expect(p.y < 300) // y grows downward
    }

    @Test func pointsBehindCameraDoNotProject() {
        let camera = OrbitCamera()
        let behind = camera.position * 2 // twice as far out, behind the eye
        #expect(camera.project(behind, viewportSize: viewport) == nil)
    }

    @Test func picksNearestStarWithinTolerance() throws {
        let camera = OrbitCamera()
        let positions: [SIMD3<Float>] = [.zero, SIMD3(40, 0, 0), SIMD3(0, 0, 40)]
        let second = try #require(camera.project(positions[1], viewportSize: viewport))

        #expect(StarPicker.nearest(to: SIMD2(400, 300), in: positions, camera: camera, viewportSize: viewport) == 0)
        #expect(StarPicker.nearest(to: second + SIMD2(5, -5), in: positions, camera: camera, viewportSize: viewport) == 1)
        #expect(StarPicker.nearest(to: SIMD2(10, 10), in: positions, camera: camera, viewportSize: viewport) == nil)
    }

    @Test func overlappingStarsPreferTheNearerOne() {
        let camera = OrbitCamera()
        // Both on the line of sight through the target; index 1 is closer to the camera.
        let towardCamera = simd_normalize(camera.position - camera.target)
        let positions = [camera.target - towardCamera * 50, camera.target + towardCamera * 50]
        #expect(StarPicker.nearest(to: SIMD2(400, 300), in: positions, camera: camera, viewportSize: viewport) == 1)
    }

    @Test func ignoresStarsBehindCamera() {
        let camera = OrbitCamera()
        let positions = [camera.position * 2]
        #expect(StarPicker.nearest(to: SIMD2(400, 300), in: positions, camera: camera, viewportSize: viewport) == nil)
    }
}
