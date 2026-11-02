#if !os(macOS)
import StarCatalog
import SwiftUI

/// A Planetary System to show full screen from the star view. Each presentation is new, so
/// asking for the same system again shows it again.
struct PresentedPlanetarySystem: Identifiable {
    let id = UUID()
    let system: PlanetarySystem
}

/// A Planetary System filling the screen, with a Done button at the top left.
struct PlanetarySystemCover: View {
    let system: PlanetarySystem
    @Environment(\.dismiss) private var dismiss
    @State private var doneFrame: CGRect?

    var body: some View {
        PlanetarySystemView(system: system)
            .starFieldLabelObstacles([doneFrame].compactMap { $0 })
            .overlay(alignment: .topLeading) {
                Button("Done", systemImage: "xmark") { dismiss() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: .capsule)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { doneFrame = $0 }
                    .onDisappear { doneFrame = nil }
                    .padding()
            }
    }
}
#endif
