// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Cosmos",
    platforms: [
        .macOS("27.0"),
        .iOS("27.0"),
    ],
    products: [
        .library(name: "StarCatalog", targets: ["StarCatalog"]),
    ],
    targets: [
        .target(
            name: "StarCatalog",
            resources: [.copy("Resources/stars.csv")]
        ),
        .testTarget(
            name: "StarCatalogTests",
            dependencies: ["StarCatalog"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
