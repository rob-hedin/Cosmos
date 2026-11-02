import Foundation
import Metal
import MetalKit
import QuartzCore
import simd
import StarCatalog

/// Draws one Planetary System: the Central Star's glow, shaded spheres for the star and every Body,
/// faint rings for Belts, orbit lines, a selection ring and names.
///
/// The scene is a `PlanetarySceneState` (the layout, clock, camera, following and flights); this
/// class only draws it and keeps the view's drawing mode right. While the clock runs, a flight is
/// under way or the view is spinning, the view draws every frame; otherwise it draws on demand.
///
/// There is no depth buffer. Belts and orbit lines are a faint underlay that always sits beneath
/// every sphere, even where a line passes in front of one. Spheres are sorted by the distance from
/// the eye to their centers and drawn far to near, the same order `PlanetaryPicker` uses to decide
/// which one you clicked.
@MainActor
public final class PlanetarySystemRenderer: NSObject {
    public let device: MTLDevice

    /// The scene being drawn. Change it through the renderer's methods so the view redraws.
    public private(set) var state: PlanetarySceneState

    public var system: PlanetarySystem { state.system }

    /// The camera, relative to the scene's origin (the followed item, if any); see `PlanetarySceneState`.
    public var camera: OrbitCamera {
        get { state.camera }
        set {
            state.camera = newValue
            requestRedraw()
        }
    }

    /// Compressed or True scale. Changing it keeps a followed Body framed, or returns to the home view.
    public var scale: PlanetarySystemScale {
        get { state.scale }
        set {
            guard newValue != state.scale else { return }
            state.setScale(newValue)
            rebuildGeometry()
            updateDrawingMode()
            requestRedraw()
        }
    }

    /// Simulated time: pause and speed. Setting a clock that runs makes the view draw every frame.
    public var clock: SimulationClock {
        get { state.clock }
        set {
            state.clock = newValue
            updateDrawingMode()
            requestRedraw()
        }
    }

    /// The item drawn with a ring, a pinned name and a brighter orbit.
    public var selection: PlanetarySystemItem? {
        didSet { if selection != oldValue { requestRedraw() } }
    }

    /// Draws names. A crowded moon's name is left out until the moon is selected.
    public var showsLabels = true {
        didSet { requestRedraw() }
    }

    public var showsOrbits = true {
        didSet { requestRedraw() }
    }

    /// Regions where names must not go, such as an overlaid info card, in points from the top-left
    /// of the view's safe area (below a title bar), which is where SwiftUI lays out overlays.
    public var labelExclusions: [LabelLayout.Rect] = [] {
        didSet { if labelExclusions != oldValue { requestRedraw() } }
    }

    /// How quickly a fling slows down, per second. Higher stops sooner.
    public var spinDamping: Float = 3.5

    /// Linear RGB of names.
    public var labelColor: SIMD3<Float> = SIMD3(0.72, 0.77, 0.85) {
        didSet { requestRedraw() }
    }

    /// Linear RGB of the selection ring and the selected name.
    public var selectionColor: SIMD3<Float> = SIMD3(0.25, 0.75, 1) {
        didSet { requestRedraw() }
    }

    /// True while the view keeps turning after a fling.
    public var isSpinning: Bool {
        simd_length(spinVelocity) > 0.01
    }

    /// True while the clock runs, the camera is flying to an item, or the view is spinning.
    public var isAnimating: Bool {
        !state.clock.isPaused || state.isFlying || isSpinning
    }

    private var spinVelocity: SIMD2<Float> = .zero
    private var lastSpinTime: CFTimeInterval?
    private weak var view: MTKView?

    private let commandQueue: MTLCommandQueue
    private let pipelines: Pipelines
    private let labelAtlas: LabelAtlas?
    private let labelBufferPool = BufferPool()
    private var labelInstances: [LabelInstance] = []

    /// Per Body, in `system.bodies` order: its linear color.
    private let bodyColors: [SIMD3<Float>]
    private let starColor: SIMD3<Float>
    /// Where each item sits in a snapshot's entries.
    private let entryIndices: [PlanetarySystemItem: Int]
    /// Per Body: the index of its Parent's entry (0 is the star).
    private let parentEntryIndices: [Int]

    private struct BeltGeometry {
        let radii: ClosedRange<Double>
        let parentEntryIndex: Int
    }
    private var belts: [BeltGeometry] = []
    /// Closed line strips, one per Body, back to back, in scene units around the Body's Parent.
    private var orbitBuffer: MTLBuffer?
    private static let orbitSegments = 256

    /// Builds the renderer for `system`. Throws if there is no Metal device or the shaders can't be loaded.
    public init(
        system: PlanetarySystem,
        scale: PlanetarySystemScale = .compressed,
        clock: SimulationClock = SimulationClock(),
        device: MTLDevice? = MTLCreateSystemDefaultDevice()
    ) throws(StarRendererError) {
        guard let device, let queue = device.makeCommandQueue() else {
            throw StarRendererError.noMetalDevice
        }
        self.device = device
        commandQueue = queue
        pipelines = try Pipelines(device: device)
        state = PlanetarySceneState(system: system, scale: scale, clock: clock)

        bodyColors = system.bodies.map { Self.linear(fromSRGB: $0.displayColor) }
        starColor = Astrophysics.color(temperature: system.centralStar.temperature)
        var indices: [PlanetarySystemItem: Int] = [.centralStar: 0]
        for (index, body) in system.bodies.enumerated() {
            indices[.body(body.name)] = index + 1
        }
        entryIndices = indices
        parentEntryIndices = system.bodies.map { body in
            switch body.parent {
            case .centralStar: 0
            case .body(let name): indices[.body(name)] ?? 0
            }
        }
        labelAtlas = LabelAtlas(
            device: device,
            labels: [(id: 0, text: system.centralStar.name)]
                + system.bodies.enumerated().map { (id: $0.offset + 1, text: $0.element.name) }
        )

        super.init()
        rebuildGeometry()
    }

    /// Configures a view to be drawn by this renderer and makes it the view's delegate.
    public func attach(to view: MTKView) {
        view.device = device
        view.colorPixelFormat = StarRenderer.pixelFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.delegate = self
        self.view = view
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        updateDrawingMode()
        requestRedraw()
    }

    public func requestRedraw() {
        // While drawing on a timer the view redraws by itself.
        guard view?.isPaused != false else { return }
        #if os(macOS)
        view?.needsDisplay = true
        #else
        view?.setNeedsDisplay()
        #endif
    }

    // MARK: Picking and motion

    /// The item under a point in the view (points from the top-left, y down), within `tolerance`
    /// points of its drawn disc. The sphere drawn on top wins where discs overlap.
    public func item(at point: CGPoint, viewSize: CGSize, tolerance: Float = 20) -> PlanetarySystemItem? {
        state.item(
            at: SIMD2(Float(point.x), Float(point.y)),
            viewportSize: SIMD2(Float(viewSize.width), Float(viewSize.height)),
            tolerance: tolerance
        )
    }

    /// Glides to an item and then follows it as it moves.
    public func fly(to item: PlanetarySystemItem) {
        spinVelocity = .zero
        lastSpinTime = nil
        state.fly(to: item, at: CACurrentMediaTime())
        updateDrawingMode()
        requestRedraw()
    }

    /// Back to the home view, following nothing.
    public func resetView() {
        spinVelocity = .zero
        lastSpinTime = nil
        state.resetView()
        updateDrawingMode()
        requestRedraw()
    }

    /// Orbits around the target so the scene follows a drag; see `OrbitCamera.rotate(by:)`.
    public func rotate(by angles: SIMD2<Float>) {
        state.camera.rotate(by: angles)
        requestRedraw()
    }

    /// Multiplies the distance to the target. Cancels a flight, so zooming takes over from it.
    public func zoom(by factor: Float) {
        cancelFlight()
        state.camera.zoom(by: factor)
        requestRedraw()
    }

    /// Spins the view about its line of sight, in radians.
    public func roll(by angle: Float) {
        state.camera.roll(by: angle)
        requestRedraw()
    }

    /// Slides the view with a drag, and stops following.
    public func pan(byPoints points: SIMD2<Float>, viewportShortSide: Float) {
        state.pan(byPoints: points, viewportShortSide: viewportShortSide)
        updateDrawingMode()
        requestRedraw()
    }

    /// Keeps rotating at `angularVelocity` (radians per second, screen convention) after a drag,
    /// slowing to a stop.
    public func fling(angularVelocity: SIMD2<Float>) {
        spinVelocity = angularVelocity
        lastSpinTime = nil
        if !isSpinning { spinVelocity = .zero }
        updateDrawingMode()
        requestRedraw()
    }

    /// Stops a flight and a fling where they are.
    public func stopMotion() {
        spinVelocity = .zero
        lastSpinTime = nil
        state.cancelFlight()
        updateDrawingMode()
    }

    /// Stops a flight where it is, leaving any fling running. The item is not followed.
    public func cancelFlight() {
        state.cancelFlight()
        updateDrawingMode()
    }

    /// Timed drawing (both flags off, per MTKView's documented modes) while anything moves, else on demand.
    private func updateDrawingMode() {
        guard let view else { return }
        if isAnimating {
            if view.isPaused || view.enableSetNeedsDisplay {
                view.enableSetNeedsDisplay = false
                view.isPaused = false
            }
        } else if !view.isPaused {
            view.isPaused = true
            view.enableSetNeedsDisplay = true
        }
    }

    private func advanceSpin() {
        guard isSpinning else { return }
        let now = CACurrentMediaTime()
        let elapsed = Float(min(now - (lastSpinTime ?? now - 1.0 / 60), 0.1))
        lastSpinTime = now
        state.camera.rotate(by: spinVelocity * elapsed)
        spinVelocity *= exp(-spinDamping * elapsed)
        if !isSpinning {
            spinVelocity = .zero
            lastSpinTime = nil
        }
    }

    // MARK: Geometry

    /// Builds what depends on the scale: each Body's orbit path and each Belt's edges.
    private func rebuildGeometry() {
        let layout = state.layout
        var points: [SIMD4<Float>] = []
        points.reserveCapacity(system.bodies.count * (Self.orbitSegments + 1))
        for body in system.bodies {
            let path = layout.orbitPath(of: body, segments: Self.orbitSegments).map {
                SIMD4(Float($0.x), Float($0.y), Float($0.z), 1)
            }
            points += path
            // Close the loop.
            points.append(path.first ?? .zero)
        }
        orbitBuffer = points.isEmpty ? nil : device.makeBuffer(
            bytes: points, length: MemoryLayout<SIMD4<Float>>.stride * points.count, options: .storageModeShared
        )
        orbitBuffer?.label = "Orbits"

        belts = system.belts.map { belt in
            let parent: PlanetarySystemItem = switch belt.parent {
            case .centralStar: .centralStar
            case .body(let name): .body(name)
            }
            return BeltGeometry(radii: layout.beltRadii(of: belt), parentEntryIndex: entryIndices[parent] ?? 0)
        }
    }

    private static func linear(fromSRGB color: SIMD3<Float>) -> SIMD3<Float> {
        func channel(_ c: Float) -> Float {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return SIMD3(channel(color.x), channel(color.y), channel(color.z))
    }

    // MARK: Drawing

    private func render(in view: MTKView) {
        state.step(to: CACurrentMediaTime())
        advanceSpin()
        updateDrawingMode()

        let drawableSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        let viewport = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
        guard drawableSize.x > 0, drawableSize.y > 0, viewport.x > 0, viewport.y > 0,
              let passDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }
        encoder.label = "Planetary system"

        let camera = state.camera
        let snapshot = state.snapshot()
        let pixelsPerPoint = drawableSize.x / viewport.x
        let shortSide = min(viewport.x, viewport.y)
        let minimumRadius = state.minimumPointRadius
        var uniforms = FrameUniforms(
            viewProjection: camera.viewProjection(aspectRatio: drawableSize.x / drawableSize.y),
            viewportSize: drawableSize,
            minPointSize: 0, maxPointSize: 0, sizeExponent: 1, exposure: 1, saturation: 1
        )

        drawBelts(with: encoder, snapshot: snapshot, uniforms: &uniforms)
        if showsOrbits {
            drawOrbits(with: encoder, snapshot: snapshot, uniforms: &uniforms)
        }
        func pointRadius(of entry: PlanetarySceneSnapshot.Entry) -> Float {
            SphereProjection.pointRadius(
                radius: entry.radius, center: entry.position, camera: camera,
                viewportShortSide: shortSide, minimum: minimumRadius
            )
        }
        drawHalo(
            with: encoder, star: snapshot.entries[0], pointRadius: pointRadius(of: snapshot.entries[0]),
            pixelsPerPoint: pixelsPerPoint, uniforms: uniforms
        )
        drawSpheres(
            with: encoder, snapshot: snapshot, camera: camera, drawableSize: drawableSize,
            pixelsPerPoint: pixelsPerPoint, shortSide: shortSide, minimumRadius: minimumRadius, uniforms: uniforms
        )
        if let selection, let index = entryIndices[selection], snapshot.entries.indices.contains(index) {
            let entry = snapshot.entries[index]
            drawRing(
                with: encoder, at: entry.position, diameter: 2 * (pointRadius(of: entry) + Self.selectionRingMargin),
                uniforms: uniforms, pixelsPerPoint: pixelsPerPoint
            )
        }
        if showsLabels {
            drawLabels(
                with: encoder, commandBuffer: commandBuffer, snapshot: snapshot, in: view,
                viewport: viewport, pixelsPerPoint: pixelsPerPoint
            )
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// The gap between a selected sphere's edge and its ring, in points.
    private static let selectionRingMargin: Float = 6

    private func drawBelts(
        with encoder: MTLRenderCommandEncoder, snapshot: PlanetarySceneSnapshot, uniforms: inout FrameUniforms
    ) {
        guard !belts.isEmpty else { return }
        let instances = belts.map { belt in
            let width = belt.radii.upperBound - belt.radii.lowerBound
            return BeltInstance(
                centerOuter: SIMD4(snapshot.entries[belt.parentEntryIndex].position, Float(belt.radii.upperBound)),
                innerFade: SIMD4(Float(belt.radii.lowerBound), Float(width * 0.08), 0, 0),
                color: SIMD4(0.55, 0.5, 0.42, 0.12)
            )
        }
        encoder.setRenderPipelineState(pipelines.belt)
        instances.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress { encoder.setVertexBytes(base, length: bytes.count, index: 0) }
        }
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances.count)
    }

    private func drawOrbits(
        with encoder: MTLRenderCommandEncoder, snapshot: PlanetarySceneSnapshot, uniforms: inout FrameUniforms
    ) {
        guard let orbitBuffer else { return }
        encoder.setRenderPipelineState(pipelines.orbit)
        encoder.setVertexBuffer(orbitBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        let perOrbit = Self.orbitSegments + 1
        for (index, body) in system.bodies.enumerated() {
            let isSelected = selection == .body(body.name)
            var offset = SIMD4(snapshot.entries[parentEntryIndices[index]].position, 0)
            let base = bodyColors[index]
            var color = SIMD4(isSelected ? simd_min(base + SIMD3(repeating: 0.2), SIMD3(repeating: 1)) : base * 0.35, 1)
            encoder.setVertexBytes(&offset, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
            encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.drawPrimitives(type: .lineStrip, vertexStart: index * perOrbit, vertexCount: perOrbit)
        }
    }

    /// The star's soft glow, under all the spheres.
    private func drawHalo(
        with encoder: MTLRenderCommandEncoder, star: PlanetarySceneSnapshot.Entry, pointRadius: Float,
        pixelsPerPoint: Float, uniforms: FrameUniforms
    ) {
        var halo = StarInstance(positionSize: SIMD4(star.position, 1), color: SIMD4(starColor, 1))
        var haloUniforms = uniforms
        haloUniforms.minPointSize = max(pointRadius * 2 * Self.haloScale, Self.minimumHaloDiameter) * pixelsPerPoint
        haloUniforms.maxPointSize = haloUniforms.minPointSize
        haloUniforms.exposure = 0.9
        encoder.setRenderPipelineState(pipelines.halo)
        encoder.setVertexBytes(&halo, length: MemoryLayout<StarInstance>.stride, index: 0)
        encoder.setVertexBytes(&haloUniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// How many times the star's disc the glow spans, and its least size in points.
    private static let haloScale: Float = 5
    private static let minimumHaloDiameter: Float = 36

    /// All the spheres as camera-facing impostors, far to near with premultiplied "over" blending.
    private func drawSpheres(
        with encoder: MTLRenderCommandEncoder, snapshot: PlanetarySceneSnapshot, camera: OrbitCamera,
        drawableSize: SIMD2<Float>, pixelsPerPoint: Float, shortSide: Float, minimumRadius: Float,
        uniforms: FrameUniforms
    ) {
        let eye = camera.position
        let order = snapshot.entries.indices
            .map { (index: $0, depth: simd_distance(eye, snapshot.entries[$0].position)) }
            .sorted { ($1.depth, $0.index) < ($0.depth, $1.index) }
        let instances = order.map { entry -> SphereInstance in
            let item = snapshot.entries[entry.index]
            let color = entry.index == 0 ? SIMD4(starColor, 1) : SIMD4(bodyColors[entry.index - 1], 0)
            return SphereInstance(positionRadius: SIMD4(item.position, item.radius), color: color)
        }
        var sphereUniforms = SphereUniforms(
            viewProjection: uniforms.viewProjection,
            viewportSize: drawableSize,
            pixelsPerPoint: pixelsPerPoint,
            minimumPointRadius: minimumRadius,
            eyePosition: SIMD4(eye, 0),
            cameraRight: SIMD4(camera.right, 0),
            cameraUp: SIMD4(camera.up, 0),
            lightPosition: SIMD4(snapshot.entries[0].position, 0),
            shortSidePoints: shortSide,
            tanHalfFieldOfView: tan(camera.fieldOfView / 2)
        )
        encoder.setRenderPipelineState(pipelines.sphere)
        instances.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress { encoder.setVertexBytes(base, length: bytes.count, index: 0) }
        }
        encoder.setVertexBytes(&sphereUniforms, length: MemoryLayout<SphereUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances.count)
    }

    /// A ring `diameter` points across around `position`.
    private func drawRing(
        with encoder: MTLRenderCommandEncoder, at position: SIMD3<Float>, diameter: Float,
        uniforms: FrameUniforms, pixelsPerPoint: Float
    ) {
        var ring = StarInstance(positionSize: SIMD4(position, 1), color: SIMD4(selectionColor, 1))
        var ringUniforms = uniforms
        ringUniforms.minPointSize = diameter * pixelsPerPoint
        ringUniforms.maxPointSize = ringUniforms.minPointSize
        encoder.setRenderPipelineState(pipelines.ring)
        encoder.setVertexBytes(&ring, length: MemoryLayout<StarInstance>.stride, index: 0)
        encoder.setVertexBytes(&ringUniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    private func drawLabels(
        with encoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer, snapshot: PlanetarySceneSnapshot,
        in view: MTKView, viewport: SIMD2<Float>, pixelsPerPoint: Float
    ) {
        guard let labelAtlas else { return }
        let sizes = snapshot.entries.indices.map { labelAtlas.entries[$0]?.size ?? .zero }
        let candidates = PlanetaryLabels.candidates(
            for: snapshot, in: system, camera: state.camera, viewportSize: viewport, labelSizes: sizes,
            minimumPointRadius: state.minimumPointRadius, selection: selection
        ).filter { labelAtlas.entries[$0.id] != nil }
        guard !candidates.isEmpty else { return }

        let insets = view.safeAreaInsets
        let placements = LabelLayout.place(
            candidates,
            in: viewport,
            insets: SIMD4(Float(insets.top), Float(insets.left), Float(insets.bottom), Float(insets.right)),
            avoiding: labelExclusions.map {
                // The view itself extends under the title bar; shift into its coordinates.
                LabelLayout.Rect(origin: $0.origin + SIMD2(Float(insets.left), Float(insets.top)), size: $0.size)
            },
            maxCount: snapshot.entries.count
        )
        let selectedIndex = selection.flatMap { entryIndices[$0] }
        labelInstances.removeAll(keepingCapacity: true)
        for placement in placements {
            guard let entry = labelAtlas.entries[placement.id] else { continue }
            let color = placement.id == selectedIndex ? selectionColor : labelColor
            labelInstances.append(LabelInstance(
                rect: SIMD4(lowHalf: placement.origin * pixelsPerPoint, highHalf: entry.size * pixelsPerPoint),
                uvRect: SIMD4(lowHalf: entry.uvOrigin, highHalf: entry.uvSize),
                color: SIMD4(color, 1)
            ))
        }
        guard !labelInstances.isEmpty else { return }

        var drawableSize = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        encoder.setRenderPipelineState(pipelines.label)
        encoder.setVertexBytes(&drawableSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        if bindLabelInstances(to: encoder, commandBuffer: commandBuffer) {
            encoder.setFragmentTexture(labelAtlas.texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: labelInstances.count)
        }
    }

    /// Binds `labelInstances` at vertex index 0. setVertexBytes is limited to 4 KB, so larger sets go
    /// through a pooled buffer. Returns false, so the caller skips the draw, if a buffer can't be made.
    private func bindLabelInstances(to encoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer) -> Bool {
        let length = MemoryLayout<LabelInstance>.stride * labelInstances.count
        if length <= 4_096 {
            labelInstances.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress { encoder.setVertexBytes(base, length: length, index: 0) }
            }
            return true
        }
        guard let buffer = labelBufferPool.take(minimumLength: length)
            ?? device.makeBuffer(length: length * 2, options: .storageModeShared)
        else { return false }
        buffer.label = "Label instances"
        labelInstances.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress { buffer.contents().copyMemory(from: base, byteCount: length) }
        }
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        let pool = labelBufferPool
        let returned = BufferPool.Handoff(buffer: buffer)
        commandBuffer.addCompletedHandler { _ in pool.put(returned) }
        return true
    }
}

extension PlanetarySystemRenderer: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        requestRedraw()
    }

    public func draw(in view: MTKView) {
        render(in: view)
    }
}

/// The render pipelines, built once from the shader library.
@MainActor
private struct Pipelines {
    /// Additive glow (the star's halo), reusing the star shaders.
    let halo: MTLRenderPipelineState
    /// The selection ring.
    let ring: MTLRenderPipelineState
    /// Orbit lines, moved to their Parent's position by a per-draw offset.
    let orbit: MTLRenderPipelineState
    let belt: MTLRenderPipelineState
    let sphere: MTLRenderPipelineState
    let label: MTLRenderPipelineState

    init(device: MTLDevice) throws(StarRendererError) {
        guard let library = try? device.makeDefaultLibrary(bundle: .module),
              let starVertex = library.makeFunction(name: "starVertex"),
              let starFragment = library.makeFunction(name: "starFragment"),
              let ringFragment = library.makeFunction(name: "ringFragment"),
              let lineFragment = library.makeFunction(name: "lineFragment"),
              let offsetLineVertex = library.makeFunction(name: "offsetLineVertex"),
              let beltVertex = library.makeFunction(name: "beltVertex"),
              let beltFragment = library.makeFunction(name: "beltFragment"),
              let sphereVertex = library.makeFunction(name: "sphereVertex"),
              let sphereFragment = library.makeFunction(name: "sphereFragment"),
              let labelVertex = library.makeFunction(name: "labelVertex"),
              let labelFragment = library.makeFunction(name: "labelFragment")
        else {
            throw .shaderLibraryMissing
        }

        func makePipeline(
            _ label: String, vertex: MTLFunction, fragment: MTLFunction, premultiplied: Bool
        ) throws(StarRendererError) -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = label
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            guard let attachment = descriptor.colorAttachments[0] else { throw .shaderLibraryMissing }
            attachment.pixelFormat = StarRenderer.pixelFormat
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            // Additive light, or premultiplied "over" for spheres and names.
            attachment.destinationRGBBlendFactor = premultiplied ? .oneMinusSourceAlpha : .one
            attachment.destinationAlphaBlendFactor = premultiplied ? .oneMinusSourceAlpha : .one
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                throw .shaderLibraryMissing
            }
        }
        halo = try makePipeline("Star glow", vertex: starVertex, fragment: starFragment, premultiplied: false)
        ring = try makePipeline("Selection ring", vertex: starVertex, fragment: ringFragment, premultiplied: false)
        orbit = try makePipeline("Orbits", vertex: offsetLineVertex, fragment: lineFragment, premultiplied: false)
        belt = try makePipeline("Belts", vertex: beltVertex, fragment: beltFragment, premultiplied: false)
        sphere = try makePipeline("Spheres", vertex: sphereVertex, fragment: sphereFragment, premultiplied: true)
        label = try makePipeline("Names", vertex: labelVertex, fragment: labelFragment, premultiplied: true)
    }
}
