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

    @Test func pinnedLabelFlipsLeftAtTheRightEdge() throws {
        var pinned = candidate(1, at: SIMD2(790, 300), priority: 99)
        pinned.isPinned = true
        let placed = LabelLayout.place([pinned], in: viewport, maxCount: 10)
        let origin = try #require(placed.first).origin
        #expect(origin.x + size.x <= 790 - 4)
        #expect(origin.y == 292)
    }

    @Test func pinnedLabelIsClampedIntoTheViewport() throws {
        var pinned = candidate(1, at: SIMD2(30, 2), priority: 0)
        pinned.size = SIMD2(780, 16)
        pinned.isPinned = true
        let origin = try #require(LabelLayout.place([pinned], in: viewport, maxCount: 10).first).origin
        #expect(origin.x >= 0 && origin.x + 780 <= viewport.x)
        #expect(origin.y == 0)
    }

    @Test(arguments: [Float(2), 598])
    func pinnedLabelFlipsLeftInTheRightCorners(y: Float) throws {
        var pinned = candidate(1, at: SIMD2(790, y), priority: 0)
        pinned.isPinned = true
        let origin = try #require(LabelLayout.place([pinned], in: viewport, maxCount: 10).first).origin
        #expect(origin.x == 723)
        #expect(origin.y >= 0 && origin.y + size.y <= viewport.y)
    }

    @Test func labelsStayOutOfInsetsAndObstacles() {
        let card = LabelLayout.Rect(origin: SIMD2(0, 400), size: SIMD2(300, 200))
        let placed = LabelLayout.place([
            candidate(1, at: SIMD2(100, 20), priority: 0),   // under a 28 pt title bar
            candidate(2, at: SIMD2(100, 450), priority: 1),  // on the card
            candidate(3, at: SIMD2(100, 200), priority: 2),  // clear
        ], in: viewport, insets: SIMD4(28, 0, 0, 0), avoiding: [card], maxCount: 10)
        #expect(placed.map(\.id) == [3])
    }

    @Test func pinnedLabelMovesClearOfAnObstacle() throws {
        // The star sits just above the card's top edge, so the side positions overlap the card.
        let card = LabelLayout.Rect(origin: SIMD2(0, 400), size: SIMD2(300, 200))
        var pinned = candidate(1, at: SIMD2(100, 402), priority: 0)
        pinned.isPinned = true
        let origin = try #require(LabelLayout.place([pinned], in: viewport, avoiding: [card], maxCount: 10).first).origin
        #expect(origin.y + size.y <= 400 - 2)
    }

    @Test func pinnedLabelUnderAnObstacleMovesOutside() throws {
        let card = LabelLayout.Rect(origin: SIMD2(0, 400), size: SIMD2(300, 200))
        var pinned = candidate(1, at: SIMD2(150, 560), priority: 0)
        pinned.isPinned = true
        let origin = try #require(LabelLayout.place([pinned], in: viewport, avoiding: [card], maxCount: 10).first).origin
        // Just right of the card, level with the star.
        #expect(origin == SIMD2(303, 552))
    }

    @Test func pinnedLabelGoesFirstAndBlocksOthers() {
        var pinned = candidate(1, at: SIMD2(100, 100), priority: 50)
        pinned.isPinned = true
        let placed = LabelLayout.place([candidate(2, at: SIMD2(102, 102), priority: 0), pinned], in: viewport, maxCount: 10)
        #expect(placed.map(\.id) == [1])
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
