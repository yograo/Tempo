// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TempoCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "TempoCore", targets: ["TempoCore"])],
    targets: [
        .target(name: "TempoCore", path: "Tempo/Core"),
        .testTarget(name: "TempoCoreTests", dependencies: ["TempoCore"], path: "Tests/TempoCoreTests")
    ]
)
