// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.
// swift-tools-version:5.5

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
        ),
        .executableTarget(
            name: "NetifyExamples",
            dependencies: ["Netify"],
            path: "Examples"
        )
    ]
)
