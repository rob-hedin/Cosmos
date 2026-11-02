import Foundation
import Testing
@testable import StarCatalog

@Suite struct OrbitalMotionTests {
    @Test(arguments: [
        (0.0, 0.0), (0.0, 1.7), (0.5, 0.2), (0.5, .pi),
        (0.8, 2.4), (0.95, 5.8), (0.999, 0.01),
    ])
    func eccentricAnomalySolvesKeplersEquation(eccentricity: Double, meanAnomaly: Double) {
        let anomaly = Orbit.eccentricAnomaly(meanAnomaly: meanAnomaly, eccentricity: eccentricity)
        #expect(anomaly.isFinite)
        #expect(abs(anomaly - eccentricity * sin(anomaly) - meanAnomaly) < 1e-12)
    }

    @Test func circularOrbitStartsOnPositiveXAxisAndMovesCounterclockwise() {
        let orbit = Orbit(distance: 2, period: 8)
        #expect(distance(orbit.offset(atDay: 0, period: 8), SIMD3(2, 0, 0)) < 1e-12)
        #expect(distance(orbit.offset(atDay: 2, period: 8), SIMD3(0, 2, 0)) < 1e-12)
        #expect(distance(orbit.offset(atDay: 96, period: 8), orbit.offset(atDay: 0, period: 8)) < 1e-12)
    }

    @Test func eccentricOrbitStartsAtPeriapsisAndMovesFasterThere() {
        let orbit = Orbit(distance: 1, period: 100, eccentricity: 0.5)
        #expect(distance(orbit.offset(atDay: 0, period: 100), SIMD3(0.5, 0, 0)) < 1e-12)
        #expect(distance(orbit.offset(atDay: 50, period: 100), SIMD3(-1.5, 0, 0)) < 1e-12)

        var radii: [Double] = []
        for index in 0..<100 {
            let point = orbit.offset(atDay: Double(index), period: 100)
            let radius = length(point)
            radii.append(radius)
            #expect(radius >= 0.5 - 1e-12 && radius <= 1.5 + 1e-12)
        }
        #expect((radii.min() ?? .nan) >= 0.5 - 1e-12)
        #expect((radii.max() ?? .nan) <= 1.5 + 1e-12)

        let start = orbit.offset(atDay: 0, period: 100)
        let nearPeriapsis = orbit.offset(atDay: 1, period: 100)
        let beforeApoapsis = orbit.offset(atDay: 49.5, period: 100)
        let afterApoapsis = orbit.offset(atDay: 50.5, period: 100)
        #expect(sweptAngle(from: start, to: nearPeriapsis) > sweptAngle(from: beforeApoapsis, to: afterApoapsis))
    }

    @Test func inclinationTiltsTheOrbitAboutItsXAxis() {
        let inclined = Orbit(distance: 3, period: 4, inclination: 30)
        let quarter = inclined.offset(atDay: 1, period: 4)
        #expect(abs(quarter.x) < 1e-12)
        #expect(abs(quarter.y - 3 * cos(Double.pi / 6)) < 1e-12)
        #expect(abs(quarter.z - 3 * sin(Double.pi / 6)) < 1e-12)

        let flat = Orbit(distance: 3, period: 4)
        let atStart = flat.offset(atDay: 0, period: 4)
        #expect(abs(atStart.x - 3) < 1e-12)
        #expect(abs(atStart.z) < 1e-12)
        for day in stride(from: 0.0, through: 4.0, by: 0.25) {
            #expect(abs(length(inclined.offset(atDay: day, period: 4)) - 3) < 1e-12)
        }
    }

    @Test(arguments: [-10.0, 0.0, 3.7, 1_000_000.0])
    func orbitalPositionRepeatsAfterOnePeriod(day: Double) {
        let orbit = Orbit(distance: 2.4, period: 17, eccentricity: 0.31, inclination: 12, startingAngle: 43)
        let first = orbit.offset(atDay: day, period: 17)
        let next = orbit.offset(atDay: day + 17, period: 17)
        #expect(distance(first, next) < 1e-6 * orbit.distance)
    }

    @Test func missingOrInvalidPeriodUsesTheDayZeroPosition() {
        let orbit = Orbit(distance: 1.7, eccentricity: 0.2, inclination: 17, startingAngle: 26)
        let dayZero = orbit.offset(atDay: 0, period: nil)
        #expect(distance(orbit.offset(atDay: 300, period: nil), dayZero) < 1e-12)
        for invalidPeriod in [0.0, -1.0, .nan, .infinity, -.infinity] {
            #expect(distance(orbit.offset(atDay: 300, period: invalidPeriod), dayZero) < 1e-12)
        }
    }

    @Test func orbitPathHasRequestedCountAndStaysOnTheTiltedEllipse() {
        let orbit = Orbit(distance: 2, eccentricity: 0.4, inclination: 30)
        #expect(orbit.pathOffsets(segments: 0).isEmpty)
        #expect(orbit.pathOffsets(segments: -2).isEmpty)

        let points = orbit.pathOffsets(segments: 16)
        #expect(points.count == 16)
        #expect(distance(points[0], SIMD3(1.2, 0, 0)) < 1e-12)
        for point in points {
            let radius = length(point)
            #expect(radius >= 2 * (1 - 0.4) - 1e-12)
            #expect(radius <= 2 * (1 + 0.4) + 1e-12)
            #expect(abs(point.z - point.y * tan(Double.pi / 6)) < 1e-12)
        }
    }
}

private func length(_ point: SIMD3<Double>) -> Double {
    sqrt(point.x * point.x + point.y * point.y + point.z * point.z)
}

private func distance(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
    length(lhs - rhs)
}

private func sweptAngle(from lhs: SIMD3<Double>, to rhs: SIMD3<Double>) -> Double {
    atan2(lhs.x * rhs.y - lhs.y * rhs.x, lhs.x * rhs.x + lhs.y * rhs.y)
}
