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
import UIKit

/// An MTKView that turns touch, Pencil and iPad pointer input into camera moves.
///
/// | Action | Input |
/// | --- | --- |
/// | Rotate | One-finger drag (keeps spinning briefly if released while moving) |
/// | Zoom | Pinch, or scroll with a trackpad or mouse |
/// | Pan | Two-finger drag |
/// | Roll | Two-finger rotate |
/// | Select | Tap a star (tap empty space to deselect) |
/// | Fly to a star | Double-tap it |
/// | Reset | Double-tap empty space |
final class InteractiveStarView: MTKView, UIGestureRecognizerDelegate {
    /// Rotation per point dragged, in radians.
    var radiansPerPoint: Float = 0.006

    /// Called when a tap selects a star, or with nil when a tap lands on empty space.
    var onSelect: (@MainActor (Star?) -> Void)?

    /// Distance to orbit a star from after double-tapping it, in light years.
    var flyToDistance: Float = 20

    /// Fingers get a little more room than a pointer when picking a star.
    var touchTolerance: Float = 28

    private var renderer: StarRenderer? {
        delegate as? StarRenderer
    }

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        installGestures()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        installGestures()
    }

    private func installGestures() {
        isMultipleTouchEnabled = true

        let rotate = UIPanGestureRecognizer(target: self, action: #selector(rotate(_:)))
        rotate.maximumNumberOfTouches = 1
        rotate.allowedScrollTypesMask = []

        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.allowedScrollTypesMask = []
        pan.delegate = self

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        pinch.delegate = self

        let roll = UIRotationGestureRecognizer(target: self, action: #selector(roll(_:)))
        roll.delegate = self

        // Trackpad and mouse-wheel scrolling on iPad; no touches, so it never fights the drags.
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(scroll(_:)))
        scroll.allowedScrollTypesMask = .all
        scroll.allowedTouchTypes = []

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2

        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        tap.require(toFail: doubleTap)

        for recognizer in [rotate, pan, pinch, roll, scroll, doubleTap, tap] {
            addGestureRecognizer(recognizer)
        }
    }

    /// Pinch, roll and two-finger pan work together, like a map.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer.delegate === self && other.delegate === self
    }

    // MARK: Touches

    /// Any new touch stops a fling or a flight, so a finger on the screen holds the view still.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        renderer?.stopMotion()
        super.touchesBegan(touches, with: event)
    }

    @objc private func rotate(_ recognizer: UIPanGestureRecognizer) {
        guard let renderer else { return }
        // A second finger turns the gesture into a pinch, pan or roll: drop the rotation without
        // flinging (re-enabling cancels it), so the camera doesn't turn under a pinch.
        if recognizer.numberOfTouches > 1 {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
            return
        }
        switch recognizer.state {
        case .changed:
            let delta = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)
            renderer.camera.rotate(by: SIMD2(Float(delta.x), Float(delta.y)) * radiansPerPoint)
        case .ended:
            // UIKit measures release speed itself, in points per second, independent of frame rate.
            let velocity = recognizer.velocity(in: self)
            renderer.fling(angularVelocity: SIMD2(Float(velocity.x), Float(velocity.y)) * radiansPerPoint)
        default:
            break
        }
    }

    @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .changed, let renderer else { return }
        let delta = recognizer.translation(in: self)
        recognizer.setTranslation(.zero, in: self)
        renderer.cancelFlight()
        renderer.camera.pan(byPoints: SIMD2(Float(delta.x), Float(delta.y)), viewportShortSide: shortSide)
    }

    @objc private func pinch(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.state == .changed, let renderer, recognizer.scale > 0 else { return }
        renderer.cancelFlight()
        renderer.camera.zoom(by: 1 / Float(recognizer.scale))
        recognizer.scale = 1
    }

    @objc private func roll(_ recognizer: UIRotationGestureRecognizer) {
        guard recognizer.state == .changed, let renderer else { return }
        // UIKit's rotation is clockwise-positive; the camera's roll is counterclockwise-positive.
        renderer.camera.roll(by: -Float(recognizer.rotation))
        recognizer.rotation = 0
    }

    @objc private func scroll(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .changed, let renderer else { return }
        let delta = recognizer.translation(in: self)
        recognizer.setTranslation(.zero, in: self)
        renderer.cancelFlight()
        renderer.camera.zoom(by: exp(-Float(delta.y) * 0.005))
    }

    @objc private func tap(_ recognizer: UITapGestureRecognizer) {
        onSelect?(star(at: recognizer.location(in: self)))
    }

    @objc private func doubleTap(_ recognizer: UITapGestureRecognizer) {
        guard let renderer else { return }
        if let hit = star(at: recognizer.location(in: self)) {
            renderer.fly(to: hit.position, distance: min(renderer.camera.distance, flyToDistance))
        } else {
            renderer.camera.reset()
        }
    }

    private var shortSide: Float {
        Float(min(bounds.width, bounds.height))
    }

    /// The star under a point in the view (top-left origin, as UIKit uses).
    private func star(at point: CGPoint) -> Star? {
        renderer?.star(at: point, viewSize: bounds.size, tolerance: touchTolerance)
    }
}
#endif
