import StarCatalog
import SwiftUI

/// Where a star field opens: centered on a star, showing `span` light years across the view's
/// shorter side.
public struct StarFieldFocus: Sendable, Hashable {
    /// A star's name as the info card shows it, a common alias such as "Alpha Centauri",
    /// "Sun" or "Sol", or a catalog number such as "HIP 71683".
    public var star: String
    /// Light years across the view's shorter side.
    public var span: Double

    public init(star: String, span: Double) {
        self.star = star
        self.span = span
    }
}

/// Lists a route's legs and their distances, and any names that weren't found.
struct StarRouteTile: View {
    let route: StarRoute
    /// Names, from the route or the focus, that matched no star.
    let notFound: [String]
    /// Guidance while building a route.
    var hint: String?
    var onUndo: (@MainActor () -> Void)?
    /// Shown whenever there is a route.
    var onClear: (@MainActor () -> Void)?

    var body: some View {
        // Scrolls only when a long route won't fit in the space below any controls.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: 340, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !route.stops.isEmpty || hint != nil {
                HStack(spacing: 10) {
                    Text("Route").font(.headline)
                    Spacer(minLength: 12)
                    if let onUndo, !route.stops.isEmpty {
                        Button("Undo", systemImage: "arrow.uturn.backward", action: onUndo)
                            .help("Remove the last stop")
                    }
                    if let onClear, !route.stops.isEmpty {
                        Button("Clear", systemImage: "xmark.circle", action: onClear)
                            .help("Clear the whole route")
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            if let hint {
                Text(hint).foregroundStyle(.secondary)
            }
            if route.stops.count == 1, let stop = route.stops.first {
                Text(stop.name)
            }
            if !route.legs.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    ForEach(Array(route.legs.enumerated()), id: \.offset) { _, leg in
                        GridRow {
                            Text("\(leg.from.name) → \(leg.to.name)")
                            Text(Self.format(leg.distance))
                                .monospacedDigit()
                                .gridColumnAlignment(.trailing)
                        }
                    }
                    if route.legs.count > 1 {
                        Divider()
                            .gridCellUnsizedAxes(.horizontal)
                        GridRow {
                            Text("Total")
                            Text(Self.format(route.totalDistance))
                                .monospacedDigit()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            if !notFound.isEmpty {
                Label("Not found: \(notFound.joined(separator: ", "))", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: 340, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    static func format(_ lightYears: Double) -> String {
        "\(lightYears.formatted(.number.precision(.fractionLength(2)))) ly"
    }
}
