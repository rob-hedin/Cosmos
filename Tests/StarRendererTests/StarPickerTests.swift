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

    @Test func ignoresStarsCenteredOffScreen() {
        let camera = OrbitCamera()
        // Walk a point left until it lands just past the viewport's left edge, mid-height.
        var offScreen = SIMD3<Float>(-100, 0, 0)
        while let p = camera.project(offScreen, viewportSize: viewport), p.x >= -10 {
            offScreen.x -= 1
        }
        #expect(StarPicker.nearest(to: SIMD2(2, 300), in: [offScreen], camera: camera, viewportSize: viewport) == nil)
    }

    @Test func ignoresStarsBeyondTheFarPlane() {
        var camera = OrbitCamera()
        camera.farPlane = 100
        #expect(StarPicker.nearest(to: SIMD2(400, 300), in: [.zero], camera: camera, viewportSize: viewport) == nil)
    }

    @Test func resultDoesNotDependOnOrder() {
        let camera = OrbitCamera()
        let towardCamera = simd_normalize(camera.position - camera.target)
        // A chain of stars, each a little farther off the cursor on screen and a little nearer the camera.
        let positions: [SIMD3<Float>] = (0..<4).map { step in
            let s = Float(step)
            return camera.target + towardCamera * (10 * s) + camera.right * (0.15 * s)
        }
        let forward = StarPicker.nearest(to: SIMD2(400, 300), in: positions, camera: camera, viewportSize: viewport)
        let backward = StarPicker.nearest(to: SIMD2(400, 300), in: Array(positions.reversed()), camera: camera, viewportSize: viewport)
            .map { positions.count - 1 - $0 }
        #expect(forward != nil)
        #expect(forward == backward)
    }

    @Test func aBigDiscWinsOverAFaintStarInFront() throws {
        let camera = OrbitCamera()
        // A faint star much closer to the camera, a few points from a bright star's center on screen.
        let bright = SIMD3<Float>.zero
        let brightOnScreen = try #require(camera.project(bright, viewportSize: viewport))
        let faint = camera.position * 0.05 + camera.right * 4
        let faintOnScreen = try #require(camera.project(faint, viewportSize: viewport))
        let tap = brightOnScreen + (faintOnScreen - brightOnScreen) / 2
        let positions = [faint, bright]
        #expect(StarPicker.nearest(to: tap, in: positions, camera: camera, viewportSize: viewport) == 0)
        // With the bright star's 10 pt disc under the tap, it wins.
        let withSizes = StarPicker.nearest(to: tap, in: positions, radii: [0.75, 10], camera: camera, viewportSize: viewport)
        #expect(withSizes == 1)
    }

    @Test func discRadiusExtendsTheReach() throws {
        let camera = OrbitCamera()
        let onScreen = try #require(camera.project(.zero, viewportSize: viewport))
        let tap = onScreen + SIMD2(25, 0)
        #expect(StarPicker.nearest(to: tap, in: [.zero], camera: camera, viewportSize: viewport) == nil)
        #expect(StarPicker.nearest(to: tap, in: [.zero], radii: [10], camera: camera, viewportSize: viewport) == 0)
    }

    @Test func theBiggerDiscWinsWhenBothCoverTheTap() throws {
        let camera = OrbitCamera()
        let bright = SIMD3<Float>.zero
        let tap = try #require(camera.project(bright, viewportSize: viewport))
        // A smaller disc, nearer the camera, also covering the tap point.
        let small = camera.position * 0.05 + camera.right * 1
        #expect(StarPicker.nearest(to: tap, in: [small, bright], radii: [3, 10], camera: camera, viewportSize: viewport) == 1)
        #expect(StarPicker.nearest(to: tap, in: [bright, small], radii: [10, 3], camera: camera, viewportSize: viewport) == 0)
        // With equal discs, the nearer star wins.
        #expect(StarPicker.nearest(to: tap, in: [small, bright], radii: [10, 10], camera: camera, viewportSize: viewport) == 0)
        #expect(StarPicker.nearest(to: tap, in: [bright, small], radii: [10, 10], camera: camera, viewportSize: viewport) == 1)
    }
}
