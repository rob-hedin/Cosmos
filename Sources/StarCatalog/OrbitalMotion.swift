import Foundation

extension Orbit {
    /// Solves Kepler's equation E − e·sin E = M for the eccentric anomaly (radians), by Newton's
    /// method (start at M for e < 0.8, else π; at most 50 steps; stop when |ΔE| < 1e-14).
    ///
    /// Any finite mean anomaly works: it is reduced to one turn first, and the whole turns are added
    /// back to the result. A circular orbit (e = 0) returns the mean anomaly as it is. An
    /// eccentricity outside 0..<1, which `PlanetarySystem` never allows, is treated the same way.
    public static func eccentricAnomaly(meanAnomaly: Double, eccentricity: Double) -> Double {
        guard meanAnomaly.isFinite, eccentricity > 0, eccentricity < 1 else { return meanAnomaly }
        let turn = 2 * Double.pi
        let wholeTurns = (meanAnomaly / turn).rounded()
        let reduced = meanAnomaly - wholeTurns * turn
        // Solve for the mirror image in 0...π, where the equation is convex and Newton's method
        // converges steadily from either starting point.
        let target = abs(reduced)
        var anomaly = eccentricity < 0.8 ? target : Double.pi
        for _ in 0..<50 {
            let step = (anomaly - eccentricity * sin(anomaly) - target) / (1 - eccentricity * cos(anomaly))
            anomaly -= step
            if abs(step) < 1e-14 { break }
        }
        return (reduced < 0 ? -anomaly : anomaly) + wholeTurns * turn
    }

    /// Offset from the Parent in AU, `day` days after the start, for an orbit of `period` days.
    ///
    /// The mean anomaly is `startingAngle` (degrees to radians) plus 2π·day/period. The ellipse has
    /// its periapsis on +x, and the Body moves counterclockwise seen from +z: in the orbit plane,
    /// x = a(cos E − e) and y = a·√(1−e²)·sin E. The plane is then tilted by `inclination` about the
    /// x axis (y' = y cos i, z' = y sin i). A nil, non-finite or non-positive period gives the
    /// position at day 0. Any finite day works, negative included.
    public func offset(atDay day: Double, period: Double?) -> SIMD3<Double> {
        var meanAnomaly = startingAngle * .pi / 180
        if let period, period.isFinite, period > 0, day.isFinite {
            // Only the fractional part of the revolutions matters, so keep it small before scaling.
            let revolutions = (day / period).truncatingRemainder(dividingBy: 1)
            meanAnomaly += 2 * .pi * revolutions
        }
        return point(atEccentricAnomaly: Self.eccentricAnomaly(meanAnomaly: meanAnomaly, eccentricity: eccentricity))
    }

    /// `segments` points around the orbit in AU (no repeat of the first), evenly spaced in
    /// eccentric anomaly and starting at periapsis (E = 0); tilted like `offset`. Empty when
    /// `segments` < 1.
    public func pathOffsets(segments: Int) -> [SIMD3<Double>] {
        guard segments >= 1 else { return [] }
        return (0..<segments).map { index in
            point(atEccentricAnomaly: 2 * .pi * Double(index) / Double(segments))
        }
    }

    /// The point on the tilted ellipse at an eccentric anomaly.
    private func point(atEccentricAnomaly anomaly: Double) -> SIMD3<Double> {
        let inclinationRadians = inclination * .pi / 180
        let x = distance * (cos(anomaly) - eccentricity)
        let y = distance * (1 - eccentricity * eccentricity).squareRoot() * sin(anomaly)
        return SIMD3(x, y * cos(inclinationRadians), y * sin(inclinationRadians))
    }
}
