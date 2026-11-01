@_exported import StarCatalog
@_exported import StarRenderer
import MetalKit
import SwiftUI

/// A SwiftUI view that renders a star catalog in 3D with Metal.
public struct StarFieldView: View {
    private let catalog: Result<StarCatalog, any Error>
    private var sizeMode: StarSizeMode

    /// Shows the bundled catalog of stars within 200 light years.
    public init(sizeMode: StarSizeMode = .luminosity) {
        self.catalog = Result { try StarCatalog.bundled() }
        self.sizeMode = sizeMode
    }

    public init(catalog: StarCatalog, sizeMode: StarSizeMode = .luminosity) {
        self.catalog = .success(catalog)
        self.sizeMode = sizeMode
    }

    public var body: some View {
        switch catalog {
        case .success(let catalog):
            MetalStarView(catalog: catalog, sizeMode: sizeMode)
                .ignoresSafeArea()
        case .failure(let error):
            ContentUnavailableView(
                "Stars unavailable",
                systemImage: "sparkles",
                description: Text(String(describing: error))
            )
        }
    }
}

/// Hosts an MTKView driven by a StarRenderer.
struct MetalStarView {
    let catalog: StarCatalog
    let sizeMode: StarSizeMode

    final class Coordinator {
        var renderer: StarRenderer?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    private func makeView(context: Context) -> MTKView {
        let view = MTKView()
        do {
            let renderer = try StarRenderer(catalog: catalog)
            renderer.sizeMode = sizeMode
            renderer.attach(to: view)
            context.coordinator.renderer = renderer
        } catch {
            assertionFailure("StarRenderer failed to start: \(error)")
        }
        return view
    }

    @MainActor
    private func update(context: Context) {
        context.coordinator.renderer?.sizeMode = sizeMode
    }
}

#if os(macOS)
extension MetalStarView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView { makeView(context: context) }
    func updateNSView(_ view: MTKView, context: Context) { update(context: context) }
}
#else
extension MetalStarView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView { makeView(context: context) }
    func updateUIView(_ view: MTKView, context: Context) { update(context: context) }
}
#endif
