import simd
import Testing
@testable import StarRenderer

@Suite struct StarPickerSunTests {
    let viewport = SIMD2<Float>(800, 600)
    let sunRadius: Float = 9

    @Test func nearestHitPicksSunWhenItsMarkerIsWithinReach() throws {
        let camera = OrbitCamera()
        let origin = try #require(camera.project(.zero, viewportSize: viewport))
        let point = origin + SIMD2(5, 0)
        let distantStar = try position(atHorizontalOffset: 100, camera: camera, viewport: viewport)

        #expect(StarPicker.nearestHit(
            to: point,
            in: [distantStar],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        ) == .sun)
    }

    @Test func nearestHitReturnsStarIndexWhenAStarIsNearestAwayFromSun() throws {
        let camera = OrbitCamera()
        let position = try position(atHorizontalOffset: 120, camera: camera, viewport: viewport)
        let projected = try #require(camera.project(position, viewportSize: viewport))
        let point = projected + SIMD2(3, 0)
        let nearest = StarPicker.nearest(
            to: point,
            in: [position],
            camera: camera,
            viewportSize: viewport
        )

        let nearestIndex = try #require(nearest)
        #expect(nearestIndex == 0)
        #expect(StarPicker.nearestHit(
            to: point,
            in: [position],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        ) == .star(nearestIndex))
    }

    @Test func nearestHitReturnsNilBeyondStarsAndSunDisc() throws {
        let camera = OrbitCamera()
        let point = try #require(camera.project(.zero, viewportSize: viewport)) + SIMD2(31, 0)
        let distantStar = try position(atHorizontalOffset: 120, camera: camera, viewport: viewport)

        #expect(StarPicker.nearestHit(
            to: point,
            in: [distantStar],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        ) == nil)
    }

    @Test func nearestHitUsesTheLargerDiscToBreakSunAndStarTies() throws {
        let camera = OrbitCamera()
        let point = try #require(camera.project(.zero, viewportSize: viewport)) + SIMD2(2, 0)
        let nearbyStar = try position(atHorizontalOffset: 4, camera: camera, viewport: viewport)

        #expect(StarPicker.nearestHit(
            to: point,
            in: [nearbyStar],
            radii: [2],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        ) == .sun)

        #expect(StarPicker.nearestHit(
            to: point,
            in: [nearbyStar],
            radii: [20],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        ) == .star(0))
    }

    @Test func nearestHitNeverPicksSunWhenOriginIsBehindCamera() {
        var camera = OrbitCamera()
        let forward = camera.orientation.act(SIMD3<Float>(0, 0, 1))
        camera.target = -forward * 500

        #expect(camera.project(.zero, viewportSize: viewport) == nil)
        #expect(StarPicker.nearestHit(
            to: SIMD2(400, 300),
            in: [],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        ) == nil)
    }

    @Test func nearestHitNeverPicksSunWhenOriginIsOffScreen() throws {
        var camera = OrbitCamera()
        camera.target = camera.right * 1_000
        let projectedOrigin = try #require(camera.project(.zero, viewportSize: viewport))

        #expect(
            projectedOrigin.x < 0 || projectedOrigin.x > viewport.x
                || projectedOrigin.y < 0 || projectedOrigin.y > viewport.y
        )
        #expect(StarPicker.nearestHit(
            to: SIMD2(400, 300),
            in: [],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        ) == nil)
    }

    @Test func emptyPositionsCanHitSunButReturnNilFarFromIt() throws {
        let camera = OrbitCamera()
        let origin = try #require(camera.project(.zero, viewportSize: viewport))

        #expect(StarPicker.nearestHit(
            to: origin + SIMD2(5, 0),
            in: [],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        ) == .sun)
        #expect(StarPicker.nearestHit(
            to: origin + SIMD2(35, 0),
            in: [],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        ) == nil)
    }

    @Test func nilRadiiKeepTheSunRadiusAndMatchExplicitZeroRadii() throws {
        let camera = OrbitCamera()
        let origin = try #require(camera.project(.zero, viewportSize: viewport))
        let point = origin + SIMD2(25, 0)
        let distantStar = try position(atHorizontalOffset: 100, camera: camera, viewport: viewport)

        let withoutRadii = StarPicker.nearestHit(
            to: point,
            in: [distantStar],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        )
        let withZeroRadius = StarPicker.nearestHit(
            to: point,
            in: [distantStar],
            radii: [0],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        )

        #expect(withoutRadii == .sun)
        #expect(withZeroRadius == .sun)
        #expect(withoutRadii == withZeroRadius)
    }

    @Test func shortRadiiDoNotShiftTheSunRadiusOntoAMissingStarRadius() throws {
        let camera = OrbitCamera()
        let origin = try #require(camera.project(.zero, viewportSize: viewport))
        let point = origin + SIMD2(5, 0)
        let firstStar = try position(atHorizontalOffset: -100, camera: camera, viewport: viewport)
        let secondStar = try position(atHorizontalOffset: 17, camera: camera, viewport: viewport)

        #expect(StarPicker.nearestHit(
            to: point,
            in: [firstStar, secondStar],
            radii: [0],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        ) == .sun)

        let fullRadiiResult = StarPicker.nearestHit(
            to: point,
            in: [firstStar, secondStar],
            radii: [0, 20],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        )
        let longRadiiResult = StarPicker.nearestHit(
            to: point,
            in: [firstStar, secondStar],
            radii: [0, 20, 100],
            sunRadius: sunRadius,
            camera: camera,
            viewportSize: viewport
        )

        #expect(fullRadiiResult == .star(1))
        #expect(longRadiiResult == fullRadiiResult)
    }
}

private func position(
    atHorizontalOffset offset: Float,
    camera: OrbitCamera,
    viewport: SIMD2<Float>
) throws -> SIMD3<Float> {
    var lower: Float = 0
    var upper: Float = 1_000

    for _ in 0..<60 {
        let middle = (lower + upper) / 2
        let candidate = camera.target + camera.right * middle
        let projected = try #require(camera.project(candidate, viewportSize: viewport))
        if projected.x < viewport.x / 2 + offset {
            lower = middle
        } else {
            upper = middle
        }
    }

    return camera.target + camera.right * ((lower + upper) / 2)
}
