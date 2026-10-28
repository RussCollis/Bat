// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "bat-installer", targets: ["Bat"]),
        .library(name: "BatCore", targets: ["BatCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "BatCore",
            dependencies: []
        ),
        .executableTarget(
            name: "Bat",
            dependencies: [
                "BatCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .testTarget(
            name: "BatTests",
            dependencies: [
                "BatCore",
            ]
        ),
    ]
)
