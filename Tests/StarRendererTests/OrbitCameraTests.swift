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
