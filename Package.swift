// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Caplet",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CapletCore"),
        .executableTarget(name: "Caplet", dependencies: ["CapletCore"]),
        .testTarget(name: "CapletCoreTests", dependencies: ["CapletCore"]),
    ]
)
