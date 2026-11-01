import StarCatalog
import SwiftUI

/// A compact card describing one star: name, distance, type, magnitudes and physical estimates.
public struct StarInfoCard: View {
    private let star: Star
    private let onClose: (() -> Void)?

    public init(star: Star, onClose: (() -> Void)? = nil) {
        self.star = star
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(swatch)
                    .frame(width: 10, height: 10)
                Text(star.name)
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
                row("Distance", "\(number(star.distanceLightYears, digits: 2)) ly")
                if !star.constellation.isEmpty {
                    row("Constellation", star.constellation)
                }
                row("Spectral type", star.spectralType ?? "Unknown")
                row("Color", star.colorName)
                row("Apparent mag", number(star.apparentMagnitude, digits: 2))
                row("Absolute mag", number(star.absoluteMagnitude, digits: 2))
                row("Luminosity", "\(significant(star.luminosity)) L☉")
                row("Temperature", "\(number(star.temperature.rounded(), digits: 0)) K")
                row("Radius (est.)", "\(significant(star.estimatedRadius)) R☉")
            }
            .font(.callout)
        }
        .padding(12)
        .frame(maxWidth: 300, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private var swatch: Color {
        Color(.sRGBLinear, red: Double(star.color.x), green: Double(star.color.y), blue: Double(star.color.z))
    }

    private func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    /// Three significant figures, so 0.0000562 and 22.6 both read well.
    private func significant(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(3)))
    }
}
