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

    public static let pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

    /// True while the view keeps turning after a fling.
    public var isSpinning: Bool {
        simd_length(spinVelocity) > 0.01
    }

    /// Rotation that continues after a drag ends, in radians per second (screen convention).
    private var spinVelocity: SIMD2<Float> = .zero
    private var lastSpinTime: CFTimeInterval?

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var instanceBuffer: MTLBuffer?
    private var instanceCount = 0
    private weak var view: MTKView?

    public init(catalog: StarCatalog, device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else {
            throw StarRendererError.noMetalDevice
        }
        self.device = device
        self.catalog = catalog
        commandQueue = queue

        guard let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertexFunction = library.makeFunction(name: "starVertex"),
              let fragmentFunction = library.makeFunction(name: "starFragment")
        else {
            throw StarRendererError.shaderLibraryMissing
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Stars"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = Self.pixelFormat
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .one
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

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

    /// Keeps rotating at `angularVelocity` (radians per second, screen convention) after a drag,
    /// slowing to a stop. The view draws continuously only while spinning.
    public func fling(angularVelocity: SIMD2<Float>) {
        spinVelocity = angularVelocity
        lastSpinTime = nil
        guard isSpinning else { return stopSpinning() }
        // Timed drawing: both flags off, per MTKView's documented modes.
        view?.enableSetNeedsDisplay = false
        view?.isPaused = false
    }

    public func stopSpinning() {
        spinVelocity = .zero
        lastSpinTime = nil
        guard let view, !view.isPaused else { return }
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        requestRedraw()
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
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
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
