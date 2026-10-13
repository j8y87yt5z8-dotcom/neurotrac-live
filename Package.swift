// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NeuroTracLive",
    platforms: [.macOS(.v13)],
    targets: [
        // NeuroTrac protocol: packets, CRC, decoding (no UI, testable)
        .target(name: "NeuroTracCore"),
        // Mac application (SwiftUI)
        .executableTarget(name: "NeuroTracLive", dependencies: ["NeuroTracCore"]),
        .testTarget(name: "NeuroTracCoreTests", dependencies: ["NeuroTracCore"]),
    ]
)
