// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Chorus",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ChorusCore", targets: ["ChorusCore"])
    ],
    targets: [
        .target(
            name: "ChorusCore",
            path: "Sources/ChorusCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ChorusCoreTests",
            dependencies: ["ChorusCore"],
            path: "Tests/ChorusCoreTests"
        )
    ]
)
