import CoreGraphics
import CoreText
import Foundation
import Metal

/// Text labels rasterized once with Core Text into a single-channel texture, packed in rows.
final class LabelAtlas {
    struct Entry {
        /// Top-left and size in texture coordinates (0...1, y down).
        let uvOrigin: SIMD2<Float>
        let uvSize: SIMD2<Float>
        /// Size on screen, in points, including padding.
        let size: SIMD2<Float>
    }

    let texture: MTLTexture
    let entries: [Int: Entry]

    /// Rasterized at 2x so labels stay crisp on Retina displays.
    static let pixelsPerPoint: CGFloat = 2
    /// Clear space around each label, in points.
    static let padding: CGFloat = 1.5

    /// Returns nil if Metal or Core Graphics can't allocate the atlas.
    init?(device: MTLDevice, labels: [(id: Int, text: String)], fontSize: CGFloat = 11, width: Int = 2_048) {
        let scale = Self.pixelsPerPoint
        let font = CTFontCreateUIFontForLanguage(.label, fontSize * scale, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize * scale, nil)
        let ascent = CTFontGetAscent(font)
        let pad = Self.padding * scale
        let rowHeight = Int(ceil(ascent + CTFontGetDescent(font) + 2 * pad))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]

        // Measure and pack into rows.
        var placements: [(id: Int, line: CTLine, x: Int, y: Int, width: Int)] = []
        var x = 0
        var y = 0
        var seenIDs = Set<Int>()
        for label in labels {
            // Repeated IDs keep the first label, as StarCatalog.star(withID:) keeps the first star.
            guard seenIDs.insert(label.id).inserted else { continue }
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: label.text, attributes: attributes))
            let labelWidth = Int(ceil(CTLineGetTypographicBounds(line, nil, nil, nil) + 2 * pad))
            guard labelWidth <= width else { continue }
            if x + labelWidth > width {
                x = 0
                y += rowHeight
            }
            placements.append((label.id, line, x, y, labelWidth))
            x += labelWidth
        }
        let height = y + rowHeight
        guard height <= 16_384,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return nil }

        // White text on black: the red channel of the texture is the label's coverage.
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 1, alpha: 1)
        context.setShouldAntialias(true)

        var entries: [Int: Entry] = [:]
        let atlasSize = SIMD2(Float(width), Float(height))
        for placement in placements {
            // Core Graphics draws y-up; the bitmap's first row is the top, matching texture coordinates.
            context.textPosition = CGPoint(x: CGFloat(placement.x) + pad, y: CGFloat(height - placement.y) - pad - ascent)
            CTLineDraw(placement.line, context)
            let pixelSize = SIMD2(Float(placement.width), Float(rowHeight))
            entries[placement.id] = Entry(
                uvOrigin: SIMD2(Float(placement.x), Float(placement.y)) / atlasSize,
                uvSize: pixelSize / atlasSize,
                size: pixelSize / Float(scale)
            )
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let data = context.data, let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Star names"
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: context.bytesPerRow
        )
        self.texture = texture
        self.entries = entries
    }
}
