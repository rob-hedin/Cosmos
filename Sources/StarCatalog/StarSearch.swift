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

        // Tiers: 0 exact, 1 prefix, 2 word prefix, 3 anywhere. Each star keeps its best tier.
        var results: [(rank: Int, magnitude: Double, location: StarLocation)] = []
        var slot: [Star.ID: Int] = [:]
        func add(_ star: Star, rank: Int) {
            // Catalog numbers rank after real names in the same tier.
            let rank = rank * 2 + (star.isCatalogDesignation ? 1 : 0)
            if let index = slot[star.id] {
                results[index].rank = min(results[index].rank, rank)
                return
            }
            slot[star.id] = results.count
            results.append((rank, star.apparentMagnitude, StarLocation(name: star.name, position: star.position, starID: star.id)))
        }

        if "sun".hasPrefix(key) || "sol".hasPrefix(key) {
            results.append((key == "sun" || key == "sol" ? 0 : 2, -26.7, .sun))
        }
        let aliasKey = key.replacingOccurrences(of: "'", with: "")
        for (alias, name) in Self.aliases where alias.hasPrefix(aliasKey) {
            if let star = star(named: name) { add(star, rank: alias == aliasKey ? 0 : 1) }
        }
        // "hip 7168" suggests every star whose HIP number starts with 7168, named or not.
        let parts = key.split(separator: " ")
        if parts.count == 2, ["hip", "hd"].contains(parts[0]), parts[1].allSatisfy(\.isNumber) {
            let digits = String(parts[1])
            for star in stars {
                guard let number = parts[0] == "hip" ? star.hipparcosID : star.henryDraperID else { continue }
                let text = String(number)
                if text.hasPrefix(digits) { add(star, rank: text == digits ? 0 : 1) }
            }
        }
        for (star, name) in zip(stars, searchNames) {
            let rank: Int
            if name == key || name.filter({ $0 != " " }) == squeezedKey {
                rank = 0
            } else if name.hasPrefix(key) {
                rank = 1
            } else if name.contains(" " + key) {
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
