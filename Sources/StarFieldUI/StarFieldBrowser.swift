import StarCatalog
import SwiftUI

/// A star field with built-in controls for star names, reference rings and the size mode.
/// `StarFieldScene` uses this; use it directly to get the same controls in your own layout.
public struct StarFieldBrowser: View {
    @State private var sizeMode: StarSizeMode = .luminosity
    @State private var showsLabels = true
    @State private var showsRings = true
    @State private var selection: Star.ID?
    @State private var controlsFrame: CGRect?
    private let focus: StarFieldFocus?
    private let route: [String]

    /// Opens on `focus` if given, otherwise frames `route`; see ``StarFieldView``.
    public init(focus: StarFieldFocus? = nil, route: [String] = []) {
        self.focus = focus
        self.route = route
    }

    public var body: some View {
        StarFieldView(
            sizeMode: sizeMode, selection: $selection, showsLabels: showsLabels, showsReferenceRings: showsRings,
            focus: focus, route: route
        )
            .starFieldLabelObstacles([controlsFrame].compactMap { $0 })
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    Toggle("Names", systemImage: "textformat", isOn: $showsLabels)
                        .toggleStyle(.button)
                    Toggle("Rings", systemImage: "circle.dashed", isOn: $showsRings)
                        .toggleStyle(.button)
                        .help("Rings at 50, 100 and 200 light years from the Sun")
                    Picker("Size", selection: $sizeMode) {
                        Text("Luminosity").tag(StarSizeMode.luminosity)
                        Text("Radius").tag(StarSizeMode.estimatedRadius)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Size stars by luminosity, or by estimated physical radius")
                }
                .padding(8)
                .background(.regularMaterial, in: .capsule)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { controlsFrame = $0 }
                .padding()
            }
    }
}
