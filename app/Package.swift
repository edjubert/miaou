// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Miaou",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Miaou",
            path: "Sources/Miaou",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MiaouTests",
            dependencies: ["Miaou"],
            path: "Sources/MiaouTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
