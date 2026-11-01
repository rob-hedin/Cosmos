@_exported import StarCatalog
@_exported import StarRenderer
import MetalKit
import SwiftUI

/// A SwiftUI view that renders a star catalog in 3D with Metal.
public struct StarFieldView: View {
    private let source: Result<StarCatalog, any Error>
    private let sizeMode: StarSizeMode

    @State private var renderer: StarRenderer?
    @State private var failure: (any Error)?

    /// Shows the bundled catalog of stars within 200 light years.
    public init(sizeMode: StarSizeMode = .luminosity) {
        self.source = Self.bundledCatalog
        self.sizeMode = sizeMode
    }

    public init(catalog: StarCatalog, sizeMode: StarSizeMode = .luminosity) {
        self.source = .success(catalog)
        self.sizeMode = sizeMode
    }

    /// Parsed once and shared, so recreating the view doesn't re-read the CSV.
    private static let bundledCatalog = Result { try StarCatalog.bundled() }

    private var catalog: StarCatalog? {
        try? source.get()
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
                MetalStarView(renderer: renderer)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .onAppear(perform: makeRenderer)
        .onChange(of: catalog) { makeRenderer() }
        .onChange(of: sizeMode) { renderer?.sizeMode = sizeMode }
    }

    private func makeRenderer() {
        do {
            let renderer = try StarRenderer(catalog: source.get())
            renderer.sizeMode = sizeMode
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

    @MainActor
    private func makeView() -> MTKView {
        let view = MTKView()
        renderer.attach(to: view)
        return view
    }

    @MainActor
    private func update(_ view: MTKView) {
        if view.delegate !== renderer {
            renderer.attach(to: view)
        }
    }
}

#if os(macOS)
extension MetalStarView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView { makeView() }
    func updateNSView(_ view: MTKView, context: Context) { update(view) }
}
#else
extension MetalStarView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView { makeView() }
    func updateUIView(_ view: MTKView, context: Context) { update(view) }
}
#endif
