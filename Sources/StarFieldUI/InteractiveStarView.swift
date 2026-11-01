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

    private var lastDrag: (delta: SIMD2<Float>, time: TimeInterval)?

    private var renderer: StarRenderer? {
        delegate as? StarRenderer
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Rotate and pan

    override func mouseDown(with event: NSEvent) {
        renderer?.stopSpinning()
        lastDrag = nil
        if event.clickCount == 2 {
            renderer?.camera.reset()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = SIMD2(Float(event.deltaX), Float(event.deltaY))
        if event.modifierFlags.contains(.shift) {
            pan(by: delta)
        } else {
            renderer?.camera.rotate(by: delta * radiansPerPoint)
            lastDrag = (delta, event.timestamp)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { lastDrag = nil }
        // Fling only if the pointer was still moving when released.
        guard let lastDrag, event.timestamp - lastDrag.time < 0.05 else { return }
        let framesPerSecond = Float(window?.screen?.maximumFramesPerSecond ?? 60)
        renderer?.fling(angularVelocity: lastDrag.delta * radiansPerPoint * framesPerSecond)
    }

    override func rightMouseDown(with event: NSEvent) {
        renderer?.stopSpinning()
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
