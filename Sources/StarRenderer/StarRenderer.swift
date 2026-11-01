import Foundation
import Metal
import MetalKit
import QuartzCore
import simd
import StarCatalog

public enum StarRendererError: Error {
    case noMetalDevice
    case shaderLibraryMissing
    case bufferAllocationFailed
}

/// Draws every star in one instanced call: a screen-aligned glowing quad per star,
/// blended additively so overlapping stars brighten instead of hiding each other.
@MainActor
public final class StarRenderer: NSObject {
    public let device: MTLDevice
    public let catalog: StarCatalog

    public var camera = OrbitCamera() {
        didSet { requestRedraw() }
    }

    public var sizeMode: StarSizeMode = .luminosity {
        didSet {
            guard sizeMode != oldValue else { return }
            try? rebuildInstances()
            requestRedraw()
        }
    }

    /// On-screen diameter range in points; scaled to pixels for the display.
    public var pointSizeRange: ClosedRange<Float> = 1.5...20 {
        didSet { requestRedraw() }
    }

    /// Curve applied to normalized sizes. Above 1, most stars stay small and only the largest grow.
    public var sizeExponent: Float = 4 {
        didSet { requestRedraw() }
    }

    /// Overall brightness of each star.
    public var exposure: Float = 0.8 {
        didSet { requestRedraw() }
    }

    /// Color saturation: 1 is the true blackbody color, higher makes tints easier to see.
    public var saturation: Float = 1.6 {
        didSet { requestRedraw() }
    }

    /// How quickly a fling slows down, per second. Higher stops sooner.
    public var spinDamping: Float = 3.5

    /// The star drawn with a highlight ring, by `Star.id`.
    public var selectedStarID: Star.ID? {
        didSet { requestRedraw() }
    }

    /// Diameter of the selection ring, in points.
    public var selectionRingDiameter: Float = 28 {
        didSet { requestRedraw() }
    }

    /// Draws star names. Named stars (not catalog numbers) are labeled when they would be
    /// brighter than `labelMagnitudeLimit` as seen from the camera; the selected star is always labeled.
    public var showsLabels = false {
        didSet { requestRedraw() }
    }

    /// Faintest apparent magnitude, seen from the camera, that gets a label. 6 is the naked-eye limit.
    public var labelMagnitudeLimit: Float = 6 {
        didSet { requestRedraw() }
    }

    /// Most labels shown at once; the brightest win.
    public var maxLabels = 80 {
        didSet { requestRedraw() }
    }

    /// Regions where labels must not go, in points from the view's top-left, such as an overlaid
    /// info card. The view's safe area (a title bar or notch) is avoided as well.
    public var labelExclusions: [LabelLayout.Rect] = [] {
        didSet { if labelExclusions != oldValue { requestRedraw() } }
    }

    /// Linear RGB of star names.
    public var labelColor: SIMD3<Float> = SIMD3(0.72, 0.77, 0.85) {
        didSet { requestRedraw() }
    }

    /// Linear RGB of the selection ring.
    public var selectionRingColor: SIMD3<Float> = SIMD3(0.25, 0.75, 1) {
        didSet { requestRedraw() }
    }

    public static let pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

    /// True while the view keeps turning after a fling.
    public var isSpinning: Bool {
        simd_length(spinVelocity) > 0.01
    }

    /// True while the camera is gliding to a new target.
    public var isFlying: Bool {
        flight != nil
    }

    /// Rotation that continues after a drag ends, in radians per second (screen convention).
    private var spinVelocity: SIMD2<Float> = .zero
    private var lastSpinTime: CFTimeInterval?

    private struct Flight {
        let fromTarget: SIMD3<Float>
        let toTarget: SIMD3<Float>
        let fromDistance: Float
        let toDistance: Float
        let start: CFTimeInterval
        let duration: CFTimeInterval
    }
    private var flight: Flight?

    /// Star positions in catalog order, for picking.
    private let positions: [SIMD3<Float>]
    /// Normalized sizes for the current size mode, in catalog order.
    private var normalizedSizes: [Float] = []
    /// Indices of stars with proper, Bayer or Flamsteed names.
    private let namedStarIndices: [Int]

    /// Names of every named star, built the first time labels are drawn.
    private lazy var labelAtlas: LabelAtlas? = LabelAtlas(
        device: device,
        labels: namedStarIndices.map { (id: catalog.stars[$0].id, text: catalog.stars[$0].name) }
    )
    /// The selected star's name, when it isn't in the atlas (catalog numbers).
    private var selectedLabelAtlas: (id: Star.ID, atlas: LabelAtlas)?
    /// Label instance buffers for when there are too many for setVertexBytes. A buffer goes back
    /// to the pool only when the GPU has finished the frame that used it.
    private let labelBufferPool = BufferPool()
    /// Per-frame label scratch storage, kept to avoid reallocating every frame.
    private var labelCandidates: [LabelCandidate] = []
    private var labelOpacity: [Int: Float] = [:]
    private var labelInstances: [LabelInstance] = []

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let ringPipeline: MTLRenderPipelineState
    private let labelPipeline: MTLRenderPipelineState
    private var instanceBuffer: MTLBuffer?
    private var instanceCount = 0
    private weak var view: MTKView?

    public init(catalog: StarCatalog, device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else {
            throw StarRendererError.noMetalDevice
        }
        self.device = device
        self.catalog = catalog
        positions = catalog.stars.map(\.position)
        // One entry per ID, first wins, matching StarCatalog.star(withID:) for catalogs with repeated IDs.
        var seenIDs = Set<Star.ID>()
        namedStarIndices = catalog.stars.indices.filter {
            !catalog.stars[$0].isCatalogDesignation && seenIDs.insert(catalog.stars[$0].id).inserted
        }
        commandQueue = queue

        guard let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertexFunction = library.makeFunction(name: "starVertex"),
              let starFragment = library.makeFunction(name: "starFragment"),
              let ringFragment = library.makeFunction(name: "ringFragment"),
              let labelVertex = library.makeFunction(name: "labelVertex"),
              let labelFragment = library.makeFunction(name: "labelFragment")
        else {
            throw StarRendererError.shaderLibraryMissing
        }

        func makePipeline(_ label: String, fragment: MTLFunction) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = label
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragment
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = Self.pixelFormat
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        pipeline = try makePipeline("Stars", fragment: starFragment)
        ringPipeline = try makePipeline("Selection ring", fragment: ringFragment)

        let labelDescriptor = MTLRenderPipelineDescriptor()
        labelDescriptor.label = "Labels"
        labelDescriptor.vertexFunction = labelVertex
        labelDescriptor.fragmentFunction = labelFragment
        let labelAttachment = labelDescriptor.colorAttachments[0]!
        labelAttachment.pixelFormat = Self.pixelFormat
        labelAttachment.isBlendingEnabled = true
        labelAttachment.sourceRGBBlendFactor = .one
        labelAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        labelAttachment.sourceAlphaBlendFactor = .one
        labelAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        labelPipeline = try device.makeRenderPipelineState(descriptor: labelDescriptor)

        super.init()
        try rebuildInstances()
    }

    /// Configures a view for on-demand drawing and makes this renderer its delegate.
    public func attach(to view: MTKView) {
        view.device = device
        view.colorPixelFormat = Self.pixelFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = self
        self.view = view
        requestRedraw()
    }

    public func requestRedraw() {
        // While spinning the view draws every frame on its own timer.
        guard view?.isPaused != false else { return }
        #if os(macOS)
        view?.needsDisplay = true
        #else
        view?.setNeedsDisplay()
        #endif
    }

    // MARK: Picking

    /// The star under a point in the view (points from the top-left, y down), within `tolerance` points.
    public func star(at point: CGPoint, viewSize: CGSize, tolerance: Float = 20) -> Star? {
        StarPicker.nearest(
            to: SIMD2(Float(point.x), Float(point.y)),
            in: positions,
            camera: camera,
            viewportSize: SIMD2(Float(viewSize.width), Float(viewSize.height)),
            maxDistance: tolerance
        ).map { catalog.stars[$0] }
    }

    // MARK: Motion

    /// Keeps rotating at `angularVelocity` (radians per second, screen convention) after a drag,
    /// slowing to a stop. The view draws continuously only while spinning.
    public func fling(angularVelocity: SIMD2<Float>) {
        spinVelocity = angularVelocity
        lastSpinTime = nil
        guard isSpinning else { return stopSpinning() }
        startTimedDrawing()
    }

    public func stopSpinning() {
        spinVelocity = .zero
        lastSpinTime = nil
        stopTimedDrawingIfIdle()
    }

    /// Glides the camera so it orbits `target` from `distance` light years, keeping its orientation.
    public func fly(to target: SIMD3<Float>, distance: Float, duration: CFTimeInterval = 0.8) {
        spinVelocity = .zero
        flight = Flight(
            fromTarget: camera.target,
            toTarget: target,
            fromDistance: camera.distance,
            toDistance: min(max(distance, OrbitCamera.distanceRange.lowerBound), OrbitCamera.distanceRange.upperBound),
            start: CACurrentMediaTime(),
            duration: max(duration, 0.01)
        )
        startTimedDrawing()
    }

    /// Stops any fling or flight where it is.
    public func stopMotion() {
        flight = nil
        stopSpinning()
    }

    /// Stops a flight where it is, leaving any fling running.
    public func cancelFlight() {
        flight = nil
        stopTimedDrawingIfIdle()
    }

    /// Timed drawing: both flags off, per MTKView's documented modes.
    private func startTimedDrawing() {
        view?.enableSetNeedsDisplay = false
        view?.isPaused = false
    }

    private func stopTimedDrawingIfIdle() {
        guard !isSpinning, flight == nil, let view, !view.isPaused else { return }
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        requestRedraw()
    }

    private func advanceFlight() {
        guard let flight else { return }
        let progress = Float(min((CACurrentMediaTime() - flight.start) / flight.duration, 1))
        let eased = progress * progress * (3 - 2 * progress)
        camera.target = simd_mix(flight.fromTarget, flight.toTarget, SIMD3(repeating: eased))
        // Interpolate distance in log space so zooming in feels even.
        camera.distance = exp(log(flight.fromDistance) + (log(flight.toDistance) - log(flight.fromDistance)) * eased)
        if progress >= 1 {
            self.flight = nil
            stopTimedDrawingIfIdle()
        }
    }

    private func advanceSpin() {
        guard isSpinning else { return }
        let now = CACurrentMediaTime()
        let elapsed = Float(min(now - (lastSpinTime ?? now - 1.0 / 60), 0.1))
        lastSpinTime = now
        camera.rotate(by: spinVelocity * elapsed)
        spinVelocity *= exp(-spinDamping * elapsed)
        if !isSpinning {
            stopSpinning()
        }
    }

    private func rebuildInstances() throws {
        let sizes = catalog.normalizedSizes(for: sizeMode)
        normalizedSizes = sizes
        var instances = zip(catalog.stars, sizes).map { star, size in
            StarInstance(
                positionSize: SIMD4(star.position, size),
                color: SIMD4(star.color, 1)
            )
        }
        // The Sun, at the origin, so there is always a reference point.
        instances.append(StarInstance(positionSize: SIMD4(0, 0, 0, 0.6), color: SIMD4(1, 0.93, 0.82, 1)))

        guard let buffer = device.makeBuffer(
            bytes: instances,
            length: MemoryLayout<StarInstance>.stride * instances.count,
            options: .storageModeShared
        ) else {
            throw StarRendererError.bufferAllocationFailed
        }
        buffer.label = "Star instances"
        instanceBuffer = buffer
        instanceCount = instances.count
    }

    private func render(in view: MTKView) {
        advanceFlight()
        advanceSpin()
        guard let instanceBuffer,
              let passDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }

        let drawableSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        let pointsWide = max(Float(view.bounds.width), 1)
        let pixelsPerPoint = drawableSize.x / pointsWide
        var uniforms = FrameUniforms(
            viewProjection: camera.viewProjection(aspectRatio: drawableSize.x / max(drawableSize.y, 1)),
            viewportSize: drawableSize,
            minPointSize: pointSizeRange.lowerBound * pixelsPerPoint,
            maxPointSize: pointSizeRange.upperBound * pixelsPerPoint,
            sizeExponent: sizeExponent,
            exposure: exposure,
            saturation: saturation
        )

        encoder.label = "Stars"
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instanceCount)

        if let selectedStarID, let selected = catalog.star(withID: selectedStarID) {
            var ring = StarInstance(
                positionSize: SIMD4(selected.position, 1),
                color: SIMD4(selectionRingColor, 1)
            )
            var ringUniforms = uniforms
            ringUniforms.minPointSize = selectionRingDiameter * pixelsPerPoint
            ringUniforms.maxPointSize = ringUniforms.minPointSize
            ringUniforms.exposure = 1
            ringUniforms.saturation = 1
            encoder.setRenderPipelineState(ringPipeline)
            encoder.setVertexBytes(&ring, length: MemoryLayout<StarInstance>.stride, index: 0)
            encoder.setVertexBytes(&ringUniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        if showsLabels {
            drawLabels(with: encoder, commandBuffer: commandBuffer, in: view, pixelsPerPoint: pixelsPerPoint)
        }
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: Labels

extension StarRenderer {
    /// Parsecs per light year, for apparent magnitude.
    private static let parsecsPerLightYear: Float = 1 / 3.261_56

    private func drawLabels(
        with encoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer, in view: MTKView, pixelsPerPoint: Float
    ) {
        guard let atlas = labelAtlas else { return }
        let viewport = SIMD2(Float(view.bounds.width), Float(view.bounds.height))
        guard viewport.x > 0, viewport.y > 0 else { return }
        let eye = camera.position
        let viewProjection = camera.viewProjection(aspectRatio: viewport.x / viewport.y)

        labelCandidates.removeAll(keepingCapacity: true)
        labelOpacity.removeAll(keepingCapacity: true)

        // The selected star always gets a label, even a catalog number.
        var selectedEntry: (entry: LabelAtlas.Entry, texture: MTLTexture)?
        if let id = selectedStarID, let star = catalog.star(withID: id),
           let anchor = camera.project(star.position, viewProjection: viewProjection, viewportSize: viewport) {
            if let entry = atlas.entries[id] {
                selectedEntry = (entry, atlas.texture)
            } else if let separate = labelAtlas(forSelected: star), let entry = separate.entries[id] {
                selectedEntry = (entry, separate.texture)
            }
            if let selectedEntry {
                labelCandidates.append(LabelCandidate(
                    id: id, anchor: anchor, radius: selectionRingDiameter / 2,
                    size: selectedEntry.entry.size, priority: -.infinity, isPinned: true
                ))
            }
        }

        for index in namedStarIndices {
            let star = catalog.stars[index]
            guard star.id != selectedStarID else { continue }
            // Cheap magnitude test first, so faint stars skip projection.
            let parsecs = max(simd_distance(star.position, eye), 0.001) * Self.parsecsPerLightYear
            let apparent = Float(star.absoluteMagnitude) + 5 * log10(parsecs) - 5
            guard apparent <= labelMagnitudeLimit, let entry = atlas.entries[star.id],
                  let anchor = camera.project(star.position, viewProjection: viewProjection, viewportSize: viewport)
            else { continue }
            labelCandidates.append(LabelCandidate(
                id: star.id, anchor: anchor, radius: drawnDiameter(ofStarAt: index) / 2,
                size: entry.size, priority: apparent
            ))
            // Fade labels that are close to the limit.
            labelOpacity[star.id] = min(max((labelMagnitudeLimit - apparent) / 2, 0.45), 1)
        }

        let insets = view.safeAreaInsets
        let placements = LabelLayout.place(
            labelCandidates,
            in: viewport,
            insets: SIMD4(Float(insets.top), Float(insets.left), Float(insets.bottom), Float(insets.right)),
            avoiding: labelExclusions,
            maxCount: maxLabels
        )
        labelInstances.removeAll(keepingCapacity: true)
        var separateLabel: (instance: LabelInstance, texture: MTLTexture)?
        for placement in placements {
            let isSelected = placement.id == selectedStarID
            guard let match = isSelected
                ? selectedEntry
                : atlas.entries[placement.id].map({ (entry: $0, texture: atlas.texture) })
            else { continue }
            let entry = match.entry
            let instance = LabelInstance(
                rect: SIMD4(lowHalf: placement.origin * pixelsPerPoint, highHalf: entry.size * pixelsPerPoint),
                uvRect: SIMD4(lowHalf: entry.uvOrigin, highHalf: entry.uvSize),
                color: isSelected ? SIMD4(selectionRingColor, 1) : SIMD4(labelColor, labelOpacity[placement.id] ?? 1)
            )
            if match.texture === atlas.texture {
                labelInstances.append(instance)
            } else {
                separateLabel = (instance, match.texture)
            }
        }

        var drawableSize = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        encoder.setRenderPipelineState(labelPipeline)
        encoder.setVertexBytes(&drawableSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        if !labelInstances.isEmpty, bindLabelInstances(to: encoder, commandBuffer: commandBuffer) {
            encoder.setFragmentTexture(atlas.texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: labelInstances.count)
        }
        if let separateLabel {
            var instance = separateLabel.instance
            encoder.setVertexBytes(&instance, length: MemoryLayout<LabelInstance>.stride, index: 0)
            encoder.setFragmentTexture(separateLabel.texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    /// Binds `labelInstances` at vertex index 0. setVertexBytes is limited to 4 KB, so larger sets go
    /// through a pooled buffer. Returns false, so the caller skips the draw, if a buffer can't be made.
    private func bindLabelInstances(to encoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer) -> Bool {
        let length = MemoryLayout<LabelInstance>.stride * labelInstances.count
        if length <= 4_096 {
            labelInstances.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: length, index: 0) }
            return true
        }
        let capacity = MemoryLayout<LabelInstance>.stride * max(maxLabels + 1, labelInstances.count)
        guard let buffer = labelBufferPool.take(minimumLength: length)
            ?? device.makeBuffer(length: capacity, options: .storageModeShared)
        else { return false }
        buffer.label = "Label instances"
        labelInstances.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: length) }
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        let pool = labelBufferPool
        let returned = BufferPool.Handoff(buffer: buffer)
        commandBuffer.addCompletedHandler { _ in pool.put(returned) }
        return true
    }

    /// A one-label atlas for a selected star whose name isn't in the main atlas, cached until the selection changes.
    private func labelAtlas(forSelected star: Star) -> LabelAtlas? {
        if let cached = selectedLabelAtlas, cached.id == star.id {
            return cached.atlas
        }
        guard let atlas = LabelAtlas(device: device, labels: [(id: star.id, text: star.name)], width: 1_024) else { return nil }
        selectedLabelAtlas = (star.id, atlas)
        return atlas
    }

    /// On-screen diameter of a star, in points, matching the vertex shader.
    private func drawnDiameter(ofStarAt index: Int) -> Float {
        let size = pow(normalizedSizes[index], sizeExponent)
        return pointSizeRange.lowerBound + (pointSizeRange.upperBound - pointSizeRange.lowerBound) * size
    }
}

extension StarRenderer: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        requestRedraw()
    }

    public func draw(in view: MTKView) {
        render(in: view)
    }
}

/// Reusable Metal buffers, safe to return from a command buffer's completion handler.
private final class BufferPool: @unchecked Sendable {
    /// Carries a buffer to the completion handler; the GPU is done with it by then, so nothing races.
    struct Handoff: @unchecked Sendable {
        let buffer: MTLBuffer
    }

    private let lock = NSLock()
    private var buffers: [MTLBuffer] = []

    func take(minimumLength: Int) -> MTLBuffer? {
        lock.withLock {
            guard let index = buffers.firstIndex(where: { $0.length >= minimumLength }) else { return nil }
            return buffers.remove(at: index)
        }
    }

    func put(_ handoff: Handoff) {
        lock.withLock {
            // A few frames in flight is the most we'll ever need at once.
            if buffers.count < 4 { buffers.append(handoff.buffer) }
        }
    }
}
