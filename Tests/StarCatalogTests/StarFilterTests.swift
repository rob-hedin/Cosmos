import Foundation
import Testing
@testable import StarCatalog

@Suite struct SpectralClassTests {
    @Test(arguments: [
        ("G2V", SpectralClass.g), ("A0Vvar", .a), ("dM3", .m), ("sdK5", .k), ("esdM1", .m),
        ("DA2", .whiteDwarf), ("DZ9+", .whiteDwarf), ("DG", .whiteDwarf), ("k-m", .k), ("m+", .m),
        ("O9.5V", .o), ("B8Ia", .b), ("F5IV-V", .f), ("C(R)", .other), ("WN..", .other), ("", .other),
    ] as [(String, SpectralClass)])
    func parsesSpectralTypes(type: String, expected: SpectralClass) {
        #expect(SpectralClass(spectralType: type) == expected)
    }

    @Test func missingTypeIsOther() {
        #expect(SpectralClass(spectralType: nil) == .other)
    }
}

@Suite struct StarFilterTests {
    let catalog: StarCatalog

    init() throws {
        catalog = try StarCatalog.bundled()
    }

    @Test func defaultFilterShowsEverything() {
        #expect(StarFilter.all.showsEverything)
        #expect(catalog.stars(matching: .all).count == catalog.stars.count)
    }

    @Test func distanceSpectralClassAndBrightnessCombine() {
        let filter = StarFilter(distance: 10...50, spectralClasses: [.a, .f], brightestAbsoluteMagnitude: 2)
        #expect(!filter.showsEverything)
        let shown = catalog.stars(matching: filter)
        #expect(!shown.isEmpty)
        for star in shown {
            #expect((10...50).contains(star.distanceLightYears))
            #expect([.a, .f].contains(star.spectralClass))
            #expect(star.absoluteMagnitude <= 2)
        }
        #expect(shown.contains { $0.name == "Vega" })
        #expect(!shown.contains { $0.name == "Sirius" }) // 8.6 ly
    }

    @Test(arguments: ["Rigil Kentaurus", "Toliman", "Proxima Centauri", "Sirius", "Procyon", "Castor"])
    func knownMultipleSystemsAreFound(name: String) throws {
        let star = try #require(catalog.star(named: name))
        #expect(catalog.isInMultipleSystem(star))
    }

    @Test(arguments: ["Vega", "Altair", "Arcturus", "Pollux", "52 Tau Cet"])
    func singleStarsAreNot(name: String) throws {
        let star = try #require(catalog.star(named: name))
        #expect(!catalog.isInMultipleSystem(star))
    }

    @Test func multiplicityFilterSplitsTheCatalog() {
        let multiple = catalog.stars(matching: StarFilter(multiplicity: .multiple))
        let single = catalog.stars(matching: StarFilter(multiplicity: .single))
        #expect(multiple.count > 500 && multiple.count < 2_000)
        #expect(multiple.allSatisfy { catalog.isInMultipleSystem($0) })
        #expect(single.allSatisfy { !catalog.isInMultipleSystem($0) })
        #expect(single.count + multiple.count == catalog.stars.count)
        #expect(!StarFilter(multiplicity: .single).showsEverything)
        #expect(catalog.stars(matching: StarFilter(multiplicity: .both)).count == catalog.stars.count)
    }

    /// The bucketed search finds the same pairs as comparing every pair.
    @Test func systemDetectionMatchesBruteForce() {
        var generator = SplitMix(seed: 7)
        var stars: [Star] = []
        for id in 0..<600 {
            let ra = Double.random(in: 0..<24, using: &generator)
            let dec = Double.random(in: -90...90, using: &generator)
            let distance = Double.random(in: 1...200, using: &generator)
            stars.append(Star(id: id, name: "S\(id)", apparentMagnitude: 5, absoluteMagnitude: 5,
                              rightAscensionHours: ra, declinationDegrees: dec, distanceLightYears: distance))
            // Give some stars a close companion.
            if id % 5 == 0 {
                stars.append(Star(id: 10_000 + id, name: "C\(id)", apparentMagnitude: 9, absoluteMagnitude: 9,
                                  rightAscensionHours: ra + 0.001, declinationDegrees: dec,
                                  distanceLightYears: distance * 1.01))
            }
        }
        let fast = StarCatalog.findMultipleSystems(in: stars)
        var brute = Set<Star.ID>()
        for i in stars.indices {
            for j in stars.indices where j > i {
                let (a, b) = (stars[i].distanceLightYears, stars[j].distanceLightYears)
                guard abs(a - b) <= max(0.5, 0.05 * max(a, b)) else { continue }
                let u = SIMD3<Double>(stars[i].position) / a, v = SIMD3<Double>(stars[j].position) / b
                if acos(min(max((u * v).sum(), -1), 1)) * min(a, b) <= StarCatalog.companionSeparation {
                    brute.insert(stars[i].id)
                    brute.insert(stars[j].id)
                }
            }
        }
        #expect(fast == brute)
        #expect(brute.count >= 100)
    }
}

@Suite struct StarSearchTests {
    let catalog: StarCatalog

    init() throws {
        catalog = try StarCatalog.bundled()
    }

    @Test func exactNameComesFirst() {
        #expect(catalog.search("sirius").first?.name == "Sirius")
        #expect(catalog.search("  VEGA ").first?.name == "Vega")
    }

    @Test func prefixesSuggestBrightStarsFirst() {
        let results = catalog.search("al", limit: 5)
        #expect(results.count == 5)
        #expect(results.contains { $0.name == "Altair" })
        // Real names before catalog numbers.
        #expect(results.allSatisfy { !$0.name.hasPrefix("HD") && !$0.name.hasPrefix("HIP") })
    }

    @Test func findsTheSunAliasesAndCatalogNumbers() throws {
        #expect(catalog.search("sol").first == .sun)
        #expect(catalog.search("su").contains(.sun))
        let rigil = try #require(catalog.star(named: "Rigil Kentaurus"))
        #expect(catalog.search("alpha cen").first?.starID == rigil.id)
        let hip = try #require(rigil.hipparcosID)
        #expect(catalog.search("HIP \(hip)").first?.starID == rigil.id)
    }

    @Test func wordPrefixesAndSubstringsMatch() {
        #expect(catalog.search("kentaurus").contains { $0.name == "Rigil Kentaurus" })
        #expect(catalog.search("tau cet").contains { $0.name == "52 Tau Cet" })
    }

    @Test func emptyAndUnknownQueriesFindNothing() {
        #expect(catalog.search("").isEmpty)
        #expect(catalog.search("   ").isEmpty)
        #expect(catalog.search("zzzzqqq").isEmpty)
    }

    @Test func resultsAreUniqueAndLimited() {
        let results = catalog.search("a", limit: 20)
        #expect(results.count == 20)
        #expect(Set(results).count == results.count)
    }
}

/// A small seeded generator, so the brute-force comparison is repeatable.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct SearchRankingTests {
    let catalog: StarCatalog

    init() throws {
        catalog = try StarCatalog.bundled()
    }

    @Test func aliasPrefixesDontOutrankBrighterNamePrefixes() throws {
        let names = catalog.search("al", limit: 5).map(\.name)
        #expect(names.contains("Altair"))
        #expect(!names.contains("Proxima Centauri"))
    }

    @Test func partialCatalogNumbersSuggestNamedStars() throws {
        let rigil = try #require(catalog.star(named: "Rigil Kentaurus"))
        let hip = try #require(rigil.hipparcosID)
        let partial = String(String(hip).dropLast())
        #expect(catalog.search("HIP \(partial)", limit: 20).contains { $0.starID == rigil.id })
    }

    @Test func compactCatalogNumbersWork() throws {
        let sirius = try #require(catalog.star(named: "Sirius"))
        let hip = try #require(sirius.hipparcosID)
        #expect(catalog.search("HIP\(hip)").first?.starID == sirius.id)
        #expect(catalog.location(named: "hip\(hip)")?.starID == sirius.id)
        if let hd = sirius.henryDraperID {
            #expect(catalog.search("HD\(hd)").first?.starID == sirius.id)
        }
    }

    @Test func multiwordQueriesMatchAtWordStarts() {
        // A word-start match beats a match inside a word.
        #expect(catalog.search("tau cet").first?.name == "52 Tau Cet")
    }
}

@Suite struct CompanionNotationTests {
    @Test(arguments: ["G8V + K4V", "M3.5Ve+M4Ve", "K0V+dM3", "A1V+DA"])
    func compositeSpectraListCompanions(type: String) {
        #expect(StarCatalog.listsCompanion(type))
    }

    @Test(arguments: ["DZ9+", "m+", "F8+...", "G2V", "M4+..."])
    func qualifiersDoNot(type: String) {
        #expect(!StarCatalog.listsCompanion(type))
    }

    @Test func starsWithUnusableCoordinatesDontCrash() {
        let stars = [
            Star(id: 0, name: "Bad", apparentMagnitude: 5, absoluteMagnitude: 5,
                 rightAscensionHours: .nan, declinationDegrees: 0, distanceLightYears: 50),
            Star(id: 1, name: "Worse", apparentMagnitude: 5, absoluteMagnitude: 5,
                 rightAscensionHours: 1, declinationDegrees: 0, distanceLightYears: .infinity),
            Star(id: 2, name: "Fine", apparentMagnitude: 5, absoluteMagnitude: 5,
                 rightAscensionHours: 1, declinationDegrees: 0, distanceLightYears: 50),
        ]
        #expect(StarCatalog(stars: stars).multipleSystemIDs.isEmpty)
    }
}
