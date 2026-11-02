import Foundation

extension StarCatalog {
    /// Stars whose names match `query` as you type: exact matches first, then names that start
    /// with it, then names with a word that starts with it, then names that contain it, brighter
    /// stars first within each. Also finds the Sun ("Sun", "Sol"), common aliases such as
    /// "Alpha Centauri", and catalog numbers such as "HIP 71683". Ignores case, accents and spacing.
    public func search(_ query: String, limit: Int = 8) -> [StarLocation] {
        let key = Self.searchKey(query)
        guard !key.isEmpty, limit > 0 else { return [] }
        let squeezedKey = key.filter { $0 != " " }

        var results: [(rank: Int, magnitude: Double, location: StarLocation)] = []
        var seen = Set<Star.ID>()
        func add(_ star: Star, rank: Int) {
            guard seen.insert(star.id).inserted else { return }
            // Catalog numbers rank after real names of the same kind.
            let rank = rank * 2 + (star.isCatalogDesignation ? 1 : 0)
            results.append((rank, star.apparentMagnitude, StarLocation(name: star.name, position: star.position, starID: star.id)))
        }

        if "sun".hasPrefix(key) || "sol".hasPrefix(key) {
            results.append((key == "sun" || key == "sol" ? -2 : 0, -26.7, .sun))
        }
        for (alias, name) in Self.aliases where alias.hasPrefix(key.replacingOccurrences(of: "'", with: "")) {
            if let star = star(named: name) { add(star, rank: alias == key ? -1 : 0) }
        }
        if let star = location(named: query).flatMap({ $0.starID }).flatMap(star(withID:)) {
            add(star, rank: -1)
        }
        for (star, name) in zip(stars, searchNames) {
            let rank: Int
            if name == key || name.filter({ $0 != " " }) == squeezedKey {
                rank = 0
            } else if name.hasPrefix(key) {
                rank = 1
            } else if name.split(separator: " ").contains(where: { $0.hasPrefix(key) }) {
                rank = 2
            } else if name.contains(key) {
                rank = 3
            } else {
                continue
            }
            add(star, rank: rank)
        }
        return results
            .sorted { ($0.rank, $0.magnitude, $0.location.name) < ($1.rank, $1.magnitude, $1.location.name) }
            .prefix(limit)
            .map(\.location)
    }

    /// Lowercased, without accents, with single spaces.
    static func searchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(separator: " ").joined(separator: " ")
    }
}
