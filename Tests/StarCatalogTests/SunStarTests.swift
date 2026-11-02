import Testing
@testable import StarCatalog

@Suite struct SunStarTests {
    @Test func sunHasCatalogLikeValuesAndReservedID() {
        let sun = Star.sun

        #expect(Star.sunID == Int.min)
        #expect(sun.id == Star.sunID)
        #expect(sun.name == "Sun")
        #expect(sun.spectralType == "G2V")
        #expect(sun.colorIndex == 0.65)
        #expect(sun.colorName == "Yellow")
        #expect(sun.apparentMagnitude == -26.74)
        #expect(sun.absoluteMagnitude == Astrophysics.solarAbsoluteMagnitude)
        #expect(sun.constellation.isEmpty)
        #expect(sun.hipparcosID == nil)
        #expect(sun.henryDraperID == nil)
        #expect(sun.rightAscensionHours == 0)
        #expect(sun.declinationDegrees == 0)
        #expect(sun.position == .zero)
        #expect(sun.distanceLightYears == 0)
        #expect(sun.isNakedEye)
        #expect(!sun.isCatalogDesignation)
        #expect(abs(sun.luminosity - 1) < 1e-9)
        #expect((5_700.0...5_850.0).contains(sun.temperature))
        #expect((0.9...1.1).contains(sun.estimatedRadius))
    }

    @Test func bundledCatalogDoesNotContainTheReservedSunID() throws {
        let catalog = try StarCatalog.bundled()

        #expect(catalog.star(withID: Star.sunID) == nil)
        #expect(!catalog.stars.contains { $0.id == Star.sunID })
    }
}
