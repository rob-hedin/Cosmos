import Foundation

/// One star from the catalog, with the derived values the renderer draws from.
public struct Star: Sendable, Hashable, Identifiable {
    /// Row index in the catalog, stable for a given CSV.
    public let id: Int

    // MARK: Catalog values

    /// Name as listed, with runs of spaces collapsed ("61    Cyg" becomes "61 Cyg").
    public let name: String
    public let hipparcosID: Int?
    public let henryDraperID: Int?
    public let constellation: String
    public let apparentMagnitude: Double
    public let absoluteMagnitude: Double
    public let spectralType: String?
    /// B-V color index.
    public let colorIndex: Double?
    /// The catalog's color name, such as "Orange" or "White dwarf".
    public let colorName: String
    public let rightAscensionHours: Double
    public let declinationDegrees: Double
    public let distanceLightYears: Double
    public let isNakedEye: Bool

    // MARK: Derived values

    /// Position in light years, Sun at the origin, equatorial frame (see `Astrophysics.position`).
    public let position: SIMD3<Float>
    /// Visual luminosity in solar units.
    public let luminosity: Double
    /// Effective temperature in kelvin, from B-V, else spectral class, else color name.
    public let temperature: Double
    /// Estimated radius in solar radii.
    public let estimatedRadius: Double
    /// Linear RGB, brightest channel 1.
    public let color: SIMD3<Float>

    /// True when the name is a catalog number (HD, HIP, GJ, Gl, HR) rather than a proper,
    /// Bayer or Flamsteed name. Labels show these only on demand.
    public var isCatalogDesignation: Bool {
        guard let prefix = name.split(separator: " ").first else { return true }
        return Self.catalogPrefixes.contains(String(prefix))
    }

    private static let catalogPrefixes: Set<String> = ["HD", "HIP", "GJ", "Gl", "HR"]

    public init(
        id: Int,
        name: String,
        hipparcosID: Int? = nil,
        henryDraperID: Int? = nil,
        constellation: String = "",
        apparentMagnitude: Double,
        absoluteMagnitude: Double,
        spectralType: String? = nil,
        colorIndex: Double? = nil,
        colorName: String = "Unknown",
        rightAscensionHours: Double,
        declinationDegrees: Double,
        distanceLightYears: Double,
        isNakedEye: Bool = false
    ) {
        self.id = id
        self.name = name.split(separator: " ").joined(separator: " ")
        self.hipparcosID = hipparcosID
        self.henryDraperID = henryDraperID
        self.constellation = constellation
        self.apparentMagnitude = apparentMagnitude
        self.absoluteMagnitude = absoluteMagnitude
        self.spectralType = spectralType
        self.colorIndex = colorIndex
        self.colorName = colorName
        self.rightAscensionHours = rightAscensionHours
        self.declinationDegrees = declinationDegrees
        self.distanceLightYears = distanceLightYears
        self.isNakedEye = isNakedEye

        position = SIMD3<Float>(Astrophysics.position(
            rightAscensionHours: rightAscensionHours,
            declinationDegrees: declinationDegrees,
            distanceLightYears: distanceLightYears
        ))
        luminosity = Astrophysics.luminosity(absoluteMagnitude: absoluteMagnitude)
        temperature = colorIndex.map(Astrophysics.temperature(colorIndex:))
            ?? spectralType.flatMap(Astrophysics.temperature(spectralType:))
            ?? Astrophysics.temperature(colorName: colorName)
            ?? Astrophysics.fallbackTemperature
        estimatedRadius = Astrophysics.estimatedRadius(luminosity: luminosity, temperature: temperature)
        color = Astrophysics.color(temperature: temperature)
    }
}
