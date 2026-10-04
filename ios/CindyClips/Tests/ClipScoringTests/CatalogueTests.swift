import XCTest
import CindyCore
import ClipScoring

/// The scenario files in `tests/scenarios/` are read by three runners. This one has to read all
/// of them, and read in each what the other two read.
final class CatalogueTests: XCTestCase {

    private static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    private func catalogue(_ name: String) throws -> [Scenario] {
        var warnings: [String] = []
        let scenarios = try Catalogue.load([Self.root.appendingPathComponent("tests/scenarios/\(name).json")], warnings: &warnings)
        XCTAssertEqual(warnings, [], name)
        return scenarios
    }

    private func everyScenario() throws -> [Scenario] {
        let dir = Self.root.appendingPathComponent("tests/scenarios")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }.sorted()
        XCTAssertGreaterThanOrEqual(names.count, 5)
        return try names.flatMap { try catalogue(String($0.dropLast(5))) }
    }

    func testEveryCatalogueInTheRepositoryIsRead() throws {
        let all = try everyScenario()
        XCTAssertGreaterThanOrEqual(all.count, 15)
        XCTAssertEqual(Set(all.map { $0.id }).count, all.count, "scenario ids are unique across catalogues")
    }

    func testEveryScenarioNamesSomethingThisToolCanScore() throws {
        for scenario in try everyScenario() {
            XCTAssertTrue(scenario.isCindy || MovementNames.exercise(scenario.exercise) != nil,
                          "\(scenario.id): \(scenario.exercise)")
            if let pull = scenario.pull {
                XCTAssertNotNil(MovementNames.pullVariant(pull), "\(scenario.id): \(pull)")
            }
            XCTAssertFalse(scenario.video.hasPrefix("/"), "\(scenario.id) names a clip by an absolute path")
            if !scenario.isCindy {
                XCTAssertNotNil(scenario.expectedReps, "\(scenario.id) has no expected count")
            }
        }
    }

    func testTheCindyClipKeepsItsControlsAndItsLabels() throws {
        let scenario = try XCTUnwrap(try catalogue("cindy").first)
        XCTAssertTrue(scenario.isCindy)
        XCTAssertEqual(scenario.setup, "skip")
        XCTAssertEqual(scenario.skipTo, [.init(atMs: 25000, movement: "pushup"), .init(atMs: 54000, movement: "squat")])
        XCTAssertEqual(scenario.expectedRepsByMovement, ["pullup": 5, "pushup": 10, "squat": 15])
    }

    func testTheLowLightClipsKeepTheirModels() throws {
        let youtube = try catalogue("youtube")
        func light(_ id: String) -> Light? { youtube.first { $0.id == id }?.light }
        XCTAssertEqual(light("youtube_pullups_band_assisted_five_dim"), Light(gain: 0.07, model: "uncompensated"))
        XCTAssertEqual(light("youtube_pullups_band_assisted_five_very_dim"), Light(gain: 0.03, model: "uncompensated"))
        XCTAssertEqual(light("youtube_pullups_noise_limited_is_noticed"), Light(gain: 0.03, model: "iso"))
        XCTAssertEqual(youtube.first { $0.id == "youtube_pullups_noise_limited_is_noticed" }?.expectedTracking, "LOST")
        XCTAssertEqual(youtube.first { $0.id == "youtube_pullups_noise_limited_is_noticed" }?.countTolerance, 1)
        XCTAssertNil(light("youtube_pushups_four_rep_demo"))
    }

    func testTheYoutubeCatalogueHasItsFourteenClipsAndTheCategoriesTheyFallIn() throws {
        let youtube = try catalogue("youtube")
        XCTAssertEqual(youtube.count, 14)
        func category(_ s: Scenario) -> String {
            ScenarioReport(id: s.id, exercise: s.exercise, expectedReps: s.expectedReps ?? 0, tags: s.tags ?? []).category
        }
        XCTAssertEqual(youtube.filter { category($0) == "must-not-count" }.count, 4)
        XCTAssertEqual(youtube.filter { category($0) == "difficult-but-valid" }.count, 2)
        XCTAssertEqual(youtube.filter { category($0) == "clean-valid" }.count, 8)
    }

    func testAMissingCatalogueIsAWarningNotAnError() throws {
        var warnings: [String] = []
        let none = try Catalogue.load([Self.root.appendingPathComponent("tests/scenarios/absent.json")], warnings: &warnings)
        XCTAssertEqual(none, [])
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].hasPrefix("no catalogue at "))
    }

    func testKeysThisToolDoesNotReadAreIgnored() throws {
        let json = """
        {"scenarios": [{"id": "a", "video": "v.mp4", "exercise": "pullup", "expectedReps": 3,
                        "notes": "n", "quality": "q", "model": "lightning", "labelledBottomsMs": {"pullup": [1]}}]}
        """
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cat-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var warnings: [String] = []
        let scenarios = try Catalogue.load([file], warnings: &warnings)
        XCTAssertEqual(scenarios.map { $0.id }, ["a"])
        XCTAssertEqual(scenarios[0].expectedReps, 3)
    }

    func testMovementNamesAreRunBatchsSpellings() {
        for name in ["pullup", "pull-up", "pullups", "pull-ups", "PULLUP"] { XCTAssertEqual(MovementNames.exercise(name), .pullup, name) }
        for name in ["pushup", "push-up", "pushups", "push-ups"] { XCTAssertEqual(MovementNames.exercise(name), .pushup, name) }
        for name in ["squat", "squats"] { XCTAssertEqual(MovementNames.exercise(name), .squat, name) }
        XCTAssertNil(MovementNames.exercise("cindy"))
        XCTAssertNil(MovementNames.exercise("lunge"))
        XCTAssertEqual(MovementNames.pullVariant("STRICT"), .strictPullUp)
        XCTAssertEqual(MovementNames.pullVariant("band_assisted_pull_up"), .bandAssistedPullUp)
        XCTAssertNil(MovementNames.pullVariant("kipping"))
    }

    /// run_batch.py's tables are the source of those spellings; if it learns a new one, this says so
    func testRunBatchKnowsNoSpellingThisToolLacks() throws {
        let source = try String(contentsOf: Self.root.appendingPathComponent("tools/video_regression/run_batch.py"), encoding: .utf8)
        let table = try XCTUnwrap(source.range(of: "EXERCISES = {")).upperBound
        let block = String(source[table..<(try XCTUnwrap(source.range(of: "\n}\n", range: table..<source.endIndex)).lowerBound)])
        let pattern = try NSRegularExpression(pattern: "\"([a-z-]+)\": Exercise\\.([A-Z]+)")
        let all = NSRange(block.startIndex..., in: block)
        let found = pattern.matches(in: block, range: all).map { m -> (String, String) in
            (String(block[Range(m.range(at: 1), in: block)!]), String(block[Range(m.range(at: 2), in: block)!]))
        }
        XCTAssertEqual(found.count, 10)
        for (name, exercise) in found {
            XCTAssertEqual(MovementNames.exercise(name)?.label.replacingOccurrences(of: "-", with: "").uppercased(),
                           exercise + "S", name)
        }
        let variants = try XCTUnwrap(source.range(of: "PULL_VARIANTS = {"))
        let variantBlock = String(source[variants.upperBound..<(try XCTUnwrap(source.range(of: "\n}\n", range: variants.upperBound..<source.endIndex)).lowerBound)])
        let keys = try NSRegularExpression(pattern: "\"([a-z_]+)\": PullVariant").matches(
            in: variantBlock, range: NSRange(variantBlock.startIndex..., in: variantBlock))
            .map { String(variantBlock[Range($0.range(at: 1), in: variantBlock)!]) }
        XCTAssertEqual(keys.count, 4)
        for key in keys { XCTAssertNotNil(MovementNames.pullVariant(key), key) }
    }
}
