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
                .overlay(alignment: .bottomLeading) {
                    if showsInfoCard, let selectedStar {
                        StarInfoCard(star: selectedStar) {
                            selection.wrappedValue = nil
                        }
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
    }

    private func makeRenderer() {
        do {
            let renderer = try StarRenderer(catalog: source.get())
            renderer.sizeMode = sizeMode
            renderer.showsLabels = showsLabels
            renderer.selectedStarID = selection.wrappedValue
            self.renderer = renderer
            failure = nil
        } catch {
            renderer = nil
            failure = error
        }
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
