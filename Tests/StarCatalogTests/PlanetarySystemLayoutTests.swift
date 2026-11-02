import Foundation
import Testing
@testable import StarCatalog

@Suite struct PlanetarySystemLayoutTests {
    @Test func publicUnitConstantsUseTheSpecifiedConversions() {
        #expect(Astrophysics.kilometersPerAU == 149_597_870.7)
        #expect(Astrophysics.kilometersPerSolarRadius == 695_700)
        #expect(Astrophysics.earthRadiusKilometers == 6_371)
    }

    @Test(arguments: Body.Kind.allCases)
    func everyBodyKindHasADisplayNameAndDistinctValidDefaultColor(kind: Body.Kind) {
        let names: [Body.Kind: String] = [
            .planet: "Planet", .dwarfPlanet: "Dwarf planet", .moon: "Moon",
            .asteroid: "Asteroid", .comet: "Comet",
        ]
        #expect(kind.displayName == names[kind])
        let color = kind.defaultColor
        #expect((0...1).contains(color.x) && (0...1).contains(color.y) && (0...1).contains(color.z))
        for other in Body.Kind.allCases where other != kind {
            #expect(kind.defaultColor != other.defaultColor)
        }
    }

    @Test func bodyDisplayColorUsesItsColorOrItsKindsDefault() {
        let colored = body("Colored", color: SIMD3(0.1, 0.2, 0.3))
        let plain = body("Plain", kind: .comet)
        #expect(colored.displayColor == SIMD3(0.1, 0.2, 0.3))
        #expect(plain.displayColor == Body.Kind.comet.defaultColor)
    }

    @Test func trueScalePositionsAreNestedTrueOrbitalOffsets() throws {
        let system = try PlanetarySystem.solarSystem()
        let layout = PlanetarySystemLayout(system: system, scale: .trueScale)
        for day in [0.0, 123.4, 10_000.0] {
            #expect(layout.position(of: .centralStar, atDay: day) == .zero)
            for body in system.bodies {
                let period = system.orbitalPeriod(of: body)
                let offset = body.orbit.offset(atDay: day, period: period)
                let parentPosition = position(of: body.parent, in: layout, atDay: day)
                let actual = try #require(layout.position(of: .body(body.name), atDay: day))
                #expect(distance(actual, parentPosition + offset) < 1e-12)
            }
            let positions = layout.bodyPositions(atDay: day)
            #expect(positions.count == system.bodies.count)
            for (index, body) in system.bodies.enumerated() {
                #expect(distance(positions[index], try #require(layout.position(of: .body(body.name), atDay: day))) < 1e-12)
            }
        }
    }

    @Test func trueScaleUsesPhysicalRadiiDistancesAndBeltEdges() throws {
        let system = try PlanetarySystem.solarSystem()
        let layout = PlanetarySystemLayout(system: system, scale: .trueScale)
        for body in system.bodies {
            let radius = try #require(layout.drawnRadius(of: .body(body.name)))
            #expect(abs(radius - body.radius / Astrophysics.kilometersPerAU) < 1e-15)
        }
        let starRadius = try #require(layout.drawnRadius(of: .centralStar))
        #expect(starRadius == system.centralStar.radius * Astrophysics.kilometersPerSolarRadius / Astrophysics.kilometersPerAU)
        for belt in system.belts {
            #expect(layout.beltRadii(of: belt) == belt.innerEdge...belt.outerEdge)
        }
        for parent in [Parent.centralStar, .body("Jupiter")] {
            for distance in [0.001, 1.0, 30.0] {
                #expect(layout.sceneDistance(ofTrueDistance: distance, around: parent) == distance)
            }
        }
    }

    @Test func compressedStarLevelMapsItsFarthestApoapsisToSystemRadius() throws {
        let system = try PlanetarySystem.solarSystem()
        let layout = PlanetarySystemLayout(system: system, scale: .compressed)
        let reach = max(
            system.bodies.filter { $0.parent == .centralStar }.map { $0.orbit.distance * (1 + $0.orbit.eccentricity) }.max() ?? 0,
            system.belts.filter { $0.parent == .centralStar }.map(\.outerEdge).max() ?? 0
        )
        let eris = try #require(system.body(named: "Eris"))
        let erisRadius = try #require(layout.orbitRadius(of: eris))
        let erisApoapsis = layout.sceneDistance(ofTrueDistance: eris.orbit.distance * (1 + eris.orbit.eccentricity), around: .centralStar)
        #expect(abs(erisApoapsis - PlanetarySystemLayout.systemRadius) < 1e-9)
        #expect(abs(erisRadius - PlanetarySystemLayout.systemRadius * pow(eris.orbit.distance / reach, PlanetarySystemLayout.distanceExponent)) < 1e-9)
    }

    @Test func compressedOrbitAndBeltRadiiPreserveTheirOrderingAndContainment() throws {
        let system = try PlanetarySystem.solarSystem()
        let layout = PlanetarySystemLayout(system: system, scale: .compressed)
        let siblings = system.children(of: .centralStar).sorted { $0.orbit.distance < $1.orbit.distance }
        for pair in zip(siblings, siblings.dropFirst()) {
            let innerOrbit = try #require(layout.orbitRadius(of: pair.0))
            let outerOrbit = try #require(layout.orbitRadius(of: pair.1))
            #expect(innerOrbit < outerOrbit)
        }
        for belt in system.belts {
            let radii = layout.beltRadii(of: belt)
            #expect(radii.lowerBound < radii.upperBound)
            for body in system.bodies where system.belt(containing: body) == belt {
                let orbitRadius = try #require(layout.orbitRadius(of: body))
                #expect(radii.contains(orbitRadius))
            }
        }
        let ceres = try #require(system.body(named: "Ceres"))
        let asteroidBelt = try #require(system.belts.first { $0.name == "Asteroid belt" })
        #expect(layout.beltRadii(of: asteroidBelt).contains(try #require(layout.orbitRadius(of: ceres))))
    }

    @Test func compressedPositionsPreserveTrueDirectionsAndMapEachRadialDistance() throws {
        let system = try PlanetarySystem.solarSystem()
        let layout = PlanetarySystemLayout(system: system, scale: .compressed)
        for day in [0.0, 17.2, 123.4, 10_000.0] {
            for body in system.bodies {
                let trueOffset = body.orbit.offset(atDay: day, period: system.orbitalPeriod(of: body))
                let parentPosition = position(of: body.parent, in: layout, atDay: day)
                let bodyPosition = try #require(layout.position(of: .body(body.name), atDay: day))
                let compressedOffset = bodyPosition - parentPosition
                #expect(distance(unit(compressedOffset), unit(trueOffset)) < 1e-9)
                let expectedLength = layout.sceneDistance(ofTrueDistance: length(trueOffset), around: body.parent)
                #expect(abs(length(compressedOffset) - expectedLength) < 1e-9)
            }
        }
    }

    @Test func compressedMoonsStayOutsideTheirParentAndTheirEnlargedSurface() throws {
        let system = try PlanetarySystem.solarSystem()
        let layout = PlanetarySystemLayout(system: system, scale: .compressed)
        let moons = system.bodies.filter { $0.parent != .centralStar }
        let longestPeriod = try #require(moons.compactMap { system.orbitalPeriod(of: $0) }.max())
        for index in 0..<200 {
            let day = longestPeriod * 3 * Double(index) / 199
            for moon in moons {
                let parentName: String
                if case .body(let name) = moon.parent { parentName = name } else { continue }
                let parentRadius = try #require(layout.drawnRadius(of: .body(parentName)))
                let moonRadius = try #require(layout.drawnRadius(of: .body(moon.name)))
                let parentPosition = try #require(layout.position(of: .body(parentName), atDay: day))
                let moonPosition = try #require(layout.position(of: .body(moon.name), atDay: day))
                let separation = distance(moonPosition, parentPosition)
                #expect(separation - parentRadius - moonRadius > 0)
                #expect(separation >= PlanetarySystemLayout.moonInnerFactor * parentRadius - 1e-12)
            }
        }
    }

    @Test func eachLevelCompressesIndependentlyOfOtherLevels() throws {
        let original = try PlanetarySystem.solarSystem()
        let scaledMoons = original.bodies.map { body -> Body in
            guard body.parent == .body("Jupiter") else { return body }
            return Body(
                name: body.name, kind: body.kind, parent: body.parent,
                orbit: Orbit(distance: body.orbit.distance * 2, period: original.orbitalPeriod(of: body),
                             eccentricity: body.orbit.eccentricity, inclination: body.orbit.inclination,
                             startingAngle: body.orbit.startingAngle),
                radius: body.radius, mass: body.mass, color: body.color
            )
        }
        let rebuilt = try PlanetarySystem(name: original.name, centralStar: original.centralStar, bodies: scaledMoons, belts: original.belts)
        let first = PlanetarySystemLayout(system: original, scale: .compressed)
        let second = PlanetarySystemLayout(system: rebuilt, scale: .compressed)
        for day in [0.0, 123.4, 4_000.0] {
            for body in original.bodies {
                let p1 = try #require(first.position(of: .body(body.name), atDay: day))
                let p2 = try #require(second.position(of: .body(body.name), atDay: day))
                if body.parent == .body("Jupiter") {
                    let j1 = try #require(first.position(of: .body("Jupiter"), atDay: day))
                    let j2 = try #require(second.position(of: .body("Jupiter"), atDay: day))
                    #expect(distance(p1 - j1, p2 - j2) < 1e-9)
                } else {
                    #expect(distance(p1, p2) < 1e-9)
                }
            }
        }

        let oneMoonChanged = try PlanetarySystem(
            name: original.name, centralStar: original.centralStar,
            bodies: original.bodies.map { body in
                guard body.name == "Callisto" else { return body }
                return Body(name: body.name, kind: body.kind, parent: body.parent,
                            orbit: Orbit(distance: body.orbit.distance * 1.8, period: body.orbit.period),
                            radius: body.radius, mass: body.mass, color: body.color)
            },
            belts: original.belts
        )
        let third = PlanetarySystemLayout(system: oneMoonChanged, scale: .compressed)
        for body in original.children(of: .centralStar) {
            #expect(first.position(of: .body(body.name), atDay: 123.4) == third.position(of: .body(body.name), atDay: 123.4))
            #expect(first.drawnRadius(of: .body(body.name)) == third.drawnRadius(of: .body(body.name)))
        }
    }

    @Test func compressedRoomAndSizeLimitsHoldAtEveryBodyLevel() throws {
        let system = try PlanetarySystem.solarSystem()
        let layout = PlanetarySystemLayout(system: system, scale: .compressed)
        for body in system.bodies {
            let orbitRadius = try #require(layout.orbitRadius(of: body))
            let surface: Double
            if case .body(let parentName) = body.parent {
                surface = try #require(layout.drawnRadius(of: .body(parentName)))
            } else {
                surface = 0
            }
            let siblings = system.children(of: body.parent).compactMap { layout.orbitRadius(of: $0) }
            let gap = (siblings.filter { $0 != orbitRadius }.map { abs(orbitRadius - $0) } + [orbitRadius - surface]).min() ?? (orbitRadius - surface)
            let room = PlanetarySystemLayout.roomFraction * gap
            let radius = try #require(layout.drawnRadius(of: .body(body.name)))
            #expect(layout.moonReach(of: body) <= room + 1e-12)
            #expect(radius <= PlanetarySystemLayout.sizeFraction * room + 1e-12)
            if case .body(let parentName) = body.parent {
                let parentRadius = try #require(layout.drawnRadius(of: .body(parentName)))
                #expect(radius <= PlanetarySystemLayout.maximumMoonToParentRatio * parentRadius + 1e-12)
            }
        }
    }

    @Test func compressedDrawnSizesPreserveRealSizeOrderWithinLevels() throws {
        let system = try PlanetarySystem.solarSystem()
        let layout = PlanetarySystemLayout(system: system, scale: .compressed)
        let expected: [(String, String)] = [
            ("Jupiter", "Saturn"), ("Saturn", "Uranus"), ("Uranus", "Neptune"),
            ("Neptune", "Earth"), ("Earth", "Venus"), ("Venus", "Mars"), ("Mars", "Mercury"),
            ("Ganymede", "Callisto"), ("Callisto", "Io"), ("Io", "Europa"),
        ]
        for (larger, smaller) in expected {
            let largerRadius = try #require(layout.drawnRadius(of: .body(larger)))
            let smallerRadius = try #require(layout.drawnRadius(of: .body(smaller)))
            #expect(largerRadius > smallerRadius)
        }
    }

    @Test func starClearsInnermostPeriapsisAndEveryRadiusIsFiniteAndPositive() throws {
        let system = try PlanetarySystem.solarSystem()
        let layout = PlanetarySystemLayout(system: system, scale: .compressed)
        let innermostPeriapsis = try #require(system.children(of: .centralStar).compactMap { body -> Double? in
            layout.sceneDistance(
                ofTrueDistance: body.orbit.distance * (1 - body.orbit.eccentricity),
                around: .centralStar
            )
        }.min())
        let starRadius = try #require(layout.drawnRadius(of: .centralStar))
        #expect(starRadius <= PlanetarySystemLayout.starClearanceFraction * innermostPeriapsis + 1e-12)
        for item in [PlanetarySystemItem.centralStar] + system.bodies.map({ .body($0.name) }) {
            let radius = try #require(layout.drawnRadius(of: item))
            #expect(radius.isFinite && radius > 0)
        }
    }

    @Test func smallAndDegenerateLayoutsKeepFinitePositiveRadiiAndExtent() throws {
        let lonely = try PlanetarySystem(name: "Lonely", centralStar: .sun, bodies: [])
        let lonelyLayout = PlanetarySystemLayout(system: lonely, scale: .compressed)
        let lonelyStarRadius = try #require(lonelyLayout.drawnRadius(of: .centralStar))
        #expect(lonelyStarRadius == PlanetarySystemLayout.lonelyStarFraction * PlanetarySystemLayout.systemRadius)
        #expect(lonelyLayout.extent.isFinite && lonelyLayout.extent > 0)

        let beltOnly = try PlanetarySystem(
            name: "Belt only", centralStar: .sun, bodies: [],
            belts: [Belt(name: "Dust", parent: .centralStar, innerEdge: 2, outerEdge: 4)]
        )
        let single = body("Single", orbit: Orbit(distance: 1))
        let onePlanet = try PlanetarySystem(name: "One", centralStar: .sun, bodies: [single])
        let sameA = try PlanetarySystem(name: "Same orbit", centralStar: .sun, bodies: [
            body("First", orbit: Orbit(distance: 2)), body("Second", orbit: Orbit(distance: 2)),
        ])
        let host = body("Host", orbit: Orbit(distance: 1), radius: 6_371)
        let moon = body("Child", kind: .moon, parent: .body("Host"), orbit: Orbit(distance: 0.01, period: 10), radius: 1_000)
        let oneMoon = try PlanetarySystem(name: "One moon", centralStar: .sun, bodies: [host, moon])
        let layouts = [
            PlanetarySystemLayout(system: beltOnly, scale: .compressed),
            PlanetarySystemLayout(system: onePlanet, scale: .compressed),
            PlanetarySystemLayout(system: sameA, scale: .compressed),
            PlanetarySystemLayout(system: oneMoon, scale: .compressed),
        ]
        for layout in layouts {
            #expect(layout.extent.isFinite && layout.extent > 0)
            for item in [PlanetarySystemItem.centralStar] + layout.system.bodies.map({ .body($0.name) }) {
                let radius = try #require(layout.drawnRadius(of: item))
                #expect(radius.isFinite && radius > 0)
                let position = try #require(layout.position(of: item, atDay: 0))
                #expect(position.x.isFinite && position.y.isFinite && position.z.isFinite)
            }
        }
        let belt = try #require(beltOnly.belts.first)
        let beltRadii = PlanetarySystemLayout(system: beltOnly, scale: .compressed).beltRadii(of: belt)
        #expect(beltRadii.lowerBound.isFinite && beltRadii.upperBound.isFinite && beltRadii.lowerBound < beltRadii.upperBound)

        let moonLayout = PlanetarySystemLayout(system: oneMoon, scale: .compressed)
        let hostRadius = try #require(moonLayout.drawnRadius(of: .body("Host")))
        let hostBody = try #require(oneMoon.body(named: "Host"))
        let moonBody = try #require(oneMoon.body(named: "Child"))
        let hostOrbit = try #require(moonLayout.orbitRadius(of: hostBody))
        let moonOrbit = try #require(moonLayout.orbitRadius(of: moonBody))
        let room = PlanetarySystemLayout.roomFraction * hostOrbit
        #expect(abs(moonOrbit - room) < 1e-12)
        #expect(hostRadius > 0)
    }

    @Test func extentContainsSampledItemsAndBeltEdgesInBothScales() throws {
        let system = try PlanetarySystem.solarSystem()
        for scale in PlanetarySystemScale.allCases {
            let layout = PlanetarySystemLayout(system: system, scale: scale)
            for dayIndex in 0..<50 {
                let day = Double(dayIndex) * 1_200 / 49
                for item in [PlanetarySystemItem.centralStar] + system.bodies.map({ .body($0.name) }) {
                    let position = try #require(layout.position(of: item, atDay: day))
                    let radius = try #require(layout.drawnRadius(of: item))
                    #expect(length(position) + radius <= layout.extent + 1e-9)
                }
            }
            for belt in system.belts {
                let parentDistance: Double
                if case .body(let parentName) = belt.parent {
                    parentDistance = length(try #require(layout.position(of: .body(parentName), atDay: 0)))
                } else {
                    parentDistance = 0
                }
                #expect(parentDistance + layout.beltRadii(of: belt).upperBound <= layout.extent + 1e-9)
            }
            if scale == .compressed {
                #expect(layout.extent >= PlanetarySystemLayout.systemRadius)
            }
        }
    }

    @Test func viewingSpansMatchBodyStarAndUnknownItemRules() throws {
        let system = try PlanetarySystem.solarSystem()
        let layout = PlanetarySystemLayout(system: system, scale: .compressed)
        let jupiter = try #require(system.body(named: "Jupiter"))
        let jupiterRadius = try #require(layout.drawnRadius(of: .body("Jupiter")))
        let jupiterSpan = try #require(layout.viewingSpan(of: .body("Jupiter")))
        #expect(abs(jupiterSpan - max(2 * PlanetarySystemLayout.viewingSpanMargin * layout.moonReach(of: jupiter), PlanetarySystemLayout.bodySpanFactor * jupiterRadius)) < 1e-12)
        let mercuryRadius = try #require(layout.drawnRadius(of: .body("Mercury")))
        #expect(layout.viewingSpan(of: .body("Mercury")) == PlanetarySystemLayout.bodySpanFactor * mercuryRadius)
        #expect(try #require(layout.viewingSpan(of: .centralStar)) == layout.homeSpan)
        #expect(abs(layout.homeSpan - PlanetarySystemLayout.homeSpanFactor * layout.extent) < 1e-12)
        #expect(layout.viewingSpan(of: .body("Unknown")) == nil)
        #expect(layout.position(of: .body("Unknown"), atDay: 0) == nil)
        #expect(layout.drawnRadius(of: .body("Unknown")) == nil)
    }

    @Test func compressedOrbitPathsMatchTruePathDirectionsAndMappedLengths() throws {
        let system = try PlanetarySystem.solarSystem()
        let layout = PlanetarySystemLayout(system: system, scale: .compressed)
        let body = try #require(system.body(named: "Earth"))
        let truePath = body.orbit.pathOffsets(segments: 32)
        let scenePath = layout.orbitPath(of: body, segments: 32)
        #expect(scenePath.count == truePath.count)
        for (scenePoint, truePoint) in zip(scenePath, truePath) {
            #expect(distance(unit(scenePoint), unit(truePoint)) < 1e-12)
            #expect(abs(length(scenePoint) - layout.sceneDistance(ofTrueDistance: length(truePoint), around: body.parent)) < 1e-12)
        }
    }
}

private func position(of parent: Parent, in layout: PlanetarySystemLayout, atDay day: Double) -> SIMD3<Double> {
    switch parent {
    case .centralStar: .zero
    case .body(let name): layout.position(of: .body(name), atDay: day) ?? .zero
    }
}

private func body(
    _ name: String, kind: Body.Kind = .planet, parent: Parent = .centralStar,
    orbit: Orbit = Orbit(distance: 1), radius: Double = 1,
    mass: Double? = nil, color: SIMD3<Float>? = nil
) -> Body {
    Body(name: name, kind: kind, parent: parent, orbit: orbit, radius: radius, mass: mass, color: color)
}

private func length(_ point: SIMD3<Double>) -> Double {
    sqrt(point.x * point.x + point.y * point.y + point.z * point.z)
}

private func distance(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
    length(lhs - rhs)
}

private func unit(_ point: SIMD3<Double>) -> SIMD3<Double> {
    point / length(point)
}
