import Testing
@testable import StarCatalog

@Suite struct StellarEstimateTests {
    @Test func solarMassEstimateIsNearOneSolarMass() throws {
        let mass = try #require(Astrophysics.estimatedMass(spectralType: "G2V"))
        #expect((0.9...1.15).contains(mass))
    }

    @Test func massDecreasesAcrossSpectralClassesAndSubclasses() throws {
        let types = ["O5V", "B5V", "A5V", "F5V", "G5V", "K5V", "M5V", "L5", "T5"]
        let masses = try types.map { type in
            try #require(Astrophysics.estimatedMass(spectralType: type))
        }
        #expect(zip(masses, masses.dropFirst()).allSatisfy { $0.0 > $0.1 })

        let subclassMasses = try ["M0V", "M5V", "M9V"].map { type in
            try #require(Astrophysics.estimatedMass(spectralType: type))
        }
        #expect(subclassMasses[0] > subclassMasses[1])
        #expect(subclassMasses[1] > subclassMasses[2])
    }

    @Test func massEstimatesHandleClassesPrefixesAndFractionalSubclasses() throws {
        let b0 = try #require(Astrophysics.estimatedMass(spectralType: "B0V"))
        let m5 = try #require(Astrophysics.estimatedMass(spectralType: "M5V"))
        let m4 = try #require(Astrophysics.estimatedMass(spectralType: "M4V"))
        let m45 = try #require(Astrophysics.estimatedMass(spectralType: "M4.5V"))
        let m5Again = try #require(Astrophysics.estimatedMass(spectralType: "M5V"))

        #expect((10...25).contains(b0))
        #expect((0.1...0.3).contains(m5))
        #expect(Astrophysics.estimatedMass(spectralType: "DA2") == 0.6)
        #expect(Astrophysics.estimatedMass(spectralType: "sdM4") == m4)
        #expect(Astrophysics.estimatedMass(spectralType: "dM4") == m4)
        #expect(m4 < m45 && m45 < m5Again)
        #expect(Astrophysics.estimatedMass(spectralType: "K") == Astrophysics.estimatedMass(spectralType: "K5"))
    }

    @Test(arguments: ["", "?"])
    func unrecognizedTypeHasNoMassOrRadius(type: String) {
        #expect(Astrophysics.estimatedMass(spectralType: type) == nil)
        #expect(Astrophysics.estimatedRadius(spectralType: type) == nil)
    }

    @Test func radiusEstimatesFollowSpectralType() throws {
        let g2 = try #require(Astrophysics.estimatedRadius(spectralType: "G2V"))
        let m5 = try #require(Astrophysics.estimatedRadius(spectralType: "M5V"))
        let b0 = try #require(Astrophysics.estimatedRadius(spectralType: "B0V"))

        #expect((0.9...1.15).contains(g2))
        #expect(Astrophysics.estimatedRadius(spectralType: "DA2") == 0.013)
        #expect(m5 < g2 && g2 < b0)
    }

    @Test(arguments: [(5_600.0, "G5"), (3_000.0, "M5")])
    func temperatureMassFallbackMatchesClassEstimate(temperature: Double, spectralType: String) throws {
        let expected = try #require(Astrophysics.estimatedMass(spectralType: spectralType))
        #expect(Astrophysics.estimatedMass(temperature: temperature) == expected)
    }

    @Test(arguments: [
        (1.0, 1.0, 365.25),
        (4.0, 1.0, 8 * 365.25),
        (1.0, 4.0, 365.25 / 2),
    ])
    func keplerPeriodUsesSemiMajorAxisAndTotalMass(axis: Double, mass: Double, expected: Double) {
        #expect(abs(Astrophysics.orbitalPeriod(semiMajorAxis: axis, totalMass: mass) - expected) < 1e-9)
    }

    @Test func publicUnitConstantsUsePlannedValues() {
        #expect(Astrophysics.earthMassesPerSolarMass == 332_946.0487)
        #expect(Astrophysics.daysPerYear == 365.25)
    }
}
