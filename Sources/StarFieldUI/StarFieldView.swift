@_exported import StarCatalog
@_exported import StarRenderer
import MetalKit
import SwiftUI

/// A SwiftUI view that renders a star catalog in 3D with Metal.
///
/// Click a star to select it; the selected star gets a highlight ring and, by default,
/// an info card. Pass a `selection` binding to read or set the selection from your app.
/// Star names are shown by default; pass `showsLabels: false` to hide them.
public struct StarFieldView: View {
    private let source: Result<StarCatalog, any Error>
    private let sizeMode: StarSizeMode
    private let externalSelection: Binding<Star.ID?>?
    private let showsInfoCard: Bool
    private let showsLabels: Bool

    @State private var renderer: StarRenderer?
    @State private var failure: (any Error)?
    @State private var internalSelection: Star.ID?
    /// Global frames of the star view and the info card, so labels can keep clear of the card.
    @State private var starViewFrame: CGRect = .zero
    @State private var cardFrame: CGRect?
    @Environment(\.starFieldLabelObstacles) private var labelObstacles

    /// Shows the bundled catalog of stars within 200 light years.
    public init(
        sizeMode: StarSizeMode = .luminosity,
        selection: Binding<Star.ID?>? = nil,
        showsInfoCard: Bool = true,
        showsLabels: Bool = true
    ) {
        self.source = Self.bundledCatalog
        self.sizeMode = sizeMode
        self.externalSelection = selection
        self.showsInfoCard = showsInfoCard
        self.showsLabels = showsLabels
    }

    public init(
        catalog: StarCatalog,
        sizeMode: StarSizeMode = .luminosity,
        selection: Binding<Star.ID?>? = nil,
        showsInfoCard: Bool = true,
        showsLabels: Bool = true
    ) {
        self.source = .success(catalog)
        self.sizeMode = sizeMode
        self.externalSelection = selection
        self.showsInfoCard = showsInfoCard
        self.showsLabels = showsLabels
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
        .onChange(of: selection.wrappedValue) { renderer?.selectedStarID = selection.wrappedValue }
        .onChange(of: labelExclusions) { renderer?.labelExclusions = labelExclusions }
    }

    /// The info card's and any overlaid controls' frames, relative to the star view's safe-area frame
    /// (which is what SwiftUI reports for it, even though the Metal view extends under the title bar).
    private var labelExclusions: [LabelLayout.Rect] {
        ([cardFrame].compactMap { $0 } + labelObstacles).map { frame in
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
            renderer.selectedStarID = selection.wrappedValue
            renderer.labelExclusions = labelExclusions
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
