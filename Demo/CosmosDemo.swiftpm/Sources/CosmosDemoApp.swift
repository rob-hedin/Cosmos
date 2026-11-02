import StarFieldUI
import SwiftUI

/// Demo app for iPhone and iPad: the star field, with the Solar System one tap away from the Sun's
/// info card. Launch with `--solar-system` to start in the Solar System instead.
@main
struct CosmosDemoApp: App {
    private let showsSolarSystem = ProcessInfo.processInfo.arguments.contains("--solar-system")

    var body: some Scene {
        WindowGroup("Cosmos") {
            if showsSolarSystem {
                PlanetarySystemView()
            } else {
                StarFieldBrowser()
            }
        }
    }
}
