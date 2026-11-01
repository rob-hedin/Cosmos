import Foundation
import Testing
@testable import StarCatalog

@Suite struct StarCatalogTests {
    static let header = "Name,HIP,HD,Constellation,Apparent mag,Absolute mag,Spectral type,B-V,Color,RA (h),RA (hms),Dec (deg),Dec (dms),Distance (ly),Naked eye (mag≤6)"

    @Test func bundledCatalogLoadsEveryStar() throws {
        let catalog = try StarCatalog.bundled()
        #expect(catalog.stars.count == 11_975)
        #expect(catalog.stars.allSatisfy { $0.distanceLightYears <= 200 })
    }

    @Test func siriusIsPlacedAndColored() throws {
        let sirius = try #require(try StarCatalog.bundled().star(named: "Sirius"))
        let p = SIMD3<Double>(sirius.position)
        #expect(abs((p * p).sum().squareRoot() - 8.6) < 0.01)
        #expect(sirius.position.z < 0) // southern sky
        #expect(sirius.luminosity > 20 && sirius.luminosity < 25)
        #expect(sirius.color.z >= sirius.color.x) // blue-white
        #expect(sirius.isNakedEye)
        #expect(!sirius.isCatalogDesignation)
    }

    @Test func vegaIsNorthern() throws {
        let vega = try #require(try StarCatalog.bundled().star(named: "Vega"))
        #expect(vega.position.z > 0)
    }

    @Test func proximaIsRedAndFaint() throws {
        let proxima = try #require(try StarCatalog.bundled().star(named: "Proxima Centauri"))
        #expect(proxima.color.x > proxima.color.z)
        #expect(proxima.luminosity < 0.001)
    }

    @Test func namesAreTidiedAndClassified() throws {
        let csv = """
        \(Self.header)
        61    Cyg,104214,201091,Cyg,5.2,7.49,K5V,1.069,Orange,21.11,x,38.75,x,11.4,Yes
        HD 1234,,1234,And,8.0,5.0,,,Unknown,1.0,x,10.0,x,100.0,
        """
        let catalog = try StarCatalog(csv: csv)
        #expect(catalog.stars.map(\.name) == ["61 Cyg", "HD 1234"])
        #expect(catalog.star(named: "61   cyg") != nil)
        #expect(!catalog.stars[0].isCatalogDesignation)
        #expect(catalog.stars[1].isCatalogDesignation)
        #expect(catalog.stars[1].hipparcosID == nil)
        #expect(catalog.stars[1].temperature == Astrophysics.fallbackTemperature)
    }

    @Test func packedBayerAndFlamsteedNamesAreSpacedOut() {
        #expect(Star.tidyName("20Gam Her") == "20 Gam Her")
        #expect(Star.tidyName("44Rho1Sgr") == "44 Rho1 Sgr")
        #expect(Star.tidyName("Kap1Lup") == "Kap1 Lup")
        #expect(Star.tidyName("14Mu  PsA") == "14 Mu PsA")
        #expect(Star.tidyName("3Pi 1UMa") == "3 Pi1 UMa")
        #expect(Star.tidyName("Gam Cen") == "Gam Cen")
        #expect(Star.tidyName("31 Vul") == "31 Vul")
        #expect(Star.tidyName("Kaus Australis") == "Kaus Australis")
        #expect(Star.tidyName("Alya B") == "Alya B")
        #expect(Star.tidyName("HD 126170") == "HD 126170")
    }

    @Test func packedNamesCanBeLookedUpEitherWay() throws {
        let catalog = try StarCatalog.bundled()
        let star = try #require(catalog.star(named: "20 Gam Her"))
        #expect(catalog.star(named: "20Gam Her") == star)
    }

    @Test func temperatureFallsBackToSpectralTypeThenColorName() throws {
        let csv = """
        \(Self.header)
        A,,,Ori,1,1,M2V,,Blue,1,x,1,x,10,
        B,,,Ori,1,1,,,Orange,1,x,1,x,10,
        """
        let stars = try StarCatalog(csv: csv).stars
        #expect(stars[0].temperature == 3_200)
        #expect(stars[1].temperature == 4_400)
    }

    @Test func missingColumnThrows() {
        #expect(throws: StarCatalogError.missingColumn("HIP")) {
            _ = try StarCatalog(csv: "Name\nSirius")
        }
    }

    @Test func badNumberThrows() {
        let csv = "\(Self.header)\nX,,,Ori,bright,1,,,Red,1,x,1,x,10,"
        #expect(throws: StarCatalogError.malformedRow(line: 2, column: "Apparent mag", value: "bright")) {
            _ = try StarCatalog(csv: csv)
        }
    }

    @Test(arguments: StarSizeMode.allCases)
    func sizesAreNormalized(mode: StarSizeMode) throws {
        let catalog = try StarCatalog.bundled()
        let sizes = catalog.normalizedSizes(for: mode)
        #expect(sizes.count == catalog.stars.count)
        #expect(sizes.min() == 0)
        #expect(sizes.max() == 1)
    }

    @Test func brighterStarsAreBiggerInLuminosityMode() throws {
        let catalog = try StarCatalog.bundled()
        let sizes = catalog.normalizedSizes(for: .luminosity)
        let sirius = try #require(catalog.star(named: "Sirius"))
        let proxima = try #require(catalog.star(named: "Proxima Centauri"))
        #expect(sizes[sirius.id] > sizes[proxima.id])
    }

    @Test func starsAreFoundByIDInFilteredCatalogs() throws {
        let full = try StarCatalog.bundled()
        let sirius = try #require(full.star(named: "Sirius"))
        let subset = StarCatalog(stars: full.stars.filter(\.isNakedEye).reversed())
        #expect(subset.stars.first?.id != 0)
        #expect(subset.star(withID: sirius.id) == sirius)
        #expect(subset.star(withID: -1) == nil)
        #expect(full.star(withID: sirius.id) == sirius)
    }
}
