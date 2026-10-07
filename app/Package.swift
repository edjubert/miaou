// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeGod",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VibeGod",
            path: "Sources/VibeGod",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VibeGodTests",
            dependencies: ["VibeGod"],
            path: "Sources/VibeGodTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
