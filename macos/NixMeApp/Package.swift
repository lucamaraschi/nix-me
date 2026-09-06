// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "NixMeApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NixMeApp", targets: ["NixMeApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "NixMeApp",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(name: "NixMeAppTests", dependencies: ["NixMeApp"])
    ]
)
