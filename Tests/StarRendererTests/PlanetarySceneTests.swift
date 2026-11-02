import Foundation
import simd
import Testing
import StarCatalog
@testable import StarRenderer

@Suite struct PlanetaryCameraLimitTests {
    @Test func cameraDistanceLimitsDefaultToTheExistingRangeAndClampEveryFitOperation() {
        var camera = OrbitCamera()
        #expect(camera.distanceLimits == OrbitCamera.distanceRange)

        camera.distanceLimits = 1e-5...100
        camera.distance = 1e-3
        camera.zoom(by: 0.1)
        #expect(abs(camera.distance - 1e-4) < 1e-10)
        camera.zoom(by: 0.01)
        #expect(camera.distance == 1e-5)
        camera.zoom(by: 1e9)
        #expect(camera.distance == 100)

        camera.center(on: SIMD3(1, 2, 3), span: 1e-5)
        #expect(camera.distance == 1e-5)
        camera.center(on: .zero, span: 10_000)
        #expect(camera.distance == 100)

        camera.fit(center: .zero, containing: [.zero], minimumSpan: 1e-8)
        #expect(camera.distance == 1e-5)
        camera.fit(center: .zero, containing: [SIMD3(100_000, 0, 0)], minimumSpan: 1)
        #expect(camera.distance == 100)
    }
}

@Suite struct SphereProjectionTests {
    @Test func projectedRadiusMatchesThePerspectiveSphereFormulaAndMinimum() {
        var camera = OrbitCamera()
        camera.distance = 12
        camera.fieldOfView = 0.8
        let center = SIMD3<Float>(1, 0, 0)
        let radius: Float = 2
        let distanceToEye = simd_distance(camera.position, center)
        let expected = tan(asin(radius / distanceToEye)) / tan(camera.fieldOfView / 2) * 600 / 2
        let actual = SphereProjection.pointRadius(radius: radius, center: center, camera: camera, viewportShortSide: 600, minimum: 0.1)
        #expect(abs(actual - expected) / expected < 1e-4)

        let floored = SphereProjection.pointRadius(radius: 0.001, center: SIMD3(0, 0, 0), camera: camera, viewportShortSide: 600, minimum: 2.5)
        #expect(floored == 2.5)
    }

    @Test func eyeInsideSphereUsesViewportRadiusAndRadiusGrowsAsCameraApproaches() {
        let camera = OrbitCamera()
        let inside = SphereProjection.pointRadius(radius: 1, center: camera.position, camera: camera, viewportShortSide: 480, minimum: 2)
        #expect(inside == 480)

        var farCamera = OrbitCamera()
        farCamera.distance = 20
        var nearCamera = farCamera
        nearCamera.distance = 5
        let farRadius = SphereProjection.pointRadius(radius: 1, center: .zero, camera: farCamera, viewportShortSide: 600, minimum: 0)
        let nearRadius = SphereProjection.pointRadius(radius: 1, center: .zero, camera: nearCamera, viewportShortSide: 600, minimum: 0)
        #expect(nearRadius > farRadius)
    }
}

@Suite struct PlanetarySnapshotTests {
    @Test func snapshotListsStarThenBodiesAndUsesPositionsRelativeToDoubleOrigin() throws {
        let system = try PlanetarySystem.solarSystem()
        let layout = PlanetarySystemLayout(system: system, scale: .trueScale)
        let day = 246.75
        let origin = try #require(layout.position(of: .body("Earth"), atDay: day))
        let snapshot = PlanetarySceneSnapshot(layout: layout, day: day, origin: origin)

        #expect(snapshot.entries.map(\.item) == [.centralStar] + system.bodies.map { .body($0.name) })
        let earth = try #require(snapshot.entries.first { $0.item == .body("Earth") })
        #expect(earth.position == .zero)
        for entry in snapshot.entries {
            let position = try #require(layout.position(of: entry.item, atDay: day))
            let expected = SIMD3<Float>(Float(position.x - origin.x), Float(position.y - origin.y), Float(position.z - origin.z))
            #expect(distance(entry.position, expected) < 1e-6)
            let expectedRadius = try #require(layout.drawnRadius(of: entry.item))
            #expect(entry.radius == Float(expectedRadius))
        }
    }
}

@Suite struct PlanetarySceneStateTests {
    @Test func initialStateFramesTheCompressedSolarSystemAtHome() throws {
        let state = PlanetarySceneState(system: try PlanetarySystem.solarSystem())
        let layout = state.layout
        let expectedDistance = Float(layout.homeSpan / 2 / tan(Double(state.camera.fieldOfView) / 2))
        #expect(state.scale == .compressed)
        #expect(state.origin == .zero)
        #expect(state.camera.target == .zero)
        #expect(state.camera.orientation == OrbitCamera.home)
        #expect(abs(state.camera.distance - expectedDistance) / expectedDistance < 1e-4)
        #expect(state.camera.distanceLimits.lowerBound == Float(2 * layout.smallestDrawnRadius))
        #expect(state.camera.distanceLimits.upperBound == Float(Double(PlanetarySceneState.maximumDistanceExtents) * layout.extent))
        #expect(state.followed == nil)
        #expect(state.clock.day == 0)
        #expect(abs(state.camera.nearPlane - state.camera.distance * 0.01) < 1e-6)
        #expect(abs(state.camera.farPlane - (state.camera.distance + 3 * Float(layout.extent))) < 1e-5)
    }

    @Test func assigningCameraRecomputesClipPlanesFromItsCurrentDistance() throws {
        var state = PlanetarySceneState(system: try PlanetarySystem.solarSystem())
        var camera = state.camera
        camera.zoom(by: 0.5)
        state.camera = camera
        #expect(abs(state.camera.nearPlane - state.camera.distance * PlanetarySceneState.nearPlaneFraction) < 1e-6)
        #expect(abs(state.camera.farPlane - (state.camera.distance + PlanetarySceneState.farPlaneExtents * Float(state.layout.extent))) < 1e-5)
    }

    @Test func deterministicStepsAdvanceTimeCapHitchesAndKeepSpeedChangesOnTheSameBaseline() throws {
        var state = PlanetarySceneState(system: try PlanetarySystem.solarSystem())
        state.clock.speed = .year
        state.step(to: 10)
        #expect(state.clock.day == 0)
        state.step(to: 10.05)
        #expect(abs(state.clock.day - 0.05 * SimulationSpeed.year.daysPerSecond) < 1e-10)
        let beforeHitch = state.clock.day
        state.step(to: 20.05)
        #expect(abs(state.clock.day - beforeHitch - SimulationClock.maximumStep * SimulationSpeed.year.daysPerSecond) < 1e-10)

        var speedState = PlanetarySceneState(system: try PlanetarySystem.solarSystem())
        speedState.step(to: 0)
        speedState.clock.speed = .year
        speedState.step(to: 0.05)
        #expect(abs(speedState.clock.day - 0.05 * SimulationSpeed.year.daysPerSecond) < 1e-10)
    }

    @Test func pauseAndResumeDoNotCountThePausedInterval() throws {
        var state = PlanetarySceneState(system: try PlanetarySystem.solarSystem())
        state.step(to: 4)
        state.step(to: 4.05)
        let beforePause = state.clock.day
        state.clock.isPaused = true
        state.step(to: 4.1)
        state.step(to: 100)
        #expect(state.clock.day == beforePause)
        state.clock.isPaused = false
        state.step(to: 100)
        #expect(state.clock.day == beforePause)
        state.step(to: 100.05)
        #expect(abs(state.clock.day - beforePause - 0.05 * state.clock.speed.daysPerSecond) < 1e-10)
    }

    @Test func followingUpdatesTheOriginAndKeepsCameraTargetAtTheOrigin() throws {
        var state = PlanetarySceneState(system: try PlanetarySystem.solarSystem())
        state.fly(to: .body("Earth"), at: 0)
        state.step(to: 0)
        state.step(to: PlanetarySceneState.flightDuration + 0.01)
        #expect(state.followed == .body("Earth"))
        for time in [0.86, 0.91, 1.1] {
            state.step(to: time)
            let expectedOrigin = try #require(state.layout.position(of: .body("Earth"), atDay: state.clock.day))
            #expect(state.origin == expectedOrigin)
            #expect(state.camera.target == .zero)
        }
    }

    @Test func flightInterpolatesAndThenFollowsTheMovingBody() throws {
        var state = PlanetarySceneState(system: try PlanetarySystem.solarSystem())
        let startDistance = state.camera.distance
        let jupiterSpan = try #require(state.layout.viewingSpan(of: .body("Jupiter")))
        let endDistance = Float(jupiterSpan / 2 / tan(Double(state.camera.fieldOfView) / 2))
        state.step(to: 10)
        state.fly(to: .body("Jupiter"), at: 10)
        #expect(state.isFlying)
        #expect(state.followed == nil)

        state.step(to: 10 + PlanetarySceneState.flightDuration / 2)
        #expect(min(startDistance, endDistance) < state.camera.distance)
        #expect(state.camera.distance < max(startDistance, endDistance))
        #expect(state.isFlying)

        state.step(to: 10 + PlanetarySceneState.flightDuration + 0.01)
        #expect(!state.isFlying)
        #expect(state.followed == .body("Jupiter"))
        let expectedOrigin = try #require(state.layout.position(of: .body("Jupiter"), atDay: state.clock.day))
        #expect(state.origin == expectedOrigin)
        #expect(state.camera.target == .zero)
        let span = try #require(state.layout.viewingSpan(of: .body("Jupiter")))
        let expectedDistance = Float(span / 2 / tan(Double(state.camera.fieldOfView) / 2))
        #expect(abs(state.camera.distance - expectedDistance) / expectedDistance < 1e-4)
        #expect(abs(state.camera.distanceLimits.lowerBound - 2 * Float(try #require(state.layout.drawnRadius(of: .body("Jupiter"))))) < 1e-6)
    }

    @Test func panStopsFollowingAndCancelFlightStopsTheFlight() throws {
        var state = PlanetarySceneState(system: try PlanetarySystem.solarSystem())
        state.fly(to: .body("Earth"), at: 0)
        state.step(to: 0)
        state.step(to: PlanetarySceneState.flightDuration + 0.01)
        let origin = state.origin
        let oldTarget = state.camera.target
        state.pan(byPoints: SIMD2(40, 20), viewportShortSide: 600)
        #expect(state.followed == nil)
        #expect(state.camera.target != oldTarget)
        state.step(to: 5)
        #expect(state.origin == origin)

        state.fly(to: .body("Jupiter"), at: 6)
        #expect(state.isFlying)
        state.step(to: 6.2)
        state.cancelFlight()
        #expect(!state.isFlying)
        #expect(state.followed == nil)
    }

    @Test func resetRestoresFreshViewStateButKeepsTheClock() throws {
        let system = try PlanetarySystem.solarSystem()
        var state = PlanetarySceneState(system: system)
        state.clock = SimulationClock(day: 123, speed: .year, isPaused: true)
        state.camera.rotate(by: SIMD2(0.3, 0.5))
        state.fly(to: .body("Jupiter"), at: 0)
        state.step(to: 1)
        state.resetView()
        let fresh = PlanetarySceneState(system: system)
        #expect(state.camera == fresh.camera)
        #expect(state.origin == fresh.origin)
        #expect(state.followed == fresh.followed)
        #expect(!state.isFlying)
        #expect(state.clock == SimulationClock(day: 123, speed: .year, isPaused: true))
    }

    @Test func scaleChangesKeepTheFollowedBodyFramedOrReturnHome() throws {
        var following = PlanetarySceneState(system: try PlanetarySystem.solarSystem())
        following.clock = SimulationClock(day: 123.4, speed: .week)
        following.fly(to: .body("Earth"), at: 0)
        following.step(to: 0)
        following.step(to: PlanetarySceneState.flightDuration + 0.01)
        let day = following.clock.day
        following.setScale(.trueScale)
        #expect(following.scale == .trueScale)
        #expect(following.followed == .body("Earth"))
        let earthOrigin = try #require(following.layout.position(of: .body("Earth"), atDay: day))
        #expect(following.origin == earthOrigin)
        let earthSpan = try #require(following.layout.viewingSpan(of: .body("Earth")))
        let earthDistance = Float(earthSpan / 2 / tan(Double(following.camera.fieldOfView) / 2))
        #expect(abs(following.camera.distance - earthDistance) / earthDistance < 1e-4)
        #expect(following.clock.day == day)

        var home = PlanetarySceneState(system: try PlanetarySystem.solarSystem())
        home.setScale(.trueScale)
        let homeDistance = Float(home.layout.homeSpan / 2 / tan(Double(home.camera.fieldOfView) / 2))
        #expect(abs(home.camera.distance - homeDistance) / homeDistance < 1e-4)

        var inFlight = PlanetarySceneState(system: try PlanetarySystem.solarSystem())
        inFlight.fly(to: .body("Jupiter"), at: 0)
        #expect(inFlight.isFlying)
        inFlight.setScale(.trueScale)
        #expect(!inFlight.isFlying)
        #expect(inFlight.followed == .body("Jupiter"))
        let jupiterOrigin = try #require(inFlight.layout.position(of: .body("Jupiter"), atDay: inFlight.clock.day))
        #expect(inFlight.origin == jupiterOrigin)
    }
}

@Suite struct PlanetaryPickerTests {
    @Test func overlappingContainmentPicksTheNearestDepthRegardlessOfDiscSizeOrOrder() {
        let largeFar = PlanetaryPicker.Disc(center: .zero, radius: 30, depth: 10)
        let smallNear = PlanetaryPicker.Disc(center: .zero, radius: 4, depth: 2)
        #expect(PlanetaryPicker.pick(.zero, in: [largeFar, smallNear], tolerance: 20) == 1)
        #expect(PlanetaryPicker.pick(.zero, in: [smallNear, largeFar], tolerance: 20) == 0)

        let largeNear = PlanetaryPicker.Disc(center: .zero, radius: 30, depth: 2)
        let smallFar = PlanetaryPicker.Disc(center: .zero, radius: 4, depth: 10)
        #expect(PlanetaryPicker.pick(.zero, in: [largeNear, smallFar], tolerance: 20) == 0)
    }

    @Test func aContainingDiscWinsBeforeToleranceCanReachANearerDisc() {
        let farPlanet = PlanetaryPicker.Disc(center: .zero, radius: 20, depth: 10)
        let nearMoon = PlanetaryPicker.Disc(center: SIMD2(5, 0), radius: 2, depth: 2)
        #expect(PlanetaryPicker.pick(.zero, in: [farPlanet, nearMoon], tolerance: 5) == 0)
    }

    @Test func tolerancePicksNearestEdgeThenBreaksTiesByDepthAndIndex() {
        let first = PlanetaryPicker.Disc(center: SIMD2(0, 0), radius: 5, depth: 8)
        let second = PlanetaryPicker.Disc(center: SIMD2(20, 0), radius: 5, depth: 3)
        #expect(PlanetaryPicker.pick(SIMD2(7, 0), in: [first, second], tolerance: 2) == 0)

        let left = PlanetaryPicker.Disc(center: SIMD2(-10, 0), radius: 3, depth: 8)
        let right = PlanetaryPicker.Disc(center: SIMD2(10, 0), radius: 3, depth: 3)
        #expect(PlanetaryPicker.pick(.zero, in: [left, right], tolerance: 7) == 1)
        let equalDepthRight = PlanetaryPicker.Disc(center: SIMD2(10, 0), radius: 3, depth: 8)
        #expect(PlanetaryPicker.pick(.zero, in: [left, equalDepthRight], tolerance: 7) == 0)
        #expect(PlanetaryPicker.pick(SIMD2(7.1, 0), in: [first, second], tolerance: 2) == nil)
        #expect(PlanetaryPicker.pick(.zero, in: [], tolerance: 20) == nil)
    }
}

@Suite struct PlanetaryItemPickingTests {
    private let viewport = SIMD2<Float>(800, 600)

    @Test func homeViewSelectsEachVisibleUncoveredBodyAndTheStar() throws {
        let state = PlanetarySceneState(system: try PlanetarySystem.solarSystem())
        let snapshot = state.snapshot()
        let projected = projectedDiscs(snapshot: snapshot, camera: state.camera, viewport: viewport, minimum: state.minimumPointRadius)
        var checked = 0
        for entry in snapshot.entries.dropFirst() {
            guard let disc = projected.first(where: { $0.index == index(of: entry.item, in: snapshot) }),
                  isOnScreen(disc.center, viewport: viewport) else { continue }
            let coveredByNearer = projected.contains {
                $0.index != disc.index && isOnScreen($0.center, viewport: viewport)
                    && $0.depth < disc.depth && simd_distance($0.center, disc.center) <= $0.radius
            }
            guard !coveredByNearer else { continue }
            #expect(state.item(at: disc.center, viewportSize: viewport, tolerance: 0) == entry.item)
            checked += 1
        }
        #expect(checked > 0)

        let star = try #require(projected.first { $0.index == 0 })
        #expect(state.item(at: star.center + SIMD2(3, 0), viewportSize: viewport) == .centralStar)
        #expect(state.item(at: SIMD2(-1_000, -1_000), viewportSize: viewport) == nil)
    }

    @Test func closeJupiterViewPicksVisibleGalileanMoonsAndRespectsTransitDepth() throws {
        var state = PlanetarySceneState(system: try PlanetarySystem.solarSystem())
        state.fly(to: .body("Jupiter"), at: 0)
        state.step(to: PlanetarySceneState.flightDuration + 0.01)
        #expect(state.followed == .body("Jupiter"))
        state.clock.isPaused = true

        let moonNames = ["Io", "Europa", "Ganymede", "Callisto"]
        var checkedVisible: Set<String> = []
        var foundFrontTransit = false
        var foundBehindTransit = false
        for sample in 0..<480 {
            state.clock.day = Double(sample) * 0.25
            state.step(to: 2 + Double(sample) * 0.01)
            let snapshot = state.snapshot()
            let discs = projectedDiscs(snapshot: snapshot, camera: state.camera, viewport: viewport, minimum: state.minimumPointRadius)
            guard let jupiter = discs.first(where: { snapshot.entries[$0.index].item == .body("Jupiter") }) else { continue }
            for name in moonNames {
                guard let moon = discs.first(where: { snapshot.entries[$0.index].item == .body(name) }),
                      isOnScreen(moon.center, viewport: viewport) else { continue }
                let coveredByOtherNearerItem = discs.contains {
                    $0.index != moon.index && $0.index != jupiter.index
                        && isOnScreen($0.center, viewport: viewport) && $0.depth < moon.depth
                        && simd_distance($0.center, moon.center) <= $0.radius
                }
                guard !coveredByOtherNearerItem else { continue }
                let insideJupiter = simd_distance(moon.center, jupiter.center) <= jupiter.radius
                if !insideJupiter {
                    #expect(state.item(at: moon.center, viewportSize: viewport, tolerance: 0) == .body(name))
                    checkedVisible.insert(name)
                } else if moon.depth < jupiter.depth {
                    #expect(state.item(at: moon.center, viewportSize: viewport, tolerance: 0) == .body(name))
                    foundFrontTransit = true
                    checkedVisible.insert(name)
                } else {
                    #expect(state.item(at: moon.center, viewportSize: viewport, tolerance: 0) == .body("Jupiter"))
                    foundBehindTransit = true
                }
            }
        }
        #expect(checkedVisible == Set(moonNames))
        #expect(foundFrontTransit)
        #expect(foundBehindTransit)
    }

    @Test func minimumPointRadiusBodyCanBePickedAtItsDrawnEdge() throws {
        let tiny = Body(name: "Tiny", kind: .asteroid, parent: .centralStar, orbit: Orbit(distance: 1), radius: 1)
        let system = try PlanetarySystem(name: "Tiny system", centralStar: .sun, bodies: [tiny])
        let state = PlanetarySceneState(system: system)
        let snapshot = state.snapshot()
        let tinyIndex = try #require(snapshot.entries.firstIndex { $0.item == .body("Tiny") })
        let tinyEntry = snapshot.entries[tinyIndex]
        let projected = try #require(state.camera.project(tinyEntry.position, viewportSize: viewport))
        let radius = SphereProjection.pointRadius(radius: tinyEntry.radius, center: tinyEntry.position, camera: state.camera, viewportShortSide: viewport.y, minimum: state.minimumPointRadius)
        #expect(radius == state.minimumPointRadius)
        #expect(state.item(at: projected + SIMD2(radius + 3, 0), viewportSize: viewport, tolerance: 3.1) == .body("Tiny"))
    }
}

@Suite struct PlanetaryLabelsTests {
    private let viewport = SIMD2<Float>(800, 600)

    @Test func candidatesExistForEachOnScreenEntryAndSelectedItemIsPinned() throws {
        let system = try PlanetarySystem.solarSystem()
        let state = PlanetarySceneState(system: system)
        let snapshot = state.snapshot()
        let sizes = Array(repeating: SIMD2<Float>(40, 12), count: snapshot.entries.count)
        let candidates = PlanetaryLabels.candidates(
            for: snapshot, in: system, camera: state.camera, viewportSize: viewport,
            labelSizes: sizes, minimumPointRadius: state.minimumPointRadius, selection: .body("Earth")
        )
        let expectedIDs = snapshot.entries.enumerated().compactMap { index, entry -> Int? in
            guard let point = state.camera.project(entry.position, viewportSize: viewport), isOnScreen(point, viewport: viewport) else { return nil }
            return index
        }
        #expect(candidates.map(\.id).sorted() == expectedIDs.sorted())
        let selected = try #require(candidates.first { $0.id == index(of: .body("Earth"), in: snapshot) })
        #expect(selected.isPinned)
    }

    @Test func labelPrioritiesPlaceStarsBeforePlanetsDwarfsAndMoons() throws {
        let system = try PlanetarySystem.solarSystem()
        let state = PlanetarySceneState(system: system)
        let snapshot = state.snapshot()
        let candidates = PlanetaryLabels.candidates(
            for: snapshot, in: system, camera: state.camera, viewportSize: viewport,
            labelSizes: Array(repeating: SIMD2<Float>(30, 10), count: snapshot.entries.count),
            minimumPointRadius: state.minimumPointRadius, selection: nil
        )
        func priorities(where predicate: (PlanetarySceneSnapshot.Entry) -> Bool) -> [Float] {
            candidates.compactMap { candidate in
                predicate(snapshot.entries[candidate.id]) ? candidate.priority : nil
            }
        }
        let star = try #require(priorities { $0.item == .centralStar }.first)
        let planets = priorities { entry in
            guard case .body(let name) = entry.item, let body = system.body(named: name) else { return false }
            return body.kind == .planet
        }
        let dwarfs = priorities { entry in
            guard case .body(let name) = entry.item, let body = system.body(named: name) else { return false }
            return body.kind == .dwarfPlanet
        }
        let moons = priorities { entry in
            guard case .body(let name) = entry.item, let body = system.body(named: name) else { return false }
            return body.parent != .centralStar
        }
        #expect(!planets.isEmpty && !dwarfs.isEmpty && !moons.isEmpty)
        #expect(star < (planets.min() ?? .infinity))
        #expect((planets.max() ?? -.infinity) < (dwarfs.min() ?? .infinity))
        #expect((dwarfs.max() ?? -.infinity) < (moons.min() ?? .infinity))
    }

    @Test func crowdedMoonLabelIsSuppressedUnlessSelected() throws {
        let system = try PlanetarySystem.solarSystem()
        let state = PlanetarySceneState(system: system)
        let snapshot = state.snapshot()
        let sizes = Array(repeating: SIMD2<Float>(35, 10), count: snapshot.entries.count)
        let all = PlanetaryLabels.candidates(
            for: snapshot, in: system, camera: state.camera, viewportSize: viewport,
            labelSizes: sizes, minimumPointRadius: state.minimumPointRadius, selection: nil
        )
        var crowdedMoon: PlanetarySystemItem?
        for entry in snapshot.entries {
            guard case .body(let name) = entry.item, let moon = system.body(named: name), moon.parent != .centralStar,
                  let anchor = state.camera.project(entry.position, viewportSize: viewport), isOnScreen(anchor, viewport: viewport),
                  case .body(let parentName) = moon.parent,
                  let parentEntry = snapshot.entries.first(where: { $0.item == .body(parentName) }),
                  let parentAnchor = state.camera.project(parentEntry.position, viewportSize: viewport) else { continue }
            let parentRadius = SphereProjection.pointRadius(
                radius: parentEntry.radius, center: parentEntry.position, camera: state.camera,
                viewportShortSide: viewport.y, minimum: state.minimumPointRadius
            )
            if simd_distance(anchor, parentAnchor) - parentRadius <= PlanetaryLabels.minimumMoonSeparation {
                crowdedMoon = .body(name)
                break
            }
        }
        let selectedMoon = try #require(crowdedMoon)
        let selectedIndex = index(of: selectedMoon, in: snapshot)
        #expect(!all.contains { $0.id == selectedIndex })

        let selectedCandidates = PlanetaryLabels.candidates(
            for: snapshot, in: system, camera: state.camera, viewportSize: viewport,
            labelSizes: sizes, minimumPointRadius: state.minimumPointRadius, selection: selectedMoon
        )
        let selected = try #require(selectedCandidates.first { $0.id == selectedIndex })
        #expect(selected.isPinned)
    }

    @Test func flyingToJupiterMakesItsGalileanMoonLabelsAvailable() throws {
        let system = try PlanetarySystem.solarSystem()
        var state = PlanetarySceneState(system: system)
        state.fly(to: .body("Jupiter"), at: 0)
        state.step(to: PlanetarySceneState.flightDuration + 0.01)
        let snapshot = state.snapshot()
        let candidates = PlanetaryLabels.candidates(
            for: snapshot, in: system, camera: state.camera, viewportSize: viewport,
            labelSizes: Array(repeating: SIMD2<Float>(40, 12), count: snapshot.entries.count),
            minimumPointRadius: state.minimumPointRadius, selection: nil
        )
        for name in ["Io", "Europa", "Ganymede", "Callisto"] {
            #expect(candidates.contains { $0.id == index(of: .body(name), in: snapshot) })
        }
    }
}

private struct ProjectedDisc {
    let index: Int
    let center: SIMD2<Float>
    let radius: Float
    let depth: Float
}

private func projectedDiscs(
    snapshot: PlanetarySceneSnapshot, camera: OrbitCamera, viewport: SIMD2<Float>, minimum: Float
) -> [ProjectedDisc] {
    snapshot.entries.enumerated().compactMap { index, entry in
        guard let center = camera.project(entry.position, viewportSize: viewport) else { return nil }
        return ProjectedDisc(
            index: index, center: center,
            radius: SphereProjection.pointRadius(radius: entry.radius, center: entry.position, camera: camera, viewportShortSide: viewport.y, minimum: minimum),
            depth: simd_distance(camera.position, entry.position)
        )
    }
}

private func isOnScreen(_ point: SIMD2<Float>, viewport: SIMD2<Float>) -> Bool {
    point.x >= 0 && point.x <= viewport.x && point.y >= 0 && point.y <= viewport.y
}

private func index(of item: PlanetarySystemItem, in snapshot: PlanetarySceneSnapshot) -> Int {
    snapshot.entries.firstIndex { $0.item == item } ?? -1
}

private func distance(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float {
    simd_distance(lhs, rhs)
}
