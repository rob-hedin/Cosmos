#if os(macOS)
import AppKit
#endif
import StarFieldUI
import SwiftUI

/// Demo app: `swift run CosmosDemo` opens a window with every star within 200 light years.
@main
struct CosmosDemoApp: App {
    init() {
        #if os(macOS)
        // Run from the command line there is no app bundle, so ask to be a regular app with a Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        #endif
    }

    var body: some Scene {
        StarFieldScene(title: "Cosmos")
    }
}
