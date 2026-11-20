// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TrajetCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TrajetCore", targets: ["TrajetCore"]),
    ],
    targets: [
        .target(name: "TrajetCore"),
        .testTarget(name: "TrajetCoreTests", dependencies: ["TrajetCore"]),
    ]
)
