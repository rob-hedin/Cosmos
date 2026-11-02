import StarCatalog
import SwiftUI

/// Controls for a `StarFilter`: distance, spectral class, brightness and multiple systems.
struct StarFilterControls: View {
    @Binding var filter: StarFilter
    let catalog: StarCatalog

    /// The slider's far end; dragging to it means "no limit".
    private static let maxDistance = 200.0
    private static let magnitudeRange = -3.0...20.0

    var body: some View {
        #if os(macOS)
        form
        #else
        // Scrolls only where the popover is too short, as on a phone in landscape.
        ViewThatFits(in: .vertical) {
            form
            ScrollView { form }
        }
        #endif
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Distance from the Sun") {
                Text(distanceText).monospacedDigit().foregroundStyle(.secondary)
                labeledSlider("Nearest", value: nearest)
                labeledSlider("Farthest", value: farthest)
            }

            section("Spectral class") {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach([Array(SpectralClass.allCases.prefix(5)), Array(SpectralClass.allCases.dropFirst(5))], id: \.self) { row in
                        GridRow {
                            ForEach(row) { spectralClass in
                                Toggle(spectralClass.shortTitle, isOn: classBinding(spectralClass))
                                    .toggleStyle(.button)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .help(Self.help(for: spectralClass))
                            }
                        }
                    }
                }
            }

            section("Brightness") {
                Toggle("Only stars brighter than", isOn: limitsBrightness)
                if let limit = filter.brightestAbsoluteMagnitude {
                    HStack {
                        Slider(value: magnitude, in: Self.magnitudeRange, step: 0.5)
                        Text("M \(limit.formatted(.number.precision(.fractionLength(1))))")
                            .monospacedDigit()
                            .frame(minWidth: 52, alignment: .trailing)
                    }
                    Text("Absolute magnitude: lower is brighter. The Sun is M 4.8.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            section("Star systems") {
                Picker("Star systems", selection: $filter.multiplicity) {
                    ForEach(StarMultiplicity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Multiple: stars with a companion within 0.3 ly, or a companion in their spectral type")
            }

            Divider()
            HStack {
                Text("\(catalog.stars(matching: filter).count.formatted()) of \(catalog.stars.count.formatted()) stars match")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Show All") { filter = .all }
                    .disabled(filter.showsEverything)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 64, alignment: .leading)
            Slider(value: value, in: 0...Self.maxDistance, step: 1)
        }
    }

    private var distanceText: String {
        let low = filter.distance.lowerBound.formatted(.number.precision(.fractionLength(0)))
        let high = filter.distance.upperBound
        return high.isFinite && high < Self.maxDistance
            ? "\(low) to \(high.formatted(.number.precision(.fractionLength(0)))) ly"
            : "\(low) ly and beyond"
    }

    private var nearest: Binding<Double> {
        Binding {
            min(filter.distance.lowerBound, Self.maxDistance)
        } set: { low in
            let high = max(filter.distance.upperBound, low)
            filter.distance = low...high
        }
    }

    private var farthest: Binding<Double> {
        Binding {
            min(filter.distance.upperBound, Self.maxDistance)
        } set: { high in
            let upper = high >= Self.maxDistance ? .infinity : high
            filter.distance = min(filter.distance.lowerBound, high)...upper
        }
    }

    private func classBinding(_ spectralClass: SpectralClass) -> Binding<Bool> {
        Binding {
            filter.spectralClasses.contains(spectralClass)
        } set: { isOn in
            if isOn {
                filter.spectralClasses.insert(spectralClass)
            } else {
                filter.spectralClasses.remove(spectralClass)
            }
        }
    }

    private var limitsBrightness: Binding<Bool> {
        Binding {
            filter.brightestAbsoluteMagnitude != nil
        } set: { isOn in
            filter.brightestAbsoluteMagnitude = isOn ? 5 : nil
        }
    }

    private var magnitude: Binding<Double> {
        Binding {
            filter.brightestAbsoluteMagnitude ?? 5
        } set: {
            filter.brightestAbsoluteMagnitude = $0
        }
    }

    private static func help(for spectralClass: SpectralClass) -> String {
        switch spectralClass {
        case .o, .b: "Hot blue stars"
        case .a, .f: "White stars"
        case .g: "Yellow stars like the Sun"
        case .k: "Orange stars"
        case .m: "Red dwarfs and red giants"
        case .whiteDwarf: "White dwarfs"
        case .other: "Carbon stars, Wolf-Rayet stars and stars with no spectral type"
        }
    }
}

/// A search field with suggestions as you type. Return picks the first suggestion.
struct StarSearchPanel: View {
    let catalog: StarCatalog
    let onPick: (StarLocation) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let results = catalog.search(query)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search stars", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    .onSubmit { results.first.map(onPick) }
                    .onKeyPress(.escape) {
                        onDismiss()
                        return .handled
                    }
                Button("Close", systemImage: "xmark.circle.fill", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            if !results.isEmpty {
                Divider()
                ForEach(results, id: \.self) { location in
                    Button {
                        onPick(location)
                    } label: {
                        HStack {
                            Text(location.name)
                            Spacer()
                            Text(StarRouteTile.format(location.distance(to: .sun)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider()
                Text("No stars match").foregroundStyle(.secondary).padding(10)
            }
        }
        .frame(width: 280)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        // Focus once the panel is on screen; focusing during the same update can be dropped.
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            isFocused = true
        }
    }
}
