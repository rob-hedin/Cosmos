import Foundation

/// The star at the middle of a Planetary System.
public struct CentralStar: Sendable, Hashable {
    public let name: String
    /// Nil only for a catalog star whose row has no spectral type.
    public let spectralType: String?
    /// Solar masses.
    public let mass: Double
    /// Solar radii.
    public let radius: Double
    /// Kelvin.
    public let temperature: Double
    /// Where the star is in the catalog: `.sun` for the Sun, the star's location for a catalog
    /// star, nil for a star described from scratch.
    public let location: StarLocation?

    /// The Sun: "Sun", "G2V", 1 solar mass, 1 solar radius, `Astrophysics.solarTemperature`, location `.sun`.
    public static let sun = CentralStar(
        name: "Sun", spectralType: "G2V", mass: 1, radius: 1,
        temperature: Astrophysics.solarTemperature, location: .sun
    )

    /// A catalog star. Name, spectral type, location (with `starID == star.id`), temperature
    /// (`star.temperature`) and radius (`star.estimatedRadius`) come from the catalog; mass is
    /// `Astrophysics.estimatedMass(spectralType:)`, falling back to
    /// `Astrophysics.estimatedMass(temperature:)` when the type is missing or unrecognised.
    ///
    /// Does not throw and copies the values as they are: `Star.init` does not check its inputs, so an
    /// extreme row can give a zero, NaN or infinite radius or temperature. `PlanetarySystem.init`
    /// checks these values, so such a star can exist but cannot become part of a system.
    public init(catalogStar star: Star) {
        let estimatedMass = star.spectralType.flatMap { Astrophysics.estimatedMass(spectralType: $0) }
            ?? Astrophysics.estimatedMass(temperature: star.temperature)
        self.init(
            name: star.name,
            spectralType: star.spectralType,
            mass: estimatedMass,
            radius: star.estimatedRadius,
            temperature: star.temperature,
            location: StarLocation(name: star.name, position: star.position, starID: star.id)
        )
    }

    /// A star described from scratch. Values not given are estimated from the spectral type:
    /// mass by `estimatedMass(spectralType:)`, radius by `estimatedRadius(spectralType:)`,
    /// temperature by `temperature(spectralType:)`.
    ///
    /// Throws `.unrecognizedSpectralType` when a value must be estimated and the type has no
    /// recognisable class, and `.invalidValue` for any given value that is not finite and above 0.
    /// All problems are collected before throwing.
    public init(
        name: String,
        spectralType: String,
        mass: Double? = nil,
        radius: Double? = nil,
        temperature: Double? = nil
    ) throws(PlanetarySystemError) {
        var problems: [PlanetarySystemProblem] = []
        for (field, value) in [("mass", mass), ("radius", radius), ("temperature", temperature)] {
            if let value, !(value.isFinite && value > 0) {
                problems.append(.invalidValue(name: name, field: field, value: value))
            }
        }

        let resolvedMass = mass ?? Astrophysics.estimatedMass(spectralType: spectralType)
        let resolvedRadius = radius ?? Astrophysics.estimatedRadius(spectralType: spectralType)
        let resolvedTemperature = temperature ?? Astrophysics.temperature(spectralType: spectralType)
        guard let resolvedMass, let resolvedRadius, let resolvedTemperature else {
            problems.append(.unrecognizedSpectralType(star: name, spectralType: spectralType))
            throw PlanetarySystemError(problems: problems)
        }
        guard problems.isEmpty else { throw PlanetarySystemError(problems: problems) }

        self.init(
            name: name, spectralType: spectralType, mass: resolvedMass, radius: resolvedRadius,
            temperature: resolvedTemperature, location: nil
        )
    }

    private init(
        name: String,
        spectralType: String?,
        mass: Double,
        radius: Double,
        temperature: Double,
        location: StarLocation?
    ) {
        self.name = name
        self.spectralType = spectralType
        self.mass = mass
        self.radius = radius
        self.temperature = temperature
        self.location = location
    }
}
