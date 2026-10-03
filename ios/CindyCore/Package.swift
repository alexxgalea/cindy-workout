// swift-tools-version: 5.9
import PackageDescription

/// The parts of Cindy that have nothing to do with a camera: rep counting, the Cindy
/// progression, records and levels. Kept free of UIKit and Vision so it builds and tests on
/// macOS, which is where its behaviour is actually verified.
///
/// Checks are an executable rather than an XCTest target on purpose: XCTest ships with Xcode,
/// and this has to be verifiable from the command line tools alone. `swift run CindyCoreChecks`
/// exits non-zero on failure, so it drops into CI unchanged.
let package = Package(
    name: "CindyCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "CindyCore", targets: ["CindyCore"]),
        .executable(name: "CindyCoreChecks", targets: ["CindyCoreChecks"])
    ],
    targets: [
        .target(name: "CindyCore"),
        // Synthetic bodies and a rig that drives an engine with them: shared by the tests and,
        // later, by the app's replay source, so neither needs a camera.
        .target(name: "CindyFixtures", dependencies: ["CindyCore"]),
        .executableTarget(name: "CindyCoreChecks", dependencies: ["CindyCore", "CindyFixtures"])
    ]
)
