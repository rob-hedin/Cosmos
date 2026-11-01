import Foundation

/// How a star's on-screen size is chosen.
public enum StarSizeMode: String, Sendable, CaseIterable {
    /// Size grows with visual luminosity: how bright the star really is.
    case luminosity
    /// Size grows with estimated physical radius (an estimate; the data has no measured radii).
    case estimatedRadius
}

public enum StarCatalogError: Error, Equatable {
    case resourceNotFound
    case missingColumn(String)
    case malformedRow(line: Int, column: String, value: String)
}

/// The full set of stars, loaded from the bundled CSV or any CSV with the same columns.
public struct StarCatalog: Sendable, Equatable {
    public let stars: [Star]
    private let indexByID: [Star.ID: Int]

    /// Stars may come in any order, and their IDs need not match their positions (a filtered or
    /// reordered catalog keeps the original IDs). If IDs repeat, the first star with an ID wins.
    public init(stars: [Star]) {
        self.stars = stars
        indexByID = Dictionary(stars.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The 11,975 stars within 200 light years that ship with the package.
    public static func bundled() throws -> StarCatalog {
        guard let url = Bundle.module.url(forResource: "stars", withExtension: "csv") else {
            throw StarCatalogError.resourceNotFound
        }
        return try StarCatalog(contentsOf: url)
    }

    public init(contentsOf url: URL) throws {
        try self.init(csv: String(contentsOf: url, encoding: .utf8))
    }

    /// Parses CSV text with a header row. Columns are found by name, so their order does not matter.
    /// Fields must not contain commas or quotes (the bundled file has none).
    public init(csv: String) throws {
        var lines = csv.split(whereSeparator: \.isNewline).makeIterator()
        guard let header = lines.next() else { throw StarCatalogError.missingColumn(Column.name) }

        let names = header.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        func index(of column: String) throws -> Int {
            guard let i = names.firstIndex(of: column) else { throw StarCatalogError.missingColumn(column) }
            return i
        }
        let col = try Columns(
            name: index(of: Column.name),
            hip: index(of: Column.hip),
            hd: index(of: Column.hd),
            constellation: index(of: Column.constellation),
            apparentMagnitude: index(of: Column.apparentMagnitude),
            absoluteMagnitude: index(of: Column.absoluteMagnitude),
            spectralType: index(of: Column.spectralType),
            colorIndex: index(of: Column.colorIndex),
            colorName: index(of: Column.colorName),
            rightAscension: index(of: Column.rightAscension),
            declination: index(of: Column.declination),
            distance: index(of: Column.distance),
            nakedEye: index(of: Column.nakedEye)
        )

        var stars: [Star] = []
        var lineNumber = 1
        while let line = lines.next() {
            lineNumber += 1
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == names.count else {
                throw StarCatalogError.malformedRow(line: lineNumber, column: "*", value: String(line))
            }
            func optional(_ i: Int) -> String? { fields[i].isEmpty ? nil : fields[i] }
            func number(_ i: Int, _ column: String) throws -> Double {
                guard let value = Double(fields[i]) else {
                    throw StarCatalogError.malformedRow(line: lineNumber, column: column, value: fields[i])
                }
                return value
            }

            stars.append(Star(
                id: stars.count,
                name: fields[col.name],
                hipparcosID: optional(col.hip).flatMap { Int($0) },
                henryDraperID: optional(col.hd).flatMap { Int($0) },
                constellation: fields[col.constellation],
                apparentMagnitude: try number(col.apparentMagnitude, Column.apparentMagnitude),
                absoluteMagnitude: try number(col.absoluteMagnitude, Column.absoluteMagnitude),
                spectralType: optional(col.spectralType),
                colorIndex: optional(col.colorIndex).flatMap { Double($0) },
                colorName: fields[col.colorName],
                rightAscensionHours: try number(col.rightAscension, Column.rightAscension),
                declinationDegrees: try number(col.declination, Column.declination),
                distanceLightYears: try number(col.distance, Column.distance),
                isNakedEye: fields[col.nakedEye] == "Yes"
            ))
        }
        self.init(stars: stars)
    }

    /// The star with the given ID, wherever it sits in `stars`.
    public func star(withID id: Star.ID) -> Star? {
        indexByID[id].map { stars[$0] }
    }

    /// First star whose name matches, ignoring case and extra spaces.
    public func star(named name: String) -> Star? {
        let wanted = Star.tidyName(name)
        return stars.first { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    /// A size in 0...1 for every star, in `stars` order. Sizes scale with the logarithm of the
    /// chosen quantity across the whole catalog, so faint dwarfs and giants both stay in range.
    public func normalizedSizes(for mode: StarSizeMode) -> [Float] {
        let values = stars.map { star in
            switch mode {
            case .luminosity: log10(star.luminosity)
            case .estimatedRadius: log10(star.estimatedRadius)
            }
        }
        guard let low = values.min(), let high = values.max(), high > low else {
            return Array(repeating: 1, count: values.count)
        }
        return values.map { Float(($0 - low) / (high - low)) }
    }
}

private struct Columns {
    let name, hip, hd, constellation, apparentMagnitude, absoluteMagnitude: Int
    let spectralType, colorIndex, colorName, rightAscension, declination, distance, nakedEye: Int
}

/// Header names in the catalog CSV.
enum Column {
    static let name = "Name"
    static let hip = "HIP"
    static let hd = "HD"
    static let constellation = "Constellation"
    static let apparentMagnitude = "Apparent mag"
    static let absoluteMagnitude = "Absolute mag"
    static let spectralType = "Spectral type"
    static let colorIndex = "B-V"
    static let colorName = "Color"
    static let rightAscension = "RA (h)"
    static let declination = "Dec (deg)"
    static let distance = "Distance (ly)"
    static let nakedEye = "Naked eye (mag≤6)"
}
