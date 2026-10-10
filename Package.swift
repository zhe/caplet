// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TinyTiler",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "TilerCore"),
        .executableTarget(name: "TinyTiler", dependencies: ["TilerCore"]),
        .testTarget(name: "TilerCoreTests", dependencies: ["TilerCore"]),
    ]
)
