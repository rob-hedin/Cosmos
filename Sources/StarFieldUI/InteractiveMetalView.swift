import MetalKit
import StarCatalog
import StarRenderer
import simd

/// What the gesture view moves: a renderer's camera. The star view and the Planetary System view
/// each have their own camera, and the gestures are the same for both.
@MainActor
protocol CameraController: AnyObject {
    /// Orbits around the target; angles in radians, screen convention (+x a drag to the right,
    /// +y a drag downward).
    func rotate(by angles: SIMD2<Float>)
    /// Slides the view with a drag of `points` (+y downward) in a viewport whose shorter side is
    /// `viewportShortSide` points.
    func pan(byPoints points: SIMD2<Float>, viewportShortSide: Float)
    /// Multiplies the distance to the target: below 1 moves closer.
    func zoom(by factor: Float)
    /// Spins the view about its line of sight, in radians (counterclockwise when positive).
    func roll(by angle: Float)
    /// Keeps rotating at `angularVelocity` (radians per second, screen convention) after a drag.
    func fling(angularVelocity: SIMD2<Float>)
    /// Stops a fling and any flight.
    func stopMotion()
    /// Stops a flight, leaving any fling running.
    func cancelFlight()
}

extension StarRenderer: CameraController {
    func rotate(by angles: SIMD2<Float>) { camera.rotate(by: angles) }
    func pan(byPoints points: SIMD2<Float>, viewportShortSide: Float) {
        camera.pan(byPoints: points, viewportShortSide: viewportShortSide)
    }
    func zoom(by factor: Float) { camera.zoom(by: factor) }
    func roll(by angle: Float) { camera.roll(by: angle) }
}

extension PlanetarySystemRenderer: CameraController {}

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
/// | Click | `onClick`: the star view selects a star, the Planetary System view an item |
/// | Double-click | `onDoubleClick`: flies to what is under the pointer, or resets on empty space |
final class InteractiveMetalView: MTKView {
    /// Rotation per point dragged, in radians.
    var radiansPerPoint: Float = 0.006

    /// What the gestures move.
    weak var controller: (any CameraController)?

    /// A single click, at a point in the view (top-left origin) with a hit tolerance in points.
    var onClick: (@MainActor (CGPoint, Float) -> Void)?

    /// A double-click, at a point in the view (top-left origin) with a hit tolerance in points.
    /// The first click of the pair has already run `onClick`.
    var onDoubleClick: (@MainActor (CGPoint, Float) -> Void)?

    /// How close to an item a click counts as a hit, in points.
    var clickTolerance: Float = 20

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
            controller?.rotate(by: delta * radiansPerPoint)
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
        controller?.fling(angularVelocity: distance / Float(duration) * radiansPerPoint)
    }

    override func rightMouseDown(with event: NSEvent) {
        beginDrag(at: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        beginDrag(at: event)
    }

    private func beginDrag(at event: NSEvent) {
        controller?.stopMotion()
        rotationSamples.removeAll()
        lastEventTime = event.timestamp
        travel = 0
    }

    /// A single click runs `onClick`; a double click runs `onDoubleClick` (the first click of the pair already ran `onClick`).
    private func click(count: Int, at event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let topLeft = CGPoint(x: location.x, y: isFlipped ? location.y : bounds.height - location.y)
        switch count {
        case 1:
            onClick?(topLeft, clickTolerance)
        case 2:
            onDoubleClick?(topLeft, clickTolerance)
        default:
            break
        }
    }

    override func rightMouseDragged(with event: NSEvent) {
        pan(by: SIMD2(Float(event.deltaX), Float(event.deltaY)))
    }

    override func otherMouseDragged(with event: NSEvent) {
        pan(by: SIMD2(Float(event.deltaX), Float(event.deltaY)))
    }

    private func pan(by points: SIMD2<Float>) {
        let shortSide = Float(min(bounds.width, bounds.height))
        controller?.pan(byPoints: points, viewportShortSide: shortSide)
    }

    // MARK: Zoom and roll

    override func scrollWheel(with event: NSEvent) {
        // Trackpads report fine-grained point deltas; mouse wheels report coarse lines.
        let perUnit: Float = event.hasPreciseScrollingDeltas ? 0.005 : 0.08
        controller?.cancelFlight()
        controller?.zoom(by: exp(-Float(event.scrollingDeltaY) * perUnit))
    }

    override func magnify(with event: NSEvent) {
        controller?.cancelFlight()
        controller?.zoom(by: 1 / max(1 + Float(event.magnification), 0.1))
    }

    override func rotate(with event: NSEvent) {
        controller?.roll(by: Float(event.rotation) * .pi / 180)
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
/// | Tap | `onClick`: the star view selects a star, the Planetary System view an item |
/// | Double-tap | `onDoubleClick`: flies to what is under the finger, or resets on empty space |
final class InteractiveMetalView: MTKView, UIGestureRecognizerDelegate {
    /// Rotation per point dragged, in radians.
    var radiansPerPoint: Float = 0.006

    /// What the gestures move.
    weak var controller: (any CameraController)?

    /// A single tap, at a point in the view (top-left origin) with a hit tolerance in points.
    var onClick: (@MainActor (CGPoint, Float) -> Void)?

    /// A double tap, at a point in the view (top-left origin) with a hit tolerance in points.
    /// `onClick` runs first, as the first click of a double-click does on the Mac.
    var onDoubleClick: (@MainActor (CGPoint, Float) -> Void)?

    /// Fingers get a little more room than a pointer (20 points on the Mac) when picking.
    var touchTolerance: Float = 28

    /// True once a second finger joins the touch sequence (a pinch, pan or roll begins), until the
    /// next sequence starts. One-finger rotation stops, without flinging, while it's set.
    private var isMultiTouch = false

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
        rotate.delegate = self

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

    /// Every drag, pinch and roll can run together, so adding a second finger mid-drag hands over
    /// to pinch, pan and roll; `isMultiTouch` keeps the one-finger rotation out of it.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer.delegate === self && other.delegate === self
    }

    // MARK: Touches

    /// Any new touch stops a fling or a flight, so a finger on the screen holds the view still.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller?.stopMotion()
        // Recognizers may hold back later touches from the view, so this reliably sees only the
        // first finger of a sequence; the multi-touch recognizers set the flag when they begin.
        isMultiTouch = (event?.touches(for: self)?.count ?? touches.count) > 1
        super.touchesBegan(touches, with: event)
    }

    /// Called by the two-finger recognizers.
    private func noteMultiTouch(_ recognizer: UIGestureRecognizer) {
        if recognizer.state == .began {
            isMultiTouch = true
        }
    }

    /// Movement since the last call, consumed so each update is a delta. Read in every state,
    /// since a short gesture can go from began straight to ended.
    private func takeTranslation(_ recognizer: UIPanGestureRecognizer) -> SIMD2<Float> {
        let delta = recognizer.translation(in: self)
        recognizer.setTranslation(.zero, in: self)
        return SIMD2(Float(delta.x), Float(delta.y))
    }

    @objc private func rotate(_ recognizer: UIPanGestureRecognizer) {
        guard let controller, [.began, .changed, .ended].contains(recognizer.state) else { return }
        let delta = takeTranslation(recognizer)
        guard !isMultiTouch else { return }
        controller.rotate(by: delta * radiansPerPoint)
        if recognizer.state == .ended {
            // UIKit measures release speed itself, in points per second, independent of frame rate.
            let velocity = recognizer.velocity(in: self)
            controller.fling(angularVelocity: SIMD2(Float(velocity.x), Float(velocity.y)) * radiansPerPoint)
        }
    }

    @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
        noteMultiTouch(recognizer)
        guard let controller, [.began, .changed, .ended].contains(recognizer.state) else { return }
        let delta = takeTranslation(recognizer)
        controller.cancelFlight()
        controller.pan(byPoints: delta, viewportShortSide: shortSide)
    }

    @objc private func pinch(_ recognizer: UIPinchGestureRecognizer) {
        noteMultiTouch(recognizer)
        guard let controller, [.began, .changed, .ended].contains(recognizer.state), recognizer.scale > 0 else { return }
        controller.cancelFlight()
        controller.zoom(by: 1 / Float(recognizer.scale))
        recognizer.scale = 1
    }

    @objc private func roll(_ recognizer: UIRotationGestureRecognizer) {
        noteMultiTouch(recognizer)
        guard let controller, [.began, .changed, .ended].contains(recognizer.state) else { return }
        // UIKit's rotation is clockwise-positive; the camera's roll is counterclockwise-positive.
        controller.roll(by: -Float(recognizer.rotation))
        recognizer.rotation = 0
    }

    @objc private func scroll(_ recognizer: UIPanGestureRecognizer) {
        guard let controller, [.began, .changed, .ended].contains(recognizer.state) else { return }
        // Pointer scrolling sends no touches, so stop a fling here rather than in touchesBegan.
        if recognizer.state == .began {
            controller.stopMotion()
        }
        let delta = takeTranslation(recognizer)
        controller.zoom(by: exp(-delta.y * 0.005))
    }

    @objc private func tap(_ recognizer: UITapGestureRecognizer) {
        onClick?(recognizer.location(in: self), touchTolerance)
    }

    @objc private func doubleTap(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: self)
        // Click first (to select, or on empty space to deselect), as a double-click does on the Mac,
        // where the first click already ran it. The single-tap recognizer waits for this one to
        // fail, so it won't run it.
        onClick?(location, touchTolerance)
        onDoubleClick?(location, touchTolerance)
    }

    private var shortSide: Float {
        Float(min(bounds.width, bounds.height))
    }
}
#endif
