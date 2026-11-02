import Foundation

/// The facts an info card shows for one item of a Planetary System: a title and labeled rows.
///
/// Rows for a Body, in order: Kind, Parent, Distance (the semi-major axis), Period, Radius, Mass
/// (only when known) and Belt (only when the Body lies in one). Rows for the Central Star: Kind,
/// Spectral type, Mass, Radius and Temperature. Numbers are formatted for `locale`.
public struct PlanetarySystemFacts: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public let label: String
        public let value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    /// The item's name.
    public let title: String
    public let rows: [Row]

    /// Below this distance (AU) a Body's distance is shown in km.
    private static let kilometerDistanceLimit = 0.01
    /// Periods below this many days are shown in days, the rest in years.
    private static let dayPeriodLimit = 2 * Astrophysics.daysPerYear

    /// The facts for `item`. Nil for a Body name that is not in the system.
    public init?(item: PlanetarySystemItem, in system: PlanetarySystem, locale: Locale = .current) {
        switch item {
        case .centralStar:
            let star = system.centralStar
            title = star.name
            rows = [
                Row(label: "Kind", value: "Star"),
                Row(label: "Spectral type", value: star.spectralType ?? "Unknown"),
                Row(label: "Mass", value: "\(Self.significant(star.mass, locale)) M☉"),
                Row(label: "Radius", value: "\(Self.significant(star.radius, locale)) R☉"),
                Row(label: "Temperature", value: "\(Self.whole(star.temperature, locale)) K"),
            ]
        case .body(let name):
            guard let body = system.body(named: name) else { return nil }
            title = body.name
            var rows = [
                Row(label: "Kind", value: body.kind.displayName),
                Row(label: "Parent", value: Self.parentName(of: body, in: system)),
                Row(label: "Distance", value: Self.distance(body.orbit.distance, locale)),
            ]
            if let period = system.orbitalPeriod(of: body) {
                rows.append(Row(label: "Period", value: Self.period(period, locale)))
            }
            rows.append(Row(label: "Radius", value: "\(Self.whole(body.radius, locale)) km"))
            if let mass = body.mass {
                rows.append(Row(label: "Mass", value: "\(Self.significant(mass, locale)) M⊕"))
            }
            if let belt = system.belt(containing: body) {
                rows.append(Row(label: "Belt", value: belt.name))
            }
            self.rows = rows
        }
    }

    private static func parentName(of body: Body, in system: PlanetarySystem) -> String {
        switch body.parent {
        case .centralStar: system.centralStar.name
        case .body(let name): name
        }
    }

    /// Kilometres below 0.01 AU, else AU.
    private static func distance(_ astronomicalUnits: Double, _ locale: Locale) -> String {
        if astronomicalUnits < kilometerDistanceLimit {
            return "\(whole(astronomicalUnits * Astrophysics.kilometersPerAU, locale)) km"
        }
        return "\(significant(astronomicalUnits, locale)) AU"
    }

    /// Days below two years, else years; the unit is singular when the number shows as 1.
    private static func period(_ days: Double, _ locale: Locale) -> String {
        let useDays = days < dayPeriodLimit
        let number = significant(useDays ? days : days / Astrophysics.daysPerYear, locale)
        let unit = useDays ? "day" : "year"
        return number == "1" ? "1 \(unit)" : "\(number) \(unit)s"
    }

    /// One to three significant digits.
    private static func significant(_ value: Double, _ locale: Locale) -> String {
        value.formatted(.number.precision(.significantDigits(1...3)).locale(locale))
    }

    /// Rounded to a whole number, with digit grouping.
    private static func whole(_ value: Double, _ locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }
}
