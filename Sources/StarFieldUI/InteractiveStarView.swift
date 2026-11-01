import MetalKit
import StarCatalog
import StarRenderer
import simd

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
/// | Select | Click a star (click empty space to deselect) |
/// | Fly to a star | Double-click it |
/// | Reset | Double-click empty space |
final class InteractiveStarView: MTKView {
    /// Rotation per point dragged, in radians.
    var radiansPerPoint: Float = 0.006

    /// Called when a click selects a star, or with nil when a click lands on empty space.
    var onSelect: (@MainActor (Star?) -> Void)?

    /// Distance to orbit a star from after double-clicking it, in light years.
    var flyToDistance: Float = 20

    /// Total pointer travel since the press, to tell a click from a drag.
    private var travel: Float = 0
    /// Click count of the current press; click actions run on release, and only if it stayed a click.
    private var pressClickCount = 0

    /// Recent rotation drags, for estimating release speed. Cleared on press and when panning.
    private var rotationSamples: [(delta: SIMD2<Float>, time: TimeInterval, interval: TimeInterval)] = []
    private var lastEventTime: TimeInterval = 0

    /// How far back release speed is averaged, in seconds.
    private let velocityWindow: TimeInterval = 0.08
    /// A gap between drag events longer than this counts as a pause, in seconds.
    private let pauseThreshold: TimeInterval = 0.05
    /// Time charged to the first move after a pause, when the real interval isn't meaningful.
    private let nominalEventInterval: TimeInterval = 1.0 / 60

    private var renderer: StarRenderer? {
        delegate as? StarRenderer
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Rotate and pan

    override func mouseDown(with event: NSEvent) {
        beginDrag(at: event)
        pressClickCount = event.clickCount
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = SIMD2(Float(event.deltaX), Float(event.deltaY))
        travel += simd_length(delta)
        let interval = event.timestamp - lastEventTime
        lastEventTime = event.timestamp
        if event.modifierFlags.contains(.shift) {
            rotationSamples.removeAll()
            pan(by: delta)
        } else {
            renderer?.camera.rotate(by: delta * radiansPerPoint)
            // A long gap means the pointer paused (or this is the first move after the press):
            // start measuring afresh so the pause doesn't count toward the release speed.
            let paused = interval > pauseThreshold
            if paused {
                rotationSamples.removeAll()
            }
            rotationSamples.append((delta, event.timestamp, paused ? nominalEventInterval : interval))
            rotationSamples.removeAll { event.timestamp - $0.time > velocityWindow }
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { rotationSamples.removeAll() }
        if travel < 3 {
            click(count: pressClickCount, at: event)
            return
        }
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
        renderer?.stopMotion()
        rotationSamples.removeAll()
        lastEventTime = event.timestamp
        travel = 0
    }

    /// Single click selects (or deselects on empty space); double click flies to a star or resets.
    private func click(count: Int, at event: NSEvent) {
        let hit = star(at: event)
        switch count {
        case 1:
            onSelect?(hit)
        case 2:
            guard let renderer else { return }
            if let hit {
                renderer.fly(to: hit.position, distance: min(renderer.camera.distance, flyToDistance))
            } else {
                renderer.camera.reset()
            }
        default:
            break
        }
    }

    /// The star under the pointer, if any.
    private func star(at event: NSEvent) -> Star? {
        let location = convert(event.locationInWindow, from: nil)
        let topLeft = CGPoint(x: location.x, y: isFlipped ? location.y : bounds.height - location.y)
        return renderer?.star(at: topLeft, viewSize: bounds.size)
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
        renderer?.cancelFlight()
        renderer?.camera.zoom(by: exp(-Float(event.scrollingDeltaY) * perUnit))
    }

    override func magnify(with event: NSEvent) {
        renderer?.cancelFlight()
        renderer?.camera.zoom(by: 1 / max(1 + Float(event.magnification), 0.1))
    }

    override func rotate(with event: NSEvent) {
        renderer?.camera.roll(by: Float(event.rotation) * .pi / 180)
    }
}
#else
/// Touch gestures arrive in a later milestone; for now the iOS view is a plain MTKView.
final class InteractiveStarView: MTKView {
    var onSelect: (@MainActor (Star?) -> Void)?
}
#endif
