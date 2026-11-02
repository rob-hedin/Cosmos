import MetalKit
import SwiftUI

/// A 3D view of one Planetary System: the Central Star at the middle, with its Bodies as shaded
/// spheres and its Belts as faint rings.
///
/// Opens in Compressed scale with orbits running at 1 week per second. Click or tap to select an
/// item and show an info card; double-click or double-tap a Body to fly to it and follow it, and
/// double-click empty space to go back to the whole system. Drag to rotate, scroll or pinch to
/// zoom, and pan with shift-drag or two fingers; the gestures are the star view's. The controls at
/// the top right switch between Compressed and True scale, pause the orbits, set their speed (1 day
/// to 1 year per second) and turn names on and off.
///
/// `scale`, `speed`, `isPaused` and `showsLabels` are starting values; the controls change them,
/// and passing different values later makes the view adopt them. Pass a `selection` binding to
/// read or set the selected item from your app.
public struct PlanetarySystemView: View {
    private let source: Result<PlanetarySystem, any Error>
    private let externalSelection: Binding<PlanetarySystemItem?>?
    private let scaleParameter: PlanetarySystemScale
    private let speedParameter: SimulationSpeed
    private let isPausedParameter: Bool
    private let showsLabelsParameter: Bool
    private let showsControls: Bool
    private let showsInfoCard: Bool

    @State private var renderer: PlanetarySystemRenderer?
    @State private var failure: (any Error)?
    @State private var internalSelection: PlanetarySystemItem?
    @State private var scale: PlanetarySystemScale
    @State private var speed: SimulationSpeed
    @State private var isPaused: Bool
    @State private var showsLabels: Bool
    /// Global frames of the view, the info card and the controls, so names can keep clear of them.
    @State private var viewFrame: CGRect = .zero
    @State private var cardFrame: CGRect?
    @State private var controlsFrame: CGRect?

    /// Shows `system`.
    public init(
        system: PlanetarySystem,
        selection: Binding<PlanetarySystemItem?>? = nil,
        scale: PlanetarySystemScale = .compressed,
        speed: SimulationSpeed = .week,
        isPaused: Bool = false,
        showsControls: Bool = true,
        showsInfoCard: Bool = true,
        showsLabels: Bool = true
    ) {
        self.init(
            source: .success(system), selection: selection, scale: scale, speed: speed, isPaused: isPaused,
            showsControls: showsControls, showsInfoCard: showsInfoCard, showsLabels: showsLabels
        )
    }

    /// Shows the built-in Solar System (`PlanetarySystem.solarSystem()`, loaded once and shared).
    public init(
        selection: Binding<PlanetarySystemItem?>? = nil,
        scale: PlanetarySystemScale = .compressed,
        speed: SimulationSpeed = .week,
        isPaused: Bool = false,
        showsControls: Bool = true,
        showsInfoCard: Bool = true,
        showsLabels: Bool = true
    ) {
        self.init(
            source: Self.bundledSystem, selection: selection, scale: scale, speed: speed, isPaused: isPaused,
            showsControls: showsControls, showsInfoCard: showsInfoCard, showsLabels: showsLabels
        )
    }

    private init(
        source: Result<PlanetarySystem, any Error>,
        selection: Binding<PlanetarySystemItem?>?,
        scale: PlanetarySystemScale,
        speed: SimulationSpeed,
        isPaused: Bool,
        showsControls: Bool,
        showsInfoCard: Bool,
        showsLabels: Bool
    ) {
        self.source = source
        externalSelection = selection
        scaleParameter = scale
        speedParameter = speed
        isPausedParameter = isPaused
        showsLabelsParameter = showsLabels
        self.showsControls = showsControls
        self.showsInfoCard = showsInfoCard
        _scale = State(initialValue: scale)
        _speed = State(initialValue: speed)
        _isPaused = State(initialValue: isPaused)
        _showsLabels = State(initialValue: showsLabels)
    }

    /// Parsed once and shared, so recreating the view doesn't re-read the JSON.
    static let bundledSystem = Result { try PlanetarySystem.solarSystem() }

    private var system: PlanetarySystem? {
        try? source.get()
    }

    private var selection: Binding<PlanetarySystemItem?> {
        externalSelection ?? $internalSelection
    }

    public var body: some View {
        Group {
            if let failure {
                ContentUnavailableView(
                    "Planetary system unavailable",
                    systemImage: "globe",
                    description: Text(String(describing: failure))
                )
            } else if let renderer {
                MetalPlanetarySystemView(
                    renderer: renderer,
                    onClick: { selection.wrappedValue = $0 },
                    onDoubleClick: { item in
                        if let item {
                            renderer.fly(to: item)
                        } else {
                            renderer.resetView()
                        }
                    }
                )
                .ignoresSafeArea()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewFrame = $0 }
                .overlay(alignment: .bottomLeading) {
                    if showsInfoCard, let item = selection.wrappedValue, let system {
                        PlanetarySystemInfoCard(item: item, system: system) {
                            selection.wrappedValue = nil
                        }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cardFrame = $0 }
                        .onDisappear { cardFrame = nil }
                        .padding()
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if showsControls {
                        PlanetarySystemControls(
                            scale: $scale, speed: $speed, isPaused: $isPaused, showsLabels: $showsLabels
                        )
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { controlsFrame = $0 }
                        .onDisappear { controlsFrame = nil }
                        .padding()
                    }
                }
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .onAppear(perform: makeRenderer)
        .onChange(of: system) {
            // Names from the old system mean nothing in the new one.
            selection.wrappedValue = nil
            makeRenderer()
        }
        .onChange(of: scale) { renderer?.scale = scale }
        .onChange(of: speed) { renderer?.clock.speed = speed }
        .onChange(of: isPaused) { renderer?.clock.isPaused = isPaused }
        .onChange(of: showsLabels) { renderer?.showsLabels = showsLabels }
        .onChange(of: selection.wrappedValue) { renderer?.selection = selection.wrappedValue }
        .onChange(of: labelExclusions) { renderer?.labelExclusions = labelExclusions }
        // New values from the app replace what the controls set.
        .onChange(of: scaleParameter) { scale = scaleParameter }
        .onChange(of: speedParameter) { speed = speedParameter }
        .onChange(of: isPausedParameter) { isPaused = isPausedParameter }
        .onChange(of: showsLabelsParameter) { showsLabels = showsLabelsParameter }
    }

    /// The info card's and the controls' frames, relative to the view's safe-area frame (which is
    /// what SwiftUI reports for it, even though the Metal view extends under the title bar).
    private var labelExclusions: [LabelLayout.Rect] {
        [cardFrame, controlsFrame].compactMap { $0 }.map { frame in
            LabelLayout.Rect(
                origin: SIMD2(Float(frame.minX - viewFrame.minX), Float(frame.minY - viewFrame.minY)),
                size: SIMD2(Float(frame.width), Float(frame.height))
            )
        }
    }

    private func makeRenderer() {
        do {
            let renderer = try PlanetarySystemRenderer(
                system: source.get(), scale: scale, clock: SimulationClock(speed: speed, isPaused: isPaused)
            )
            renderer.showsLabels = showsLabels
            renderer.selection = selection.wrappedValue
            renderer.labelExclusions = labelExclusions
            self.renderer = renderer
            failure = nil
        } catch {
            renderer = nil
            failure = error
        }
    }
}

/// Hosts an MTKView driven by a PlanetarySystemRenderer.
struct MetalPlanetarySystemView {
    let renderer: PlanetarySystemRenderer
    /// A click, with the item under the pointer, or nil on empty space.
    let onClick: @MainActor (PlanetarySystemItem?) -> Void
    /// A double-click, with the item under the pointer, or nil on empty space.
    let onDoubleClick: @MainActor (PlanetarySystemItem?) -> Void

    @MainActor
    private func makeView() -> InteractiveMetalView {
        let view = InteractiveMetalView()
        configure(view)
        renderer.attach(to: view)
        return view
    }

    @MainActor
    private func update(_ view: InteractiveMetalView) {
        configure(view)
        if view.delegate !== renderer {
            renderer.attach(to: view)
        }
    }

    @MainActor
    private func configure(_ view: InteractiveMetalView) {
        let renderer = renderer
        let onClick = onClick
        let onDoubleClick = onDoubleClick
        view.controller = renderer
        view.onClick = { [weak view] point, tolerance in
            guard let view else { return }
            onClick(renderer.item(at: point, viewSize: view.bounds.size, tolerance: tolerance))
        }
        view.onDoubleClick = { [weak view] point, tolerance in
            guard let view else { return }
            onDoubleClick(renderer.item(at: point, viewSize: view.bounds.size, tolerance: tolerance))
        }
    }
}

#if os(macOS)
extension MetalPlanetarySystemView: NSViewRepresentable {
    func makeNSView(context: Context) -> InteractiveMetalView { makeView() }
    func updateNSView(_ view: InteractiveMetalView, context: Context) { update(view) }
}
#else
extension MetalPlanetarySystemView: UIViewRepresentable {
    func makeUIView(context: Context) -> InteractiveMetalView { makeView() }
    func updateUIView(_ view: InteractiveMetalView, context: Context) { update(view) }
}
#endif

#Preview("Solar System") {
    PlanetarySystemView()
}
