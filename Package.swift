// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Feather",
    platforms: [.macOS("15.4")],
    targets: [
        .executableTarget(name: "FeatherA", path: "Sources/FeatherA"),
        .testTarget(name: "FeatherATests", dependencies: ["FeatherA"], path: "Tests/FeatherATests"),
    ]
)
