import StarCatalog
import SwiftUI

/// A star field with built-in controls for star names and the size mode.
/// `StarFieldScene` uses this; use it directly to get the same controls in your own layout.
public struct StarFieldBrowser: View {
    @State private var sizeMode: StarSizeMode = .luminosity
    @State private var showsLabels = true
    @State private var selection: Star.ID?

    public init() {}

    public var body: some View {
        StarFieldView(sizeMode: sizeMode, selection: $selection, showsLabels: showsLabels)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    Toggle("Names", systemImage: "textformat", isOn: $showsLabels)
                        .toggleStyle(.button)
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
                .padding()
            }
    }
}
