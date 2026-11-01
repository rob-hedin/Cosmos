import Metal
import Testing
@testable import StarRenderer

@Suite struct LabelLayoutTests {
    let viewport = SIMD2<Float>(800, 600)
    let size = SIMD2<Float>(60, 16)

    private func candidate(_ id: Int, at anchor: SIMD2<Float>, priority: Float) -> LabelCandidate {
        LabelCandidate(id: id, anchor: anchor, radius: 4, size: size, priority: priority)
    }

    @Test func labelSitsRightOfItsStarAndCentered() throws {
        let placed = LabelLayout.place([candidate(1, at: SIMD2(100, 100), priority: 0)], in: viewport, maxCount: 10)
        let first = try #require(placed.first)
        #expect(first.origin.x > 100 + 4)
        #expect(abs(first.origin.y + size.y / 2 - 100) < 1e-4)
    }

    @Test func brighterLabelWinsAnOverlap() {
        let placed = LabelLayout.place([
            candidate(1, at: SIMD2(100, 100), priority: 3),
            candidate(2, at: SIMD2(110, 104), priority: 1),
        ], in: viewport, maxCount: 10)
        #expect(placed.map(\.id) == [2])
    }

    @Test func separateLabelsBothFit() {
        let placed = LabelLayout.place([
            candidate(1, at: SIMD2(100, 100), priority: 1),
            candidate(2, at: SIMD2(100, 200), priority: 2),
        ], in: viewport, maxCount: 10)
        #expect(placed.map(\.id) == [1, 2])
    }

    @Test func labelsMustFitInTheViewport() {
        let placed = LabelLayout.place([candidate(1, at: SIMD2(790, 300), priority: 0)], in: viewport, maxCount: 10)
        #expect(placed.isEmpty)
    }

    @Test func respectsMaxCountInPriorityOrder() {
        let candidates = (0..<10).map { candidate($0, at: SIMD2(50, Float(30 + $0 * 40)), priority: Float(10 - $0)) }
        let placed = LabelLayout.place(candidates, in: viewport, maxCount: 3)
        #expect(placed.map(\.id) == [9, 8, 7])
    }
}

@Suite struct LabelAtlasTests {
    @Test func packsEveryLabelInsideTheTexture() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let names = (0..<500).map { (id: $0, text: "Star number \($0)") }
        let atlas = try #require(LabelAtlas(device: device, labels: names))
        #expect(atlas.entries.count == 500)
        for entry in atlas.entries.values {
            let far = entry.uvOrigin + entry.uvSize
            #expect(entry.uvOrigin.x >= 0 && entry.uvOrigin.y >= 0)
            #expect(far.x <= 1 + 1e-6 && far.y <= 1 + 1e-6)
            #expect(entry.size.x > 0 && entry.size.y > 0)
        }
    }

    @Test func longerNamesGetWiderEntries() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let atlas = try #require(LabelAtlas(device: device, labels: [(id: 1, text: "Vega"), (id: 2, text: "Rigil Kentaurus")]))
        let short = try #require(atlas.entries[1])
        let long = try #require(atlas.entries[2])
        #expect(long.size.x > short.size.x)
        #expect(long.size.y == short.size.y)
    }
}
