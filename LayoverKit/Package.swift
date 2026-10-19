// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LayoverKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LayoverCore", targets: ["LayoverCore"]),
        .library(name: "LayoverUI", targets: ["LayoverUI"]),
    ],
    targets: [
        .target(name: "LayoverCore"),
        .target(name: "LayoverUI", dependencies: ["LayoverCore"]),
        .testTarget(name: "LayoverCoreTests", dependencies: ["LayoverCore"]),
        .testTarget(name: "LayoverUITests", dependencies: ["LayoverUI"]),
    ]
)
