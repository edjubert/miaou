// swift-tools-version: 6.0
import PackageDescription
import Foundation

let appDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let appSources = try FileManager.default.contentsOfDirectory(
    atPath: appDirectory.appendingPathComponent("Sources/Miaou").path
).filter { $0.hasSuffix(".swift") }.sorted().map { "Sources/Miaou/\($0)" }

let package = Package(
    name: "Miaou",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Miaou",
            path: ".",
            exclude: ["Sources/MiaouTests", "Widget", "Info.plist", "Miaou.entitlements",
                      "Makefile", "README.md", "Resources", "scripts", "build-app.py", "Miaou.app"],
            sources: appSources + ["Shared"],
            resources: [.process("Sources/Miaou/Resources")],
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
