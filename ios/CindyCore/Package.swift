// swift-tools-version: 5.9
import PackageDescription

/// The parts of Cindy that have nothing to do with a camera: rep counting, the Cindy
/// progression, records and levels. Foundation only, so it builds and tests on Linux as well as
/// on macOS, which is where the agent that ports it works.
///
/// Run the tests with `tools/ios/swift.sh test` on Linux, or `swift test --package-path
/// ios/CindyCore` anywhere Swift is installed. They are XCTest, so Xcode runs them unchanged.
let package = Package(
    name: "CindyCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "CindyCore", targets: ["CindyCore"]),
        // For the app's debug builds, which replay a scripted body in the simulator.
        .library(name: "CindyFixtures", targets: ["CindyFixtures"])
    ],
    targets: [
        .target(name: "CindyCore"),
        // Synthetic bodies and a rig that drives an engine with them: shared by the tests and,
        // later, by the app's replay source, so neither needs a camera.
        .target(name: "CindyFixtures", dependencies: ["CindyCore"]),
        .testTarget(name: "CindyCoreTests", dependencies: ["CindyCore", "CindyFixtures"])
    ]
)
