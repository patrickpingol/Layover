// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenDropKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenDropCore", targets: ["OpenDropCore"]),
        .library(name: "OpenDropUI", targets: ["OpenDropUI"]),
    ],
    targets: [
        .target(name: "OpenDropCore"),
        .target(name: "OpenDropUI", dependencies: ["OpenDropCore"]),
        .testTarget(name: "OpenDropCoreTests", dependencies: ["OpenDropCore"]),
        .testTarget(name: "OpenDropUITests", dependencies: ["OpenDropUI"]),
    ]
)
