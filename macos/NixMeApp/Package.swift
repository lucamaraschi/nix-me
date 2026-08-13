// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "NixMeApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NixMeApp", targets: ["NixMeApp"])
    ],
    targets: [
        .executableTarget(name: "NixMeApp"),
        .testTarget(name: "NixMeAppTests", dependencies: ["NixMeApp"])
    ]
)
