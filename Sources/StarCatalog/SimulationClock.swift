import Foundation

/// How fast simulated time runs, in days per real second.
public struct SimulationSpeed: Sendable, Hashable {
    /// Simulated days per real second, clamped to `range`. NaN gives `.day`.
    public let daysPerSecond: Double

    /// The slowest and fastest speeds: 1 day per second to 1 year per second.
    public static let range: ClosedRange<Double> = 1...Astrophysics.daysPerYear

    /// Values outside `range` are clamped to it, and NaN gives one day per second.
    public init(daysPerSecond: Double) {
        if daysPerSecond.isNaN {
            self.daysPerSecond = Self.range.lowerBound
        } else {
            self.daysPerSecond = min(max(daysPerSecond, Self.range.lowerBound), Self.range.upperBound)
        }
    }

    /// One day per second.
    public static let day = SimulationSpeed(daysPerSecond: 1)
    /// One week per second.
    public static let week = SimulationSpeed(daysPerSecond: 7)
    /// One twelfth of a year per second.
    public static let month = SimulationSpeed(daysPerSecond: Astrophysics.daysPerYear / 12)
    /// One year per second.
    public static let year = SimulationSpeed(daysPerSecond: Astrophysics.daysPerYear)

    /// `.day`, `.week`, `.month` and `.year`, slowest first.
    public static let presets: [SimulationSpeed] = [.day, .week, .month, .year]

    /// "1 day", "1 week", "1 month" or "1 year" for the presets, otherwise "N days" with up to
    /// three significant digits.
    public var displayName: String {
        switch self {
        case .day: return "1 day"
        case .week: return "1 week"
        case .month: return "1 month"
        case .year: return "1 year"
        default:
            let number = daysPerSecond.formatted(.number.precision(.significantDigits(1...3)))
            return number == "1" ? "1 day" : "\(number) days"
        }
    }
}

/// The time shown in a Planetary System view: a day count, a speed and a pause switch.
public struct SimulationClock: Sendable, Equatable {
    /// Simulated days since the start.
    public var day: Double = 0
    public var speed: SimulationSpeed = .week
    public var isPaused = false

    /// A longer gap between frames (the app in the background, a hitch) counts as this many seconds.
    public static let maximumStep: Double = 0.1

    public init(day: Double = 0, speed: SimulationSpeed = .week, isPaused: Bool = false) {
        self.day = day
        self.speed = speed
        self.isPaused = isPaused
    }

    /// Adds min(seconds, `maximumStep`) × the speed's days per second, unless paused. A negative or
    /// non-finite `seconds` does nothing.
    public mutating func advance(bySeconds seconds: Double) {
        guard !isPaused, seconds.isFinite, seconds > 0 else { return }
        day += min(seconds, Self.maximumStep) * speed.daysPerSecond
    }
}
