import StarCatalog
import SwiftUI

/// A compact card describing a Body or the Central Star of a Planetary System: name, Kind,
/// Parent, distance, period, radius, mass when known, and the Belt the Body lies in. The rows come
/// from `PlanetarySystemFacts`. Shows nothing for a Body that is not in the system.
public struct PlanetarySystemInfoCard: View {
    private let item: PlanetarySystemItem
    private let system: PlanetarySystem
    private let onClose: (() -> Void)?

    public init(item: PlanetarySystemItem, system: PlanetarySystem, onClose: (() -> Void)? = nil) {
        self.item = item
        self.system = system
        self.onClose = onClose
    }

    public var body: some View {
        if let facts = PlanetarySystemFacts(item: item, in: system) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Circle()
                        .fill(swatch)
                        .frame(width: 10, height: 10)
                    Text(facts.title)
                        .font(.headline)
                    Spacer(minLength: 12)
                    if let onClose {
                        Button("Close", systemImage: "xmark.circle.fill", action: onClose)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(facts.rows, id: \.label) { row in
                        GridRow {
                            Text(row.label).foregroundStyle(.secondary)
                            Text(row.value).monospacedDigit()
                        }
                    }
                }
                .font(.callout)
            }
            .padding(12)
            .frame(maxWidth: 300, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
        }
    }

    /// The Body's color (sRGB), or the star's blackbody color (linear), as the view draws them.
    private var swatch: Color {
        switch item {
        case .centralStar:
            let color = Astrophysics.color(temperature: system.centralStar.temperature)
            return Color(.sRGBLinear, red: Double(color.x), green: Double(color.y), blue: Double(color.z))
        case .body(let name):
            let color = system.body(named: name)?.displayColor ?? .zero
            return Color(.sRGB, red: Double(color.x), green: Double(color.y), blue: Double(color.z))
        }
    }
}
