import StarCatalog
import SwiftUI

/// A star field with built-in controls: search, filters, star names, reference rings and the
/// size mode. `StarFieldScene` uses this; use it directly to get the same controls in your own layout.
public struct StarFieldBrowser: View {
    @State private var sizeMode: StarSizeMode = .luminosity
    @State private var showsLabels = true
    @State private var showsRings = true
    @State private var selection: Star.ID?
    @State private var filter: StarFilter
    @State private var isSearching = false
    @State private var showsFilters = false
    @State private var flight: FlightRequest?
    @State private var controlsFrame: CGRect?
    @State private var searchFrame: CGRect?
    private let focus: StarFieldFocus?
    private let route: [String]
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// On a phone the toggles show only their icons, so the controls fit across the screen.
    private var isCompact: Bool { horizontalSizeClass == .compact }
    #else
    private let isCompact = false
    #endif

    /// Opens on `focus` if given, otherwise frames `route`, showing the stars `filter` lets
    /// through; see ``StarFieldView``.
    public init(focus: StarFieldFocus? = nil, route: [String] = [], filter: StarFilter = .all) {
        self.focus = focus
        self.route = route
        _filter = State(initialValue: filter)
    }

    private var catalog: StarCatalog? {
        try? StarFieldView.bundledCatalog.get()
    }

    public var body: some View {
        StarFieldView(
            sizeMode: sizeMode, selection: $selection, showsLabels: showsLabels, showsReferenceRings: showsRings,
            focus: focus, route: route, filter: filter
        )
        .flying(to: flight)
        .starFieldLabelObstacles([controlsFrame, searchFrame].compactMap { $0 })
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                controls
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { controlsFrame = $0 }
                if isSearching, let catalog {
                    StarSearchPanel(catalog: catalog, onPick: pick) { isSearching = false }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { searchFrame = $0 }
                        .onDisappear { searchFrame = nil }
                }
            }
            .padding()
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Toggle("Search", systemImage: "magnifyingglass", isOn: $isSearching)
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .keyboardShortcut("f", modifiers: .command)
                .help("Find a star (⌘F)")
            Button {
                showsFilters.toggle()
            } label: {
                Label(
                    "Filters",
                    systemImage: filter.showsEverything
                        ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
                )
            }
            .labelStyle(.iconOnly)
            .help("Show only some stars")
            .popover(isPresented: $showsFilters) {
                if let catalog {
                    StarFilterControls(filter: $filter, catalog: catalog)
                        .presentationCompactAdaptation(.popover)
                }
            }
            if isCompact {
                toggles.labelStyle(.iconOnly)
            } else {
                toggles
            }
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
    }

    private var toggles: some View {
        Group {
            Toggle("Names", systemImage: "textformat", isOn: $showsLabels)
                .help("Star names")
            Toggle("Rings", systemImage: "circle.dashed", isOn: $showsRings)
                .help("Rings at 50, 100 and 200 light years from the Sun")
        }
        .toggleStyle(.button)
    }

    /// Selects the star and glides to it. The Sun can't be selected, so picking it just flies home.
    private func pick(_ location: StarLocation) {
        selection = location.starID
        flight = FlightRequest(position: location.position, serial: (flight?.serial ?? 0) + 1)
        isSearching = false
    }
}

