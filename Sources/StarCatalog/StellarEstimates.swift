import Foundation

extension Astrophysics {
    /// Earth masses in one solar mass (IAU 2015 nominal values).
    public static let earthMassesPerSolarMass = 332_946.0487

    /// Days in a Julian year.
    public static let daysPerYear = 365.25

    /// Kilometres in one astronomical unit (IAU 2012).
    public static let kilometersPerAU = 149_597_870.7

    /// Kilometres in one nominal solar radius (IAU 2015).
    public static let kilometersPerSolarRadius = 695_700.0

    /// Earth's mean radius in km; the reference size for drawn Bodies.
    public static let earthRadiusKilometers = 6_371.0

    // MARK: Mass and radius from spectral type

    /// Main-sequence mass estimate in solar masses from a type such as "G2V", "M4.5V", "sdM4" or "k-m".
    ///
    /// This is a rough estimate. It ignores the luminosity class and treats every star as a main-sequence
    /// star, so giants and supergiants come out far too light. White dwarfs (class D) are 0.6.
    /// A missing subclass counts as 5. Returns nil when no class letter is found.
    public static func estimatedMass(spectralType: String) -> Double? {
        guard let spectralClass = spectralClass(of: spectralType) else { return nil }
        return mass(spectralClass: spectralClass, subclass: spectralSubclass(of: spectralType) ?? defaultSubclass)
    }

    /// Mass estimate in solar masses for a star known only by its temperature: the class (O to T, not D)
    /// whose typical temperature is nearest, at subclass 5. See `estimatedMass(spectralType:)` for the caveats.
    public static func estimatedMass(temperature: Double) -> Double {
        var best = massSequence[0]
        var bestDistance = Double.infinity
        for spectralClass in massSequence {
            guard let typical = classTemperatures[spectralClass] else { continue }
            let distance = abs(typical - temperature)
            if distance < bestDistance {
                best = spectralClass
                bestDistance = distance
            }
        }
        return mass(spectralClass: best, subclass: defaultSubclass)
    }

    /// Main-sequence radius estimate in solar radii: mass^0.8, from `estimatedMass(spectralType:)`.
    /// White dwarfs (class D) are 0.013. Returns nil when no class letter is found.
    public static func estimatedRadius(spectralType: String) -> Double? {
        guard let spectralClass = spectralClass(of: spectralType) else { return nil }
        if spectralClass == "D" { return whiteDwarfRadius }
        return estimatedMass(spectralType: spectralType).map { pow($0, 0.8) }
    }

    // MARK: Kepler

    /// Kepler's third law: the period in days of an orbit with this semi-major axis (AU) around
    /// this total mass (solar masses): `daysPerYear * sqrt(a³ / M)`.
    public static func orbitalPeriod(semiMajorAxis: Double, totalMass: Double) -> Double {
        daysPerYear * (semiMajorAxis * semiMajorAxis * semiMajorAxis / totalMass).squareRoot()
    }

    // MARK: Subclass

    /// The subclass number after the class letter ("G2V" is 2, "M4.5V" is 4.5), clamped to 0...9.5.
    /// Nil when no number follows the class letter.
    static func spectralSubclass(of spectralType: String) -> Double? {
        guard let spectralClass = spectralClass(of: spectralType) else { return nil }
        let lowercase = Character(spectralClass.lowercased())
        guard let classIndex = spectralType.firstIndex(of: spectralClass) ?? spectralType.firstIndex(of: lowercase)
        else { return nil }

        let rest = spectralType[spectralType.index(after: classIndex)...]
        let integerPart = rest.prefix { $0.isASCII && $0.isNumber }
        guard !integerPart.isEmpty else { return nil }
        var number = String(integerPart)
        let afterInteger = rest.dropFirst(integerPart.count)
        if afterInteger.first == "." {
            let fraction = afterInteger.dropFirst().prefix { $0.isASCII && $0.isNumber }
            if !fraction.isEmpty { number += "." + fraction }
        }
        return Double(number).map { min(max($0, 0), 9.5) }
    }

    // MARK: Tables

    private static let defaultSubclass = 5.0
    private static let whiteDwarfMass = 0.6
    private static let whiteDwarfRadius = 0.013

    /// Classes from hottest to coolest, without white dwarfs.
    private static let massSequence: [Character] = ["O", "B", "A", "F", "G", "K", "M", "L", "T"]

    /// Main-sequence masses in solar masses at subclass 0 of each class in `massSequence`, then the mass
    /// where the next class would start after T9 (after Pecaut and Mamajek's table, rounded).
    private static let massAnchors: [Double] = [60, 17.5, 2.3, 1.6, 1.1, 0.88, 0.57, 0.08, 0.06, 0.03]

    /// Log-linear interpolation between this class's anchor and the next one, by subclass / 10.
    private static func mass(spectralClass: Character, subclass: Double) -> Double {
        if spectralClass == "D" { return whiteDwarfMass }
        guard let index = massSequence.firstIndex(of: spectralClass) else { return whiteDwarfMass }
        let low = massAnchors[index]
        let high = massAnchors[index + 1]
        let fraction = min(max(subclass, 0), 10) / 10
        return low * pow(high / low, fraction)
    }
}
