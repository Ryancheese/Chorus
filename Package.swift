// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StereoSync",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "StereoSyncCore", targets: ["StereoSyncCore"])
    ],
    targets: [
        .target(
            name: "StereoSyncCore",
            path: "Sources/StereoSyncCore"
        ),
        .testTarget(
            name: "StereoSyncCoreTests",
            dependencies: ["StereoSyncCore"],
            path: "Tests/StereoSyncCoreTests"
        )
    ]
)
