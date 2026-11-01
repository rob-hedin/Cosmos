import MetalKit
import StarRenderer

#if os(macOS)
import AppKit

/// An MTKView that turns mouse and trackpad input into camera moves.
///
/// | Action | Input |
/// | --- | --- |
/// | Rotate | Drag (keeps spinning briefly if released while moving) |
/// | Zoom | Scroll wheel, trackpad scroll or pinch |
/// | Pan | Shift-drag, right-drag or middle-drag |
/// | Roll | Trackpad rotate |
/// | Reset | Double-click |
final class InteractiveStarView: MTKView {
    /// Rotation per point dragged, in radians.
    var radiansPerPoint: Float = 0.006

    /// Recent rotation drags, for estimating release speed. Cleared on press and when panning.
    private var rotationSamples: [(delta: SIMD2<Float>, time: TimeInterval, interval: TimeInterval)] = []
    private var lastEventTime: TimeInterval = 0

    /// How far back release speed is averaged, in seconds.
    private let velocityWindow: TimeInterval = 0.08

    private var renderer: StarRenderer? {
        delegate as? StarRenderer
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Rotate and pan

    override func mouseDown(with event: NSEvent) {
        beginDrag(at: event)
        if event.clickCount == 2 {
            renderer?.camera.reset()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = SIMD2(Float(event.deltaX), Float(event.deltaY))
        let interval = event.timestamp - lastEventTime
        lastEventTime = event.timestamp
        if event.modifierFlags.contains(.shift) {
            rotationSamples.removeAll()
            pan(by: delta)
        } else {
            renderer?.camera.rotate(by: delta * radiansPerPoint)
            rotationSamples.append((delta, event.timestamp, interval))
            rotationSamples.removeAll { event.timestamp - $0.time > velocityWindow }
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { rotationSamples.removeAll() }
        // Fling only if the last move was a rotation and the pointer was still moving when released.
        guard let last = rotationSamples.last, event.timestamp - last.time < 0.05 else { return }
        let distance = rotationSamples.reduce(SIMD2<Float>.zero) { $0 + $1.delta }
        let duration = max(rotationSamples.reduce(0.0) { $0 + $1.interval }, 1.0 / 240)
        renderer?.fling(angularVelocity: distance / Float(duration) * radiansPerPoint)
    }

    override func rightMouseDown(with event: NSEvent) {
        beginDrag(at: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        beginDrag(at: event)
    }

    private func beginDrag(at event: NSEvent) {
        renderer?.stopSpinning()
        rotationSamples.removeAll()
        lastEventTime = event.timestamp
    }

    override func rightMouseDragged(with event: NSEvent) {
        pan(by: SIMD2(Float(event.deltaX), Float(event.deltaY)))
    }

    override func otherMouseDragged(with event: NSEvent) {
        pan(by: SIMD2(Float(event.deltaX), Float(event.deltaY)))
    }

    private func pan(by points: SIMD2<Float>) {
        let shortSide = Float(min(bounds.width, bounds.height))
        renderer?.camera.pan(byPoints: points, viewportShortSide: shortSide)
    }

    // MARK: Zoom and roll

    override func scrollWheel(with event: NSEvent) {
        // Trackpads report fine-grained point deltas; mouse wheels report coarse lines.
        let perUnit: Float = event.hasPreciseScrollingDeltas ? 0.005 : 0.08
        renderer?.camera.zoom(by: exp(-Float(event.scrollingDeltaY) * perUnit))
    }

    override func magnify(with event: NSEvent) {
        renderer?.camera.zoom(by: 1 / max(1 + Float(event.magnification), 0.1))
    }

    override func rotate(with event: NSEvent) {
        renderer?.camera.roll(by: Float(event.rotation) * .pi / 180)
    }
}
#else
/// Touch gestures arrive in a later milestone; for now the iOS view is a plain MTKView.
final class InteractiveStarView: MTKView {}
#endif
