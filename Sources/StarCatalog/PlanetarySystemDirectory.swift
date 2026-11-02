import Foundation

/// The Planetary Systems an app knows about, looked up by their Central Star. The star view uses
/// it to decide whether a star's info card offers "Show planetary system".
///
/// Matching uses the Central Star's catalog location. The Sun matches a system whose Central Star
/// is the Sun (`location == .sun`). A catalog star matches a system whose Central Star has the same
/// `starID`, so build systems against the catalog the view shows. Systems whose Central Star was
/// described from scratch (`location == nil`) are kept but never match a star. When several
/// systems match, the first wins.
public struct PlanetarySystemDirectory: Sendable, Equatable {
    /// In the order given.
    public let systems: [PlanetarySystem]

    /// A directory holding `systems`, in that order.
    public init(_ systems: [PlanetarySystem] = []) {
        self.systems = systems
    }

    /// The built-in Solar System, `PlanetarySystem.solarSystem()`, loaded once. It is empty if
    /// the bundled JSON can't be loaded.
    public static let builtIn: PlanetarySystemDirectory = {
        guard let solarSystem = try? PlanetarySystem.solarSystem() else { return .empty }
        return PlanetarySystemDirectory([solarSystem])
    }()

    /// No systems, so no star offers the button.
    public static let empty = PlanetarySystemDirectory()

    /// The system around the star at `location`, or nil.
    public func system(for location: StarLocation) -> PlanetarySystem? {
        system(matching: Self.key(location.starID))
    }

    /// The system around `star`, or nil. `Star.sun` (ID `Star.sunID`) looks up as the Sun.
    public func system(for star: Star) -> PlanetarySystem? {
        system(matching: Self.key(star.id))
    }

    private func system(matching queryKey: Star.ID?) -> PlanetarySystem? {
        systems.first { system in
            guard let location = system.centralStar.location else { return false }
            return Self.key(location.starID) == queryKey
        }
    }

    /// The Sun has no catalog ID, and `Star.sunID` stands for it, so both map to nil. Every other
    /// ID is left as it is.
    private static func key(_ starID: Star.ID?) -> Star.ID? {
        starID == Star.sunID ? nil : starID
    }
}
