import XCTest
@testable import CindyCore

/// What the App Store reads out of the project, held to what the app does.
///
/// No Kotlin test: Android's equivalents are `PlayListingTest` and `PlayPolicyTest`, which hold the
/// Play listing, and the store checks that are not the listing's (the privacy manifest, the
/// encryption declaration, the version, the icon) have no Android counterpart. These read the
/// project's own files, so a manifest that forgot an API the code uses, or an icon with an alpha
/// channel, fails here and not in App Store Connect after an archive and an upload.
final class StoreMetadataTests: XCTestCase {

    private let ios: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func text(_ path: String) throws -> String {
        try String(contentsOf: ios.appendingPathComponent(path), encoding: .utf8)
    }

    private func manifest(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: ios.appendingPathComponent(path))
        return try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func accessed(_ manifest: [String: Any]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for entry in (manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]) ?? [] {
            if let type = entry["NSPrivacyAccessedAPIType"] as? String {
                out[type] = (entry["NSPrivacyAccessedAPITypeReasons"] as? [String]) ?? []
            }
        }
        return out
    }

    private let withoutStrava = "CindyTracker/PrivacyInfo.xcprivacy"
    private let withStrava = "Config/PrivacyInfo.strava.xcprivacy"

    // ---- the privacy manifest ---------------------------------------------------------------

    /// The required-reason APIs each category of the manifest stands for, as they are written in code.
    private let apis: [String: [String]] = [
        "NSPrivacyAccessedAPICategoryUserDefaults": ["UserDefaults"],
        "NSPrivacyAccessedAPICategorySystemBootTime": ["systemUptime", "mach_absolute_time"],
        "NSPrivacyAccessedAPICategoryFileTimestamp": [
            "creationDate", "modificationDate", "fileModificationDate", "NSFileCreationDate",
            "NSFileModificationDate", "contentModificationDateKey", "creationDateKey", "attributesOfItem",
            "getattrlist", "fstat(", "lstat("],
        "NSPrivacyAccessedAPICategoryDiskSpace": [
            "volumeAvailableCapacity", "systemFreeSize", "systemSize", "statfs", "attributesOfFileSystem"],
        "NSPrivacyAccessedAPICategoryActiveKeyboards": ["activeInputModes"]
    ]

    /// Every Swift file the app is built from, outside its tests.
    private func sources() throws -> [(path: String, text: String)] {
        var found: [(String, String)] = []
        for folder in ["CindyCore/Sources", "CindyTracker", "CindyCore/Sources/CindyVision"] {
            let root = ios.appendingPathComponent(folder)
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in files where url.pathExtension == "swift" {
                found.append((url.path, try String(contentsOf: url, encoding: .utf8)))
            }
        }
        XCTAssertGreaterThan(found.count, 100, "the app's sources were not found")
        return found
    }

    /// the manifest names every required-reason API the code uses, and none it does not
    func testTheManifestNamesEveryRequiredReasonApiTheCodeUsesAndNoneItDoesNot() throws {
        let code = try sources()
        let declared = accessed(try manifest(withoutStrava))
        for (category, symbols) in apis {
            let users = code.filter { file in symbols.contains { file.text.contains($0) } }.map { $0.path }
            if users.isEmpty {
                XCTAssertNil(declared[category], "\(category) is declared and no code uses it")
            } else {
                XCTAssertNotNil(declared[category],
                                "\(category) is used (\(users.map { ($0 as NSString).lastPathComponent }.sorted())) and not declared")
            }
        }
        XCTAssertEqual(Set(declared.keys), ["NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPICategorySystemBootTime"],
                       "the audit found these two, and a third needs a reason written down with it")
    }

    /// each category carries a reason Apple allows for what the code does with it
    func testEachCategoryCarriesAReasonAppleAllowsForWhatTheCodeDoesWithIt() throws {
        let declared = accessed(try manifest(withoutStrava))
        // CA92.1: read and written by the app itself. 35F9.1: time elapsed between events in the app.
        XCTAssertEqual(declared["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
        XCTAssertEqual(declared["NSPrivacyAccessedAPICategorySystemBootTime"], ["35F9.1"])
    }

    /// the system uptime is never sent or stored, which is what 35F9.1 allows
    func testTheSystemUptimeIsNeverSentOrStoredWhichIsWhat35F91Allows() throws {
        for file in try sources() where file.text.contains("systemUptime") {
            for line in file.text.split(separator: "\n") where line.contains("systemUptime") {
                XCTAssertFalse(line.contains("UserDefaults") || line.contains("JSONSerialization") || line.contains("HttpRequest"),
                               "\(file.path): \(line)")
            }
        }
        XCTAssertFalse(try text("CindyCore/Sources/CindyCore/StravaPayload.swift").contains("systemUptime"))
    }

    /// no build tracks, and a build without Strava collects nothing
    func testNoBuildTracksAndABuildWithoutStravaCollectsNothing() throws {
        for path in [withoutStrava, withStrava] {
            let m = try manifest(path)
            XCTAssertEqual(m["NSPrivacyTracking"] as? Bool, false, path)
            XCTAssertEqual((m["NSPrivacyTrackingDomains"] as? [Any])?.count, 0, path)
        }
        XCTAssertEqual((try manifest(withoutStrava)["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
    }

    /// a build with Strava declares exactly what an upload sends: health and fitness, for the app's function, not linked, not tracking
    func testABuildWithStravaDeclaresExactlyWhatAnUploadSends() throws {
        let m = try manifest(withStrava)
        let collected = try XCTUnwrap(m["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertEqual(Set(collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String }),
                       ["NSPrivacyCollectedDataTypeHealth", "NSPrivacyCollectedDataTypeFitness"])
        for entry in collected {
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, false)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypePurposes"] as? [String],
                           ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        }
        // The same API declarations as the build without it: only the collection differs.
        XCTAssertEqual(accessed(m), accessed(try manifest(withoutStrava)))
    }

    // ---- the project ------------------------------------------------------------------------

    /// the project is version 1.0.0, build 1
    func testTheProjectIsVersion100Build1() throws {
        let project = try text("project.yml")
        XCTAssertTrue(project.contains("MARKETING_VERSION: \"1.0.0\""))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION: \"1\""))
    }

    /// the encryption declaration says the app's only encryption is exempt, because it is HTTPS only
    func testTheEncryptionDeclarationSaysTheAppsOnlyEncryptionIsExemptBecauseItIsHttpsOnly() throws {
        XCTAssertTrue(try text("project.yml").contains("ITSAppUsesNonExemptEncryption: false"))
        // Nothing in the app does its own cryptography, which would not be exempt.
        for file in try sources() {
            for symbol in ["import CryptoKit", "import CommonCrypto", "SecKeyCreate", "CCCrypt", "SymmetricKey"] {
                XCTAssertFalse(file.text.contains(symbol), "\(file.path) uses \(symbol)")
            }
        }
        // And every address it sends anything to is https.
        for file in try sources() {
            for line in file.text.split(separator: "\n") where line.contains("\"http://") {
                XCTFail("\(file.path) has a plain-http address: \(line)")
            }
        }
    }

    /// the icon is a 1024 pixel square PNG with no alpha channel, and the catalog names it
    func testTheIconIsA1024PixelSquarePngWithNoAlphaChannelAndTheCatalogNamesIt() throws {
        let png = try Data(contentsOf: ios.appendingPathComponent("CindyTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        func be(_ at: Int) -> Int { png[at...at + 3].reduce(0) { $0 << 8 | Int($1) } }
        XCTAssertEqual(be(16), 1024)
        XCTAssertEqual(be(20), 1024)
        XCTAssertEqual(png[24], 8, "bit depth")
        XCTAssertEqual(png[25], 2, "colour type 2 is RGB: 4 and 6 have an alpha channel, which the App Store refuses")

        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try Data(contentsOf: ios.appendingPathComponent("CindyTracker/Assets.xcassets/AppIcon.appiconset/Contents.json")))
            as? [String: Any])
        let images = try XCTUnwrap(catalog["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0]["filename"] as? String, "AppIcon.png")
        XCTAssertEqual(images[0]["size"] as? String, "1024x1024")
        XCTAssertTrue(try text("project.yml").contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"))
        // The same picture as the one rendered from the store's own source.
        let stored = try Data(contentsOf: ios.deletingLastPathComponent().appendingPathComponent("appstore/graphics/icon.png"))
        XCTAssertEqual(png, stored, "the app icon is not the store's icon: render again and copy it")
    }

    /// the privacy policy the app opens is the iPhone page, which is not Android's
    func testThePrivacyPolicyTheAppOpensIsTheIphonePageWhichIsNotAndroids() {
        XCTAssertEqual(AppLinks.privacyPolicy, "https://alexxgalea.github.io/cindy-privacy/ios/")
        XCTAssertTrue(AppLinks.privacyPolicy.hasPrefix("https://"))
    }
}
