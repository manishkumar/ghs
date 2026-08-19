// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ghs",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ghs",
            path: "Sources/ghs",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ghsTests",
            dependencies: ["ghs"],
            path: "Tests/ghsTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
