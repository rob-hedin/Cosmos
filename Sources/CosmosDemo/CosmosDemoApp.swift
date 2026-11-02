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
@main
struct CosmosDemoApp: App {
    private let options = DemoOptions(arguments: CommandLine.arguments)

    init() {
        #if os(macOS)
        // Run from the command line there is no app bundle, so ask to be a regular app with a Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        #endif
    }

    var body: some Scene {
        StarFieldScene(title: "Cosmos", focus: options.focus, route: options.route)
    }
}

/// The demo's command-line options.
struct DemoOptions {
    var focus: StarFieldFocus?
    var route: [String] = []

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
        if let list = value(after: "--route") {
            route = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }
}
