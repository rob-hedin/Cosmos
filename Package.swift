// swift-tools-version: 6.4
import PackageDescription

// StarCatalog is pure Swift and builds everywhere, including Linux CI.
// The Metal renderer, UI and demo app need Apple platforms.
var products: [Product] = [
    .library(name: "StarCatalog", targets: ["StarCatalog"]),
]

var targets: [Target] = [
    .target(
        name: "StarCatalog",
        resources: [.copy("Resources/stars.csv")]
    ),
    .testTarget(
        name: "StarCatalogTests",
        dependencies: ["StarCatalog"]
    ),
]

#if !os(Linux)
products += [
    .library(name: "StarRenderer", targets: ["StarRenderer"]),
    .library(name: "StarFieldUI", targets: ["StarFieldUI"]),
    .executable(name: "CosmosDemo", targets: ["CosmosDemo"]),
]

targets += [
    .target(
        name: "StarRenderer",
        dependencies: ["StarCatalog"]
    ),
    .target(
        name: "StarFieldUI",
        dependencies: ["StarCatalog", "StarRenderer"]
    ),
    .executableTarget(
        name: "CosmosDemo",
        dependencies: ["StarFieldUI"]
    ),
    .testTarget(
        name: "StarRendererTests",
        dependencies: ["StarRenderer"]
    ),
]
#endif

let package = Package(
    name: "Cosmos",
    platforms: [
        .macOS("27.0"),
        .iOS("27.0"),
    ],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6]
)
