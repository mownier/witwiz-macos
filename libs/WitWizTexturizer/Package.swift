// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WitWizTexturizer",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "WitWizTexturizerCore",
            targets: ["WitWizTexturizerCore"]
        ),
        .executable(
            name: "witwiztx",
            targets: ["witwiztx"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "WitWizTexturizerCore",
            dependencies: [],
            linkerSettings: [
               .linkedFramework("CoreGraphics"),
               .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "witwiztx",
            dependencies: [
                "WitWizTexturizerCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)

