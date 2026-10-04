// swift-tools-version: 5.9
import PackageDescription

/// Scores Cindy's recorded clips with Apple's Vision, in the shape `tools/video_regression/
/// run_batch.py` scores them with MoveNet, so the two can be compared clip by clip.
///
/// `ClipScoring` is Foundation and `CindyCore` only (the engine, the scenario files, the report),
/// so it is tested on Linux like `CindyCore`. Decoding the video and running Vision need
/// AVFoundation and Vision, which exist on macOS: the `cindy-clips` tool is where they meet, and
/// on any other platform it says so and skips every scenario.
let package = Package(
    name: "CindyClips",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "cindy-clips", targets: ["cindy-clips"])
    ],
    dependencies: [
        .package(path: "../CindyCore")
    ],
    targets: [
        .target(
            name: "ClipScoring",
            dependencies: [.product(name: "CindyCore", package: "CindyCore")]),
        .executableTarget(
            name: "cindy-clips",
            dependencies: [
                "ClipScoring",
                .product(name: "CindyCore", package: "CindyCore"),
                .product(name: "CindyVision", package: "CindyCore")
            ]),
        .testTarget(
            name: "ClipScoringTests",
            dependencies: [
                "ClipScoring",
                .product(name: "CindyCore", package: "CindyCore"),
                .product(name: "CindyFixtures", package: "CindyCore")
            ])
    ]
)
