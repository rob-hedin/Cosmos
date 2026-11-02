import Foundation

/// A star's broad spectral class, from its spectral type.
public enum SpectralClass: String, Sendable, Hashable, CaseIterable, Identifiable {
    case o = "O", b = "B", a = "A", f = "F", g = "G", k = "K", m = "M"
    case whiteDwarf = "D"
    /// Carbon stars, Wolf-Rayet stars, brown dwarfs and stars with no spectral type.
    case other = "?"

    public var id: Self { self }

    /// "O" through "M", "White dwarf" or "Other".
    public var title: String {
        switch self {
        case .whiteDwarf: "White dwarf"
        case .other: "Other"
        default: rawValue
        }
    }

    /// Reads a type such as "G2V", "dM3", "sdK5", "DA2" or the catalog's color-based "k-m".
    public init(spectralType: String?) {
        guard let type = spectralType?.trimmingCharacters(in: .whitespaces), let first = type.first else {
            self = .other
            return
        }
        // White dwarfs: "D" then an uppercase letter or digit (DA, DB, DQ, DZ9...).
        if first == "D", let second = type.dropFirst().first, second.isUppercase || second.isNumber {
            self = .whiteDwarf
            return
        }
        // Luminosity prefixes: dwarf, subdwarf, extreme and ultra subdwarf.
        var rest = Substring(type)
        for prefix in ["usd", "esd", "sd", "d"] where rest.hasPrefix(prefix) {
            let after = rest.dropFirst(prefix.count)
            if after.first?.isUppercase == true {
                rest = after
                break
            }
        }
        self = rest.first.flatMap { SpectralClass(rawValue: $0.uppercased()) }
            .flatMap { $0 == .whiteDwarf || $0 == .other ? nil : $0 } ?? .other
    }
}

extension Star {
    public var spectralClass: SpectralClass {
        SpectralClass(spectralType: spectralType)
    }
}

/// Which stars to show. The default shows every star.
public struct StarFilter: Sendable, Hashable {
    /// Distance from the Sun, in light years.
    public var distance: ClosedRange<Double>
    public var spectralClasses: Set<SpectralClass>
    /// Show only stars at least this bright, as an absolute magnitude (lower is brighter).
    /// Nil shows every brightness.
    public var brightestAbsoluteMagnitude: Double?
    /// Show only stars in double or multiple systems.
    public var multipleSystemsOnly: Bool

    public init(
        distance: ClosedRange<Double> = 0...Double.infinity,
        spectralClasses: Set<SpectralClass> = Set(SpectralClass.allCases),
        brightestAbsoluteMagnitude: Double? = nil,
        multipleSystemsOnly: Bool = false
    ) {
        self.distance = distance
        self.spectralClasses = spectralClasses
        self.brightestAbsoluteMagnitude = brightestAbsoluteMagnitude
        self.multipleSystemsOnly = multipleSystemsOnly
    }

    /// Shows every star.
    public static let all = StarFilter()

    /// True when this hides nothing.
    public var showsEverything: Bool {
        distance.lowerBound <= 0 && distance.upperBound == .infinity
            && spectralClasses.isSuperset(of: SpectralClass.allCases)
            && brightestAbsoluteMagnitude == nil && !multipleSystemsOnly
    }

    public func includes(_ star: Star, in catalog: StarCatalog) -> Bool {
        distance.contains(star.distanceLightYears)
            && spectralClasses.contains(star.spectralClass)
            && brightestAbsoluteMagnitude.map { star.absoluteMagnitude <= $0 } ?? true
            && (!multipleSystemsOnly || catalog.isInMultipleSystem(star))
    }
}

extension StarCatalog {
    /// Stars that `filter` shows, in `stars` order.
    public func stars(matching filter: StarFilter) -> [Star] {
        filter.showsEverything ? stars : stars.filter { filter.includes($0, in: self) }
    }

    /// True for a star in a double or multiple system. The catalog has no multiplicity column,
    /// so this counts a star whose spectral type lists a companion ("G8V + K4V"), or that has a
    /// neighbor within 0.3 ly across the sky and at a matching distance (within 0.5 ly or 5%,
    /// allowing for parallax error).
    public func isInMultipleSystem(_ star: Star) -> Bool {
        multipleSystemIDs.contains(star.id)
    }

    static let companionSeparation = 0.3

    static func findMultipleSystems(in stars: [Star]) -> Set<Star.ID> {
        var ids = Set(stars.filter { $0.spectralType?.contains("+") == true }.map(\.id))
        let directions = stars.map { star -> SIMD3<Double> in
            let distance = max(star.distanceLightYears, 1e-9)
            return SIMD3<Double>(star.position) / distance
        }
        func areCompanions(_ i: Int, _ j: Int) -> Bool {
            let (a, b) = (stars[i].distanceLightYears, stars[j].distanceLightYears)
            guard abs(a - b) <= max(0.5, 0.05 * max(a, b)) else { return false }
            let cosine = min(max((directions[i] * directions[j]).sum(), -1), 1)
            return acos(cosine) * min(a, b) <= companionSeparation
        }
        func pair(_ i: Int, _ j: Int) {
            guard areCompanions(i, j) else { return }
            ids.insert(stars[i].id)
            ids.insert(stars[j].id)
        }

        // Nearby stars can be companions many degrees apart, so compare them all.
        let nearLimit = 25.0
        let near = stars.indices.filter { stars[$0].distanceLightYears < nearLimit }
        for (n, i) in near.enumerated() {
            for j in near[(n + 1)...] { pair(i, j) }
        }
        // Farther out, companions are within a few tenths of a degree: bucket by direction.
        // At 20 ly a 0.3 ly separation is under 0.015 rad, less than one cell.
        let cellsPerUnit = 50.0
        func cell(_ d: SIMD3<Double>) -> SIMD3<Int> {
            SIMD3(Int((d.x * cellsPerUnit).rounded(.down)), Int((d.y * cellsPerUnit).rounded(.down)),
                  Int((d.z * cellsPerUnit).rounded(.down)))
        }
        var buckets: [SIMD3<Int>: [Int]] = [:]
        for i in stars.indices where stars[i].distanceLightYears >= nearLimit - 5 {
            buckets[cell(directions[i]), default: []].append(i)
        }
        for i in stars.indices where stars[i].distanceLightYears >= nearLimit {
            let home = cell(directions[i])
            for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        for j in buckets[home &+ SIMD3(dx, dy, dz)] ?? [] where j != i {
                            // Each far pair is seen from both ends; near-near pairs were done above.
                            if stars[j].distanceLightYears >= nearLimit, j < i { continue }
                            pair(i, j)
                        }
                    }
                }
            }
        }
        return ids
    }
}
