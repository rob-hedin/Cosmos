// swift-tools-version: 6.0

import AppleProductTypes
import Foundation
import PackageDescription

// Cosmos demo app for iPhone and iPad (a Swift Playgrounds-style app package).
// It depends on the repo's own package, two folders up. See "Demo" in the README for how to
// build it with xcodebuild.

// A package that is added by path is known by the lowercased name of its folder, which is the
// name of the checkout ("cosmos", or the name of a worktree), so work it out rather than assume it.
let repositoryFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // CosmosDemo.swiftpm
    .deletingLastPathComponent() // Demo
    .deletingLastPathComponent() // the repository
let cosmosIdentity = repositoryFolder.lastPathComponent.lowercased()

let package = Package(
    name: "CosmosDemo",
    platforms: [
        .iOS("27.0"),
    ],
    products: [
        .iOSApplication(
            name: "CosmosDemo",
            targets: ["CosmosDemoApp"],
            bundleIdentifier: "com.rob-hedin.CosmosDemo",
            displayVersion: "1.0",
            bundleVersion: "1",
            supportedDeviceFamilies: [
                .pad,
                .phone,
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad])),
            ]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "CosmosDemoApp",
            dependencies: [
                .product(name: "StarFieldUI", package: cosmosIdentity),
            ],
            path: "Sources"
        ),
    ],
    swiftLanguageModes: [.v6]
)
