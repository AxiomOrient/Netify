// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription // Keep this line

let package = Package(
    name: "Netify", // Change package name
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "Netify",
            targets: ["Netify"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Netify",
            dependencies: []
        ),
        .testTarget(
            name: "NetifyTests",
            dependencies: ["Netify"]
        )
    ]
)
