@_exported import StarCatalog
@_exported import StarRenderer
import MetalKit
import SwiftUI

/// A SwiftUI view that renders a star catalog in 3D with Metal.
///
/// Click a star to select it; the selected star gets a highlight ring and, by default,
/// an info card. Pass a `selection` binding to read or set the selection from your app.
/// Star names and reference rings at 50, 100 and 200 ly are shown by default; pass
/// `showsLabels: false` or `showsReferenceRings: false` to hide them. The Sun is always marked.
///
/// Pass a `focus` to open centered on a star at a given span in light years, or a `route` of
/// star names to draw lines between them in order, list each leg's distance in a tile, and
/// frame all the stops around the first one. A focus, when given, decides the view instead.
public struct StarFieldView: View {
    private let source: Result<StarCatalog, any Error>
    private let sizeMode: StarSizeMode
    private let externalSelection: Binding<Star.ID?>?
    private let showsInfoCard: Bool
    private let showsLabels: Bool
    private let showsReferenceRings: Bool
    private let focus: StarFieldFocus?
    private let routeNames: [String]

    @State private var renderer: StarRenderer?
    @State private var failure: (any Error)?
    @State private var internalSelection: Star.ID?
    /// Global frames of the star view and the info card, so labels can keep clear of the card.
    @State private var starViewFrame: CGRect = .zero
    @State private var cardFrame: CGRect?
    @State private var route: StarRoute?
    @State private var tileFrame: CGRect?
    @Environment(\.starFieldLabelObstacles) private var labelObstacles

    /// Shows the bundled catalog of stars within 200 light years.
    public init(
        sizeMode: StarSizeMode = .luminosity,
        selection: Binding<Star.ID?>? = nil,
        showsInfoCard: Bool = true,
        showsLabels: Bool = true,
        showsReferenceRings: Bool = true,
        focus: StarFieldFocus? = nil,
        route: [String] = []
    ) {
        self.source = Self.bundledCatalog
        self.sizeMode = sizeMode
        self.externalSelection = selection
        self.showsInfoCard = showsInfoCard
        self.showsLabels = showsLabels
        self.showsReferenceRings = showsReferenceRings
        self.focus = focus
        self.routeNames = route
    }

    public init(
        catalog: StarCatalog,
        sizeMode: StarSizeMode = .luminosity,
        selection: Binding<Star.ID?>? = nil,
        showsInfoCard: Bool = true,
        showsLabels: Bool = true,
        showsReferenceRings: Bool = true,
        focus: StarFieldFocus? = nil,
        route: [String] = []
    ) {
        self.source = .success(catalog)
        self.sizeMode = sizeMode
        self.externalSelection = selection
        self.showsInfoCard = showsInfoCard
        self.showsLabels = showsLabels
        self.showsReferenceRings = showsReferenceRings
        self.focus = focus
        self.routeNames = route
    }

    /// Parsed once and shared, so recreating the view doesn't re-read the CSV.
    private static let bundledCatalog = Result { try StarCatalog.bundled() }

    private var catalog: StarCatalog? {
        try? source.get()
    }

    private var selection: Binding<Star.ID?> {
        externalSelection ?? $internalSelection
    }

    private var selectedStar: Star? {
        guard let id = selection.wrappedValue else { return nil }
        return renderer?.catalog.star(withID: id)
    }

    public var body: some View {
        Group {
            if let failure {
                ContentUnavailableView(
                    "Stars unavailable",
                    systemImage: "sparkles",
                    description: Text(String(describing: failure))
                )
            } else if let renderer {
                MetalStarView(renderer: renderer) { star in
                    selection.wrappedValue = star?.id
                }
                .ignoresSafeArea()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { starViewFrame = $0 }
                .overlay(alignment: .bottomLeading) {
                    if showsInfoCard, let selectedStar {
                        StarInfoCard(star: selectedStar) {
                            selection.wrappedValue = nil
                        }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cardFrame = $0 }
                        .onDisappear { cardFrame = nil }
                        .padding()
                    }
                }
                .overlay(alignment: .topLeading) {
                    let notFound = notFound
                    if route?.stops.isEmpty == false || !notFound.isEmpty {
                        StarRouteTile(route: route ?? StarRoute(stops: []), notFound: notFound)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { tileFrame = $0 }
                            .onDisappear { tileFrame = nil }
                            .padding()
                            .padding(.top, tileTopOffset)
                    }
                }
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .onAppear(perform: makeRenderer)
        .onChange(of: catalog) {
            // IDs from the old catalog mean nothing in the new one.
            selection.wrappedValue = nil
            makeRenderer()
        }
        .onChange(of: sizeMode) { renderer?.sizeMode = sizeMode }
        .onChange(of: showsLabels) { renderer?.showsLabels = showsLabels }
        .onChange(of: showsReferenceRings) { renderer?.showsReferenceRings = showsReferenceRings }
        .onChange(of: selection.wrappedValue) { renderer?.selectedStarID = selection.wrappedValue }
        .onChange(of: labelExclusions) { renderer?.labelExclusions = labelExclusions }
        .onChange(of: routeNames) {
            let route = resolveRoute()
            self.route = route
            if let renderer { aim(renderer, route: route, animated: true) }
        }
        .onChange(of: focus) {
            if let renderer { aim(renderer, route: route, animated: true) }
        }
    }

    /// Names that matched nothing: the route's, then the focus star's.
    private var notFound: [String] {
        var names = route?.unresolved ?? []
        if let focus, catalog?.location(named: focus.star) == nil { names.append(focus.star) }
        return names
    }

    /// How far to push the route tile down so it clears overlaid controls that share its top
    /// edge, as on a phone where they don't fit side by side.
    private var tileTopOffset: CGFloat {
        guard let tileFrame else { return 0 }
        let tileLeft = starViewFrame.minX
        let tileRight = tileFrame.maxX + 8
        let blocking = labelObstacles.filter { $0.minX < tileRight && $0.maxX > tileLeft && $0.minY < starViewFrame.midY }
        guard let bottom = blocking.map(\.maxY).max() else { return 0 }
        // The tile's own padding already gives 16 points from the top.
        return max(bottom - starViewFrame.minY - 8, 0)
    }

    private func resolveRoute() -> StarRoute? {
        guard let catalog, !routeNames.isEmpty else { return nil }
        return StarRoute(routeNames, in: catalog)
    }

    /// Points the camera at the focus star or, without one, frames the route around its first stop.
    private func aim(_ renderer: StarRenderer, route: StarRoute?, animated: Bool) {
        renderer.route = route
        var camera = renderer.camera
        if let focus, let location = renderer.catalog.location(named: focus.star) {
            camera.center(on: location.position, span: Float(focus.span))
        } else if let route, let first = route.stops.first {
            camera.fit(center: first.position, radius: Float(route.reachFromFirstStop))
        } else {
            return
        }
        if animated {
            renderer.fly(to: camera.target, distance: camera.distance)
        } else {
            renderer.camera = camera
        }
    }

    /// The info card's and any overlaid controls' frames, relative to the star view's safe-area frame
    /// (which is what SwiftUI reports for it, even though the Metal view extends under the title bar).
    private var labelExclusions: [LabelLayout.Rect] {
        ([cardFrame, tileFrame].compactMap { $0 } + labelObstacles).map { frame in
            LabelLayout.Rect(
                origin: SIMD2(Float(frame.minX - starViewFrame.minX), Float(frame.minY - starViewFrame.minY)),
                size: SIMD2(Float(frame.width), Float(frame.height))
            )
        }
    }

    private func makeRenderer() {
        do {
            let renderer = try StarRenderer(catalog: source.get())
            renderer.sizeMode = sizeMode
            renderer.showsLabels = showsLabels
            renderer.showsReferenceRings = showsReferenceRings
            renderer.referenceRingPlanes = .all
            renderer.showsSunMarker = true
            renderer.selectedStarID = selection.wrappedValue
            renderer.labelExclusions = labelExclusions
            let route = resolveRoute()
            self.route = route
            aim(renderer, route: route, animated: false)
            self.renderer = renderer
            failure = nil
        } catch {
            renderer = nil
            failure = error
        }
    }
}

extension EnvironmentValues {
    /// Global frames of views drawn over a star field, which star names should keep clear of.
    @Entry var starFieldLabelObstacles: [CGRect] = []
}

extension View {
    /// Keeps star names in the `StarFieldView`s inside this view clear of the given regions,
    /// such as controls you overlay on the star field. Frames are in global coordinates.
    public func starFieldLabelObstacles(_ frames: [CGRect]) -> some View {
        environment(\.starFieldLabelObstacles, frames)
    }
}

/// Hosts an MTKView driven by a StarRenderer.
struct MetalStarView {
    let renderer: StarRenderer
    let onSelect: @MainActor (Star?) -> Void

    @MainActor
    private func makeView() -> InteractiveStarView {
        let view = InteractiveStarView()
        view.onSelect = onSelect
        renderer.attach(to: view)
        return view
    }

    @MainActor
    private func update(_ view: InteractiveStarView) {
        view.onSelect = onSelect
        if view.delegate !== renderer {
            renderer.attach(to: view)
        }
    }
}

#if os(macOS)
extension MetalStarView: NSViewRepresentable {
    func makeNSView(context: Context) -> InteractiveStarView { makeView() }
    func updateNSView(_ view: InteractiveStarView, context: Context) { update(view) }
}
#else
extension MetalStarView: UIViewRepresentable {
    func makeUIView(context: Context) -> InteractiveStarView { makeView() }
    func updateUIView(_ view: InteractiveStarView, context: Context) { update(view) }
}
#endif
