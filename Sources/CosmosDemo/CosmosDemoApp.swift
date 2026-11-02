#if os(macOS)
import AppKit
#endif
import StarFieldUI
import SwiftUI

/// Demo app: `swift run CosmosDemo` opens a window with every star within 200 light years.
///
/// Options:
/// - `--star NAME [--span LY]` opens centered on a star, `LY` light years across (default 20).
/// - `--route "Sol, Alpha Centauri, Sirius"` draws a route between the stars and frames it.
/// - `--constellations` draws the constellation figures; `--no-constellations-button` hides its toggle.
/// - `--no-route-builder` leaves out the route builder; `--no-toolbar` leaves out all the controls.
/// - `--solar-system` also opens the Solar System in its own window. On macOS, Planetary Systems >
///   Show Solar System (⇧⌘S) opens it or brings it to the front.
///
/// Click the Sun, then "Show planetary system" on its info card, to open the Solar System from the
/// star view.
@main
struct CosmosDemoApp: App {
    private let options = DemoOptions(arguments: CommandLine.arguments)

    init() {
        #if os(macOS)
        // Run from the command line there is no app bundle, so ask to be a regular app with a Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        if options.showsSolarSystem {
            // The windows can only open once the app has finished launching.
            NotificationCenter.default.addObserver(
                forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { Self.showSolarSystem() }
            }
        }
        #endif
    }

    private var starField: StarFieldScene {
        StarFieldScene(
            title: "Cosmos", focus: options.focus, route: options.route,
            showsConstellations: options.showsConstellations,
            showsToolbar: options.showsToolbar, showsRouteBuilder: options.showsRouteBuilder,
            showsConstellationsButton: options.showsConstellationsButton
        )
    }

    var body: some Scene {
        #if os(macOS)
        starField
            .commands {
                CommandMenu("Planetary Systems") {
                    Button("Show Solar System", action: Self.showSolarSystem)
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                        .disabled(PlanetarySystemDirectory.builtIn.systems.isEmpty)
                }
            }
        #else
        starField
        #endif
    }

    #if os(macOS)
    /// Opens the built-in Solar System in its own window, or brings its window to the front.
    private static func showSolarSystem() {
        guard let solarSystem = PlanetarySystemDirectory.builtIn.systems.first else { return }
        PlanetarySystemWindow.open(system: solarSystem)
    }
    #endif
}

/// The demo's command-line options.
struct DemoOptions {
    var focus: StarFieldFocus?
    var route: [String] = []
    var showsToolbar = true
    var showsConstellations = false
    var showsConstellationsButton = true
    var showsRouteBuilder = true
    var showsSolarSystem = false

    init(arguments: [String]) {
        /// The value after `flag`, unless it's missing or is another option.
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            let value = arguments[index + 1]
            return value.hasPrefix("-") ? nil : value
        }
        if let star = value(after: "--star") {
            let span = value(after: "--span").flatMap(Double.init).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 20
            focus = StarFieldFocus(star: star, span: span)
        }
        showsConstellations = arguments.contains("--constellations")
        showsConstellationsButton = !arguments.contains("--no-constellations-button")
        showsToolbar = !arguments.contains("--no-toolbar")
        showsRouteBuilder = !arguments.contains("--no-route-builder")
        showsSolarSystem = arguments.contains("--solar-system")
        if let list = value(after: "--route") {
            route = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }
}
