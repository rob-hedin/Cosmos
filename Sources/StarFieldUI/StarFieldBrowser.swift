import StarCatalog
import SwiftUI

/// A star field with built-in controls: search, filters, a route builder, star names, reference
/// rings and the size mode. `StarFieldScene` uses this; use it directly to get the same controls
/// in your own layout. Pass `showsRouteBuilder: false` to leave out the route builder,
/// `showsConstellationsButton: false` to leave out the constellations toggle, or
/// `showsToolbar: false` to leave out the controls altogether. Pass `planetarySystems` to choose
/// which stars offer a planetary system on their info card; it defaults to the built-in Solar System.
public struct StarFieldBrowser: View {
    @State private var sizeMode: StarSizeMode
    @State private var showsLabels = true
    @State private var showsRings = true
    @State private var showsConstellations: Bool
    @State private var selection: Star.ID?
    @State private var filter: StarFilter
    @State private var isSearching = false
    @State private var showsFilters = false
    @State private var flight: FlightRequest?
    @State private var controlsFrame: CGRect?
    @State private var searchFrame: CGRect?
    /// The route the user is building. Nil until they add a stop, so a route passed in shows
    /// until then; the first stop starts a new route in its place.
    @State private var builtRoute: [StarLocation]?
    @State private var isBuildingRoute = false
    /// A stop that's already on the route, waiting for the user to remove it or add it again.
    @State private var repeatedStop: StarLocation?
    private let customCatalog: StarCatalog?
    private let focus: StarFieldFocus?
    private let route: [String]
    private let showsToolbar: Bool
    private let showsRouteBuilder: Bool
    private let showsConstellationsButton: Bool
    private let planetarySystems: PlanetarySystemDirectory

    /// Opens on `focus` if given, otherwise frames `route`, showing the stars `filter` lets
    /// through; see ``StarFieldView``. Shows the bundled catalog unless you pass one.
    public init(
        catalog: StarCatalog? = nil,
        sizeMode: StarSizeMode = .luminosity,
        focus: StarFieldFocus? = nil,
        route: [String] = [],
        filter: StarFilter = .all,
        showsConstellations: Bool = false,
        showsToolbar: Bool = true,
        showsRouteBuilder: Bool = true,
        showsConstellationsButton: Bool = true,
        planetarySystems: PlanetarySystemDirectory = .builtIn
    ) {
        customCatalog = catalog
        _sizeMode = State(initialValue: sizeMode)
        self.focus = focus
        self.route = route
        _filter = State(initialValue: filter)
        _showsConstellations = State(initialValue: showsConstellations)
        self.showsToolbar = showsToolbar
        self.showsRouteBuilder = showsRouteBuilder
        self.showsConstellationsButton = showsConstellationsButton
        self.planetarySystems = planetarySystems
    }

    private var catalog: StarCatalog? {
        customCatalog ?? (try? StarFieldView.bundledCatalog.get())
    }

    private var starField: StarFieldView {
        if let customCatalog {
            StarFieldView(
                catalog: customCatalog, sizeMode: sizeMode, selection: $selection, showsLabels: showsLabels,
                showsReferenceRings: showsRings, showsConstellations: showsConstellations, focus: focus,
                route: route, filter: filter, planetarySystems: planetarySystems
            )
        } else {
            StarFieldView(
                sizeMode: sizeMode, selection: $selection, showsLabels: showsLabels, showsReferenceRings: showsRings,
                showsConstellations: showsConstellations, focus: focus, route: route, filter: filter,
                planetarySystems: planetarySystems
            )
        }
    }

    private var isEditingRoute: Bool { showsToolbar && showsRouteBuilder && isBuildingRoute }

    private var routeEditing: RouteEditing {
        var editing = RouteEditing(stops: builtRoute)
        editing.onClear = clearBuiltRoute
        if isEditingRoute {
            if (builtRoute ?? []).isEmpty { editing.hint = Self.addStopsHint }
            editing.onStarClick = addClickedStar
            if builtRoute?.isEmpty == false { editing.onUndo = undoStop }
        }
        return editing
    }

    private func addClickedStar(_ star: Star?) {
        selection = star?.id
        if let star { addStop(StarLocation(name: star.name, position: star.position, starID: star.id)) }
    }

    private func undoStop() {
        _ = builtRoute?.popLast()
    }

    private func resetBuiltRoute() {
        builtRoute = nil
        repeatedStop = nil
    }

    private func clearBuiltRoute() {
        builtRoute = []
    }

    #if os(macOS)
    private static let addStopsHint = "Click stars to add stops"
    #else
    private static let addStopsHint = "Tap stars to add stops"
    #endif

    public var body: some View {
        starField
        .flying(to: flight)
        .editingRoute(routeEditing)
        .starFieldLabelObstacles([controlsFrame, searchFrame].compactMap { $0 })
        .confirmationDialog(
            repeatedStop.map { "\($0.name) is already on the route" } ?? "",
            isPresented: Binding { repeatedStop != nil } set: { if !$0 { repeatedStop = nil } },
            titleVisibility: .visible,
            presenting: repeatedStop
        ) { stop in
            Button("Remove from Route", role: .destructive) { builtRoute?.removeAll { $0 == stop } }
            Button("Add Again") { builtRoute?.append(stop) }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .topTrailing) {
            if showsToolbar {
                toolbar.onDisappear {
                    controlsFrame = nil
                    searchFrame = nil
                }
            }
        }
        // A new route or catalog from the app replaces whatever the user built.
        .onChange(of: route) { resetBuiltRoute() }
        .onChange(of: customCatalog) { resetBuiltRoute() }
    }

    private var toolbar: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Where the full controls don't fit, as on a phone, they step down to fewer, smaller ones.
            ViewThatFits(in: .horizontal) {
                controls(layout: .full)
                controls(layout: .compact)
                controls(layout: .icons)
                controls(layout: .minimal)
            }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { controlsFrame = $0 }
            if isSearching, let catalog {
                StarSearchPanel(catalog: catalog, onPick: pick) { isSearching = false }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { searchFrame = $0 }
                    .onDisappear { searchFrame = nil }
            }
        }
        .padding()
    }

    /// How much room the toolbar has, from widest to narrowest. `ViewThatFits` tries them in this order,
    /// so each one only shows where the wider ones don't fit. `full` and `compact` are the layouts the
    /// toolbar has always had; `icons` and `minimal` are only used where neither of those fits.
    private enum ToolbarLayout {
        /// Every control with its title, and the segmented Luminosity/Radius picker.
        case full
        /// The toggles as icons, and the segmented Luminosity/Radius picker.
        case compact
        /// Every control as an icon. The size picker becomes an icon menu.
        case icons
        /// Search, Route and Filters as icons, plus one "View" menu holding Names, Rings, Constellations and Size.
        case minimal
    }

    private func controls(layout: ToolbarLayout) -> some View {
        HStack(spacing: 10) {
            Toggle("Search", systemImage: "magnifyingglass", isOn: $isSearching)
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .keyboardShortcut("f", modifiers: .command)
                .help("Find a star (⌘F)")
            if showsRouteBuilder {
                Toggle("Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up", isOn: $isBuildingRoute)
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                    .help(isBuildingRoute ? "Stop adding stops" : "Build a route: \(Self.addStopsHint.lowercased())")
            }
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
            switch layout {
            case .full:
                toggles
                segmentedSizePicker
            case .compact:
                toggles.labelStyle(.iconOnly)
                segmentedSizePicker
            case .icons:
                toggles.labelStyle(.iconOnly)
                sizeMenu
            case .minimal:
                viewMenu
            }
        }
        .padding(8)
        .background(.regularMaterial, in: .capsule)
    }

    private static let sizeHelp = "Size stars by luminosity, or by estimated physical radius"

    /// The bare Luminosity/Radius choice, for the segmented picker and the menus to style.
    private var sizePicker: some View {
        Picker("Size", selection: $sizeMode) {
            Text("Luminosity").tag(StarSizeMode.luminosity)
            Text("Radius").tag(StarSizeMode.estimatedRadius)
        }
    }

    private var segmentedSizePicker: some View {
        sizePicker
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(Self.sizeHelp)
    }

    /// The size choice as one icon, for when the segmented picker doesn't fit.
    private var sizeMenu: some View {
        Menu {
            sizePicker
        } label: {
            Label(
                sizeMode == .luminosity ? "Size: Luminosity" : "Size: Radius",
                systemImage: sizeMode == .luminosity ? "sun.max" : "circle.circle"
            )
            .labelStyle(.iconOnly)
        }
        .fixedSize()
        .help(Self.sizeHelp)
    }

    /// Everything but Search, Route and Filters behind one icon, for the narrowest layout.
    private var viewMenu: some View {
        Menu {
            toggleItems
            Divider()
            sizePicker
        } label: {
            Label("View", systemImage: "eye")
                .labelStyle(.iconOnly)
        }
        .fixedSize()
        .help("Names, rings, constellations and star size")
    }

    private var toggles: some View {
        toggleItems.toggleStyle(.button)
    }

    /// The Names, Rings and Constellations switches, in whatever style the surrounding view gives them.
    private var toggleItems: some View {
        Group {
            Toggle("Names", systemImage: "textformat", isOn: $showsLabels)
                .help("Star names")
            Toggle("Rings", systemImage: "circle.dashed", isOn: $showsRings)
                .help("Rings at 50, 100 and 200 light years from the Sun")
            if showsConstellationsButton {
                Toggle("Constellations", systemImage: "star", isOn: $showsConstellations)
                    .help("Constellation figures as seen from Earth, on a sphere 200 ly around the Sun")
            }
        }
    }

    /// Selects the star and glides to it. Picking the Sun selects it as `Star.sunID` and flies home.
    private func pick(_ location: StarLocation) {
        if isEditingRoute { addStop(location) }
        selection = location.starID ?? Star.sunID
        flight = FlightRequest(position: location.position, serial: (flight?.serial ?? 0) + 1)
        isSearching = false
    }

    /// Adds a stop. The first one starts a new route, replacing any route passed in; a star
    /// that's already on the route asks whether to remove it or visit it again.
    private func addStop(_ stop: StarLocation) {
        guard var stops = builtRoute else {
            builtRoute = [stop]
            return
        }
        if stops.contains(stop) {
            repeatedStop = stop
        } else {
            stops.append(stop)
            builtRoute = stops
        }
    }
}
