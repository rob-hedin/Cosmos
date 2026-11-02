import Foundation

/// One thing wrong with a Planetary System's input.
public enum PlanetarySystemProblem: Sendable, Hashable, CustomStringConvertible {
    /// Two of the star, Bodies and Belts share a name (reported once per extra occurrence).
    case duplicateName(String)
    /// A Body or Belt names a Parent that is neither the Central Star nor a Body in the system.
    case unknownParent(name: String, parent: String)
    /// Bodies whose Parents lead round in a circle, starting at the one listed first in the input
    /// and following Parent links (a Body that is its own Parent is a loop of one).
    case parentLoop([String])
    /// A Body's distance is negative, zero or not finite.
    case invalidDistance(body: String, distance: Double)
    /// A Kind rule is broken: a moon whose Parent is not a planet, dwarf planet or asteroid,
    /// or any other Kind whose Parent is not the Central Star.
    case kindRuleBroken(body: String, kind: Body.Kind, parent: Parent)
    /// Any other out-of-range number. `field` is one of "radius", "mass", "period",
    /// "eccentricity", "inclination", "startingAngle", "color.red", "color.green", "color.blue"
    /// (Bodies; a color component is converted to `Double`) or "mass", "radius", "temperature"
    /// (Central Star).
    case invalidValue(name: String, field: String, value: Double)
    /// A Belt edge is negative or not finite, or the inner edge is not below the outer edge.
    case invalidBeltEdges(belt: String, inner: Double, outer: Double)
    /// A Body has no period and its Parent Body has no mass, so the period can't be derived.
    case missingParentMass(body: String, parent: String)
    /// The Central Star's spectral type has no recognisable class and a value had to be estimated.
    case unrecognizedSpectralType(star: String, spectralType: String)
    /// JSON only: `catalogName` matched nothing in the catalog.
    case unknownCatalogStar(String)
    /// JSON only: `kind` is not one of the Kind raw values.
    case unknownKind(body: String, value: String)
    /// JSON only: `color` is not "#RRGGBB". (Out-of-range components of a Swift-supplied color
    /// are `invalidValue` with field "color.red" / "color.green" / "color.blue".)
    case invalidColor(body: String, value: String)

    /// One line in plain English naming the Body, Belt or star and what is wrong.
    public var description: String {
        switch self {
        case .duplicateName(let name):
            "The name \"\(name)\" is used more than once; names must be unique."
        case .unknownParent(let name, let parent):
            "\(name) orbits \"\(parent)\", which is neither the central star nor a body in the system."
        case .parentLoop(let names):
            "These bodies orbit each other in a circle: \(names.joined(separator: " -> ")) -> \(names.first ?? "")."
        case .invalidDistance(let body, let distance):
            "\(body) has an orbital distance of \(distance) AU; it must be a finite number above 0."
        case .kindRuleBroken(let body, let kind, let parent):
            Self.describeKindRule(body: body, kind: kind, parent: parent)
        case .invalidValue(let name, let field, let value):
            "\(name) has an invalid \(field) (\(value))."
        case .invalidBeltEdges(let belt, let inner, let outer):
            "\(belt) has bad edges (inner \(inner) AU, outer \(outer) AU); they must be finite, at least 0, and inner must be below outer."
        case .missingParentMass(let body, let parent):
            "\(body) has no period, and its parent \(parent) has no mass, so the period can't be worked out."
        case .unrecognizedSpectralType(let star, let spectralType):
            "The spectral type \"\(spectralType)\" of \(star) has no recognisable class, so its mass, radius or temperature can't be estimated."
        case .unknownCatalogStar(let name):
            "The catalog has no star named \"\(name)\"."
        case .unknownKind(let body, let value):
            "\(body) has an unknown kind \"\(value)\"; use planet, dwarf planet, moon, asteroid or comet."
        case .invalidColor(let body, let value):
            "\(body) has an invalid color \"\(value)\"; use the form #RRGGBB."
        }
    }

    private static func describeKindRule(body: String, kind: Body.Kind, parent: Parent) -> String {
        let parentText: String
        switch parent {
        case .centralStar: parentText = "the central star"
        case .body(let name): parentText = name
        }
        if kind == .moon {
            return "\(body) is a moon, so it must orbit a planet, dwarf planet or asteroid, not \(parentText)."
        }
        return "\(body) is a \(kind.rawValue), so it must orbit the central star, not \(parentText)."
    }
}

/// Thrown when a Planetary System's input has problems; lists all of them.
public struct PlanetarySystemError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Never empty.
    public let problems: [PlanetarySystemProblem]

    public init(problems: [PlanetarySystemProblem]) {
        self.problems = problems
    }

    /// The problems' descriptions, one per line.
    public var description: String {
        problems.map(\.description).joined(separator: "\n")
    }
}

// MARK: - Validation

/// A Body as the validator sees it. The JSON loader can't always build a `Body` (an unknown Kind
/// or a bad color has already been reported), so the validator works on these.
struct BodyCandidate {
    let name: String
    /// Nil when the Kind is unknown (JSON only); such a Body and its children skip the Kind rules.
    let kind: Body.Kind?
    let parent: Parent
    let orbit: Orbit
    let radius: Double
    let mass: Double?
    let color: SIMD3<Float>?

    init(_ body: Body) {
        self.init(
            name: body.name, kind: body.kind, parent: body.parent, orbit: body.orbit,
            radius: body.radius, mass: body.mass, color: body.color
        )
    }

    init(name: String, kind: Body.Kind?, parent: Parent, orbit: Orbit, radius: Double, mass: Double?, color: SIMD3<Float>?) {
        self.name = name
        self.kind = kind
        self.parent = parent
        self.orbit = orbit
        self.radius = radius
        self.mass = mass
        self.color = color
    }
}

/// The Central Star's numbers that the validator checks.
struct StarValues {
    let mass: Double
    let radius: Double
    let temperature: Double

    init(_ star: CentralStar) {
        mass = star.mass
        radius = star.radius
        temperature = star.temperature
    }
}

extension PlanetarySystem {
    /// Every problem in the input, or `[]` when it is valid. `starValues` is nil when the star
    /// couldn't be built (JSON only), so there is nothing to check.
    static func validate(
        starName: String,
        starValues: StarValues?,
        bodies: [BodyCandidate],
        belts: [Belt]
    ) -> [PlanetarySystemProblem] {
        var problems: [PlanetarySystemProblem] = []

        if let starValues {
            for (field, value) in [("mass", starValues.mass), ("radius", starValues.radius), ("temperature", starValues.temperature)]
            where !isPositiveAndFinite(value) {
                problems.append(.invalidValue(name: starName, field: field, value: value))
            }
        }

        // The first Body with a name is the one Parents refer to.
        let indexByName = Dictionary(bodies.enumerated().map { ($1.name, $0) }, uniquingKeysWith: { first, _ in first })
        var usedNames: Set<String> = [starName]

        for body in bodies {
            if !usedNames.insert(body.name).inserted {
                problems.append(.duplicateName(body.name))
            }
            problems += bodyProblems(body, bodies: bodies, indexByName: indexByName)
        }

        for belt in belts {
            if !usedNames.insert(belt.name).inserted {
                problems.append(.duplicateName(belt.name))
            }
            if case .body(let parentName) = belt.parent, indexByName[parentName] == nil {
                problems.append(.unknownParent(name: belt.name, parent: parentName))
            }
            let edgesAreValid = belt.innerEdge.isFinite && belt.innerEdge >= 0
                && belt.outerEdge.isFinite && belt.innerEdge < belt.outerEdge
            if !edgesAreValid {
                problems.append(.invalidBeltEdges(belt: belt.name, inner: belt.innerEdge, outer: belt.outerEdge))
            }
        }

        problems += parentLoops(in: bodies, indexByName: indexByName).map { .parentLoop($0) }
        return problems
    }

    private static func bodyProblems(
        _ body: BodyCandidate,
        bodies: [BodyCandidate],
        indexByName: [String: Int]
    ) -> [PlanetarySystemProblem] {
        var problems: [PlanetarySystemProblem] = []
        let name = body.name

        if !isPositiveAndFinite(body.orbit.distance) {
            problems.append(.invalidDistance(body: name, distance: body.orbit.distance))
        }

        func invalid(_ field: String, _ value: Double) {
            problems.append(.invalidValue(name: name, field: field, value: value))
        }
        if !isPositiveAndFinite(body.radius) { invalid("radius", body.radius) }
        if let mass = body.mass, !isPositiveAndFinite(mass) { invalid("mass", mass) }
        if let period = body.orbit.period, !isPositiveAndFinite(period) { invalid("period", period) }
        let eccentricity = body.orbit.eccentricity
        if !(eccentricity.isFinite && eccentricity >= 0 && eccentricity < 1) { invalid("eccentricity", eccentricity) }
        if !body.orbit.inclination.isFinite { invalid("inclination", body.orbit.inclination) }
        if !body.orbit.startingAngle.isFinite { invalid("startingAngle", body.orbit.startingAngle) }
        if let color = body.color {
            for (field, component) in [("color.red", color.x), ("color.green", color.y), ("color.blue", color.z)]
            where !(component.isFinite && component >= 0 && component <= 1) {
                invalid(field, Double(component))
            }
        }

        guard case .body(let parentName) = body.parent else {
            if body.kind == .moon {
                problems.append(.kindRuleBroken(body: name, kind: .moon, parent: .centralStar))
            }
            return problems
        }
        guard let parentIndex = indexByName[parentName] else {
            problems.append(.unknownParent(name: name, parent: parentName))
            return problems
        }

        let parent = bodies[parentIndex]
        if let kind = body.kind, let parentKind = parent.kind {
            let allowed = kind == .moon && [Body.Kind.planet, .dwarfPlanet, .asteroid].contains(parentKind)
            if !allowed {
                problems.append(.kindRuleBroken(body: name, kind: kind, parent: body.parent))
            }
        }
        if body.orbit.period == nil, parent.mass == nil {
            problems.append(.missingParentMass(body: name, parent: parentName))
        }
        return problems
    }

    /// Each cycle once, listing its Bodies from the one earliest in the input, following Parent links.
    /// Bodies that only lead into a cycle are not listed.
    private static func parentLoops(in bodies: [BodyCandidate], indexByName: [String: Int]) -> [[String]] {
        enum Visit { case unvisited, onPath, done }
        var visits = Array(repeating: Visit.unvisited, count: bodies.count)
        var loops: [[String]] = []

        for start in bodies.indices where visits[start] == .unvisited {
            var path: [Int] = []
            var next: Int? = start
            while let current = next, visits[current] == .unvisited {
                visits[current] = .onPath
                path.append(current)
                if case .body(let parentName) = bodies[current].parent {
                    next = indexByName[parentName]
                } else {
                    next = nil
                }
            }
            // The walk stopped on a Body already on this path: that Body is on a cycle.
            if let repeated = next, visits[repeated] == .onPath, let loopStart = path.firstIndex(of: repeated) {
                let cycle = Array(path[loopStart...])
                if let first = cycle.indices.min(by: { cycle[$0] < cycle[$1] }) {
                    loops.append((cycle[first...] + cycle[..<first]).map { bodies[$0].name })
                }
            }
            for index in path { visits[index] = .done }
        }
        return loops
    }

    private static func isPositiveAndFinite(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }
}
