// swift-tools-version: 5.10

import Foundation
import PackageDescription

let localNixBuild = ProcessInfo.processInfo.environment["NIX_ME_DISABLE_SPARKLE"] == "1"

let package = Package(
    name: "NixMeApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NixMeApp", targets: ["NixMeApp"])
    ],
    dependencies: localNixBuild ? [] : [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "NixMeApp",
            dependencies: localNixBuild ? [] : [.product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(
            name: "NixMeAppTests",
            dependencies: ["NixMeApp"],
            resources: [.process("Fixtures")]
        )
    ]
)
