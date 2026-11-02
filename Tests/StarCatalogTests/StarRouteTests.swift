import Foundation
import Testing
@testable import StarCatalog

@Suite struct StarRouteTests {
    let catalog: StarCatalog

    init() throws {
        catalog = try StarCatalog.bundled()
    }

    @Test(arguments: ["Sun", "sol", " SOL "])
    func sunIsFoundByEitherName(name: String) throws {
        #expect(try #require(catalog.location(named: name)) == .sun)
    }

    @Test func aliasesAndCatalogNumbersResolve() throws {
        let rigil = try #require(catalog.star(named: "Rigil Kentaurus"))
        #expect(catalog.location(named: "Alpha Centauri")?.starID == rigil.id)
        #expect(catalog.location(named: "alpha centauri a")?.starID == rigil.id)
        #expect(catalog.location(named: "Alpha Centauri B")?.starID == catalog.star(named: "Toliman")?.id)
        let hip = try #require(rigil.hipparcosID)
        #expect(catalog.location(named: "HIP \(hip)")?.starID == rigil.id)
        if let hd = rigil.henryDraperID {
            #expect(catalog.location(named: "hd \(hd)")?.starID == rigil.id)
        }
        #expect(catalog.location(named: "Barnards Star") != nil)
    }

    @Test func unknownNamesAreReportedAndSkipped() {
        let route = StarRoute(["Sun", "Nowhere Prime", "Sirius", ""], in: catalog)
        #expect(route.stops.map(\.name) == ["Sun", "Sirius"])
        #expect(route.unresolved == ["Nowhere Prime"])
        #expect(route.legs.count == 1)
    }

    @Test func legDistancesMatchCatalogDistancesFromTheSun() throws {
        let route = StarRoute(["Sol", "Alpha Centauri", "Sirius"], in: catalog)
        let legs = route.legs
        try #require(legs.count == 2)
        let rigil = try #require(catalog.star(named: "Rigil Kentaurus"))
        #expect(abs(legs[0].distance - rigil.distanceLightYears) < 0.01)
        #expect(legs[0].from == .sun)
        // Sirius is 8.6 ly out and Alpha Centauri 4.4 ly, far apart in the sky, so the leg is long.
        #expect(legs[1].distance > 8 && legs[1].distance < 13)
        #expect(abs(route.totalDistance - legs[0].distance - legs[1].distance) < 1e-9)
    }

    @Test func reachIsTheFarthestStopFromTheFirst() throws {
        let route = StarRoute(["Sirius", "Sun", "Vega"], in: catalog)
        let sirius = try #require(route.stops.first)
        let vega = try #require(route.stops.last)
        #expect(abs(route.reachFromFirstStop - max(sirius.distance(to: .sun), sirius.distance(to: vega))) < 1e-9)
        #expect(StarRoute([], in: catalog).reachFromFirstStop == 0)
    }
}
