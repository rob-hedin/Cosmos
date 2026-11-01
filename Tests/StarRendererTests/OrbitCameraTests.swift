import simd
import Testing
@testable import StarRenderer

@Suite struct OrbitCameraTests {
    /// Projects a world point to normalized device coordinates.
    private func ndc(_ point: SIMD3<Float>, _ camera: OrbitCamera, aspect: Float = 1) -> SIMD3<Float> {
        let clip = camera.viewProjection(aspectRatio: aspect) * SIMD4(point, 1)
        return SIMD3(clip.x, clip.y, clip.z) / clip.w
    }

    @Test func targetIsAtScreenCenter() {
        let p = ndc(.zero, OrbitCamera())
        #expect(abs(p.x) < 1e-5 && abs(p.y) < 1e-5)
        #expect(p.z > 0 && p.z < 1)
    }

    @Test func northIsUpByDefault() {
        let p = ndc(SIMD3(0, 0, 50), OrbitCamera())
        #expect(p.y > 0)
        #expect(abs(p.x) < 1e-5)
    }

    @Test(arguments: [1.0, 16.0 / 9.0, 480.0 / 750.0, 390.0 / 844.0] as [Float])
    func defaultViewFitsTheWholeCatalog(aspect: Float) {
        let camera = OrbitCamera()
        for point: SIMD3<Float> in [[200, 0, 0], [-200, 0, 0], [0, 0, 200], [0, 0, -200]] {
            let p = ndc(point, camera, aspect: aspect)
            #expect(abs(p.x) <= 1 && abs(p.y) <= 1, "\(point) should be on screen at aspect \(aspect)")
        }
    }

    @Test func cameraSitsAtDistanceFromTarget() {
        var camera = OrbitCamera()
        camera.target = SIMD3(10, 20, 30)
        camera.distance = 42
        #expect(abs(simd_distance(camera.position, camera.target) - 42) < 1e-4)
    }

    @Test func defaultViewLooksDownSlightlyFromTheNorth() {
        let camera = OrbitCamera()
        #expect(camera.position.z > 0)
        #expect(camera.position.y < 0)
        // A point on the equator's plane in front of the Sun appears below it.
        #expect(ndc(SIMD3(0, -100, 0), camera).y < 0)
    }

    @Test func nearerPointsHaveSmallerDepth() {
        let camera = OrbitCamera()
        // The default camera sits on the -y side, so -y points are nearer.
        #expect(ndc(SIMD3(0, -100, 0), camera).z < ndc(SIMD3(0, 100, 0), camera).z)
    }

    @Test func shaderStructsHaveExpectedLayout() {
        #expect(MemoryLayout<StarInstance>.stride == 32)
        #expect(MemoryLayout<FrameUniforms>.stride == 96)
    }
}

@Suite struct CameraManipulationTests {
    private func ndc(_ point: SIMD3<Float>, _ camera: OrbitCamera) -> SIMD3<Float> {
        let clip = camera.viewProjection(aspectRatio: 1) * SIMD4(point, 1)
        return SIMD3(clip.x, clip.y, clip.z) / clip.w
    }

    /// A point halfway between the camera and its target, which an orbit moves with the drag.
    private func nearPoint(_ camera: OrbitCamera) -> SIMD3<Float> {
        (camera.position + camera.target) / 2
    }

    @Test func dragRightMovesNearSideRight() {
        var camera = OrbitCamera()
        let point = nearPoint(camera)
        camera.rotate(by: SIMD2(0.1, 0))
        #expect(ndc(point, camera).x > 0)
    }

    @Test func dragDownMovesNearSideDown() {
        var camera = OrbitCamera()
        let point = nearPoint(camera)
        camera.rotate(by: SIMD2(0, 0.1))
        #expect(ndc(point, camera).y < 0)
    }

    @Test func rotationKeepsDistanceAndTarget() {
        var camera = OrbitCamera()
        camera.rotate(by: SIMD2(1.3, -0.7))
        camera.roll(by: 0.4)
        #expect(abs(simd_distance(camera.position, camera.target) - camera.distance) < 1e-3)
        #expect(camera.target == .zero)
        #expect(abs(simd_length(camera.orientation.vector) - 1) < 1e-5)
    }

    @Test func zoomScalesAndClamps() {
        var camera = OrbitCamera()
        camera.zoom(by: 0.5)
        #expect(abs(camera.distance - 225) < 1e-3)
        camera.zoom(by: 1e-9)
        #expect(camera.distance == OrbitCamera.distanceRange.lowerBound)
        camera.zoom(by: 1e9)
        #expect(camera.distance == OrbitCamera.distanceRange.upperBound)
        camera.zoom(by: .nan)
        #expect(camera.distance == OrbitCamera.distanceRange.upperBound)
    }

    @Test func panMovesSceneWithDrag() {
        var camera = OrbitCamera()
        camera.pan(byPoints: SIMD2(50, 30), viewportShortSide: 500)
        let oldTarget = ndc(.zero, camera)
        #expect(oldTarget.x > 0) // dragged right
        #expect(oldTarget.y < 0) // dragged down
        // The scene moves exactly as far as the pointer: 50 of 500 points is 0.2 in NDC.
        #expect(abs(oldTarget.x - 0.2) < 1e-3)
    }

    @Test func resetRestoresHomeView() {
        var camera = OrbitCamera()
        camera.fieldOfView = 1
        camera.rotate(by: SIMD2(2, 1))
        camera.zoom(by: 0.1)
        camera.pan(byPoints: SIMD2(10, 10), viewportShortSide: 100)
        camera.reset()
        var expected = OrbitCamera()
        expected.fieldOfView = 1
        #expect(camera == expected)
    }

    @Test func centeringShowsTheRequestedSpan() {
        var camera = CameraFixtures.tilted
        camera.center(on: SIMD3(3, 4, 5), span: 20)
        #expect(camera.target == SIMD3(3, 4, 5))
        #expect(abs(camera.span - 20) < 1e-3)
        // A point 10 ly to the side of the target, in the view plane, lands on the shorter edge.
        let edge = camera.target + camera.up * 10
        let clip = camera.viewProjection(aspectRatio: 1) * SIMD4(edge, 1)
        #expect(abs(clip.y / clip.w - 1) < 1e-3)
    }

    @Test func fittingKeepsTheWholeSphereOnScreen() {
        var camera = CameraFixtures.tilted
        camera.fit(center: .zero, radius: 30)
        for direction: SIMD3<Float> in [[1, 0, 0], [0, 1, 0], [0, 0, 1], [-1, 0, 0], [0, -1, 0], [0, 0, -1]] {
            let clip = camera.viewProjection(aspectRatio: 1) * SIMD4(direction * 30, 1)
            #expect(clip.w > 0)
            #expect(abs(clip.x / clip.w) < 1 && abs(clip.y / clip.w) < 1)
        }
        // ...but not much more than that.
        #expect(camera.span < 2 * 30 * 1.6)
    }

    @Test func fittingASingleStopUsesTheMinimumSpan() {
        var camera = OrbitCamera()
        camera.fit(center: SIMD3(1, 1, 1), radius: 0, minimumSpan: 12)
        #expect(abs(camera.span - 12) < 1e-3)
    }
}

private enum CameraFixtures {
    static var tilted: OrbitCamera {
        var camera = OrbitCamera()
        camera.rotate(by: SIMD2(0.4, 0.3))
        return camera
    }
}
