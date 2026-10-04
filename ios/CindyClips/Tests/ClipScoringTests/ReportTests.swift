import XCTest
import CindyCore
import CindyFixtures
import ClipScoring

/// The report is what `compare_reports.py` reads next to the one `run_batch.py` writes, so its
/// keys are `run_batch.py`'s, read here from the Python source rather than copied.
final class ReportTests: XCTestCase {

    private static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    /// The `"key":` names in a piece of Python.
    private static func quotedKeys(in text: String) -> Set<String> {
        let pattern = try! NSRegularExpression(pattern: "\"([A-Za-z]+)\":")
        let all = NSRange(text.startIndex..., in: text)
        return Set(pattern.matches(in: text, range: all).compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } })
    }

    private func pythonSource() throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent("tools/video_regression/run_batch.py"), encoding: .utf8)
    }

    private func decoded(_ reports: [ScenarioReport]) throws -> [String: Any] {
        let data = try ReportWriter.data(reports)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func sample() -> ScenarioReport {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pushup(175))
        clip.pushups(2)
        return ScenarioScorer.score(
            Scenario(id: "p", video: "p.mp4", exercise: "pushup", expectedReps: 2, tags: ["youtube"]), frames: clip.frames)
    }

    /// every key the Python report has per scenario, the Swift one has
    func testEveryKeyRunBatchWritesIsWritten() throws {
        let source = try pythonSource()
        // The scenario dictionary in `main()`: the string keys between "scenarios" and `for r in reports`.
        let start = try XCTUnwrap(source.range(of: "\"scenarios\": ["))
        let end = try XCTUnwrap(source.range(of: "for r in reports\n    ]}", range: start.upperBound..<source.endIndex))
        let block = String(source[start.upperBound..<end.lowerBound])
        let keys = Self.quotedKeys(in: block)
        XCTAssertTrue(keys.isSuperset(of: ["id", "exercise", "category", "expectedReps", "observedReps", "signedError", "frames"]), "\(keys)")

        let scenario = try XCTUnwrap((try decoded([sample()])["scenarios"] as? [[String: Any]])?.first)
        XCTAssertTrue(Set(scenario.keys).isSuperset(of: keys), "missing \(keys.subtracting(scenario.keys))")
        // And the ones this tool adds, which the Python reader ignores.
        XCTAssertTrue(Set(scenario.keys).isSuperset(of: ["status", "skipReason", "perMovement", "worstHealth", "lostMs"]))
    }

    /// a fixed-exercise row has the keys run_batch.py's row has
    func testARowHasTheKeysOfRunBatchsRow() throws {
        let source = try pythonSource()
        let start = try XCTUnwrap(source.range(of: "frames.append({\n            \"timestampMs\": frame.timestamp_ms,\n            \"event\""))
        let end = try XCTUnwrap(source.range(of: "})", range: start.upperBound..<source.endIndex))
        let keys = Self.quotedKeys(in: String(source[start.upperBound..<end.lowerBound]))
        // 13 after the two the block above starts with, which the pattern does not see.
        XCTAssertEqual(keys.count, 13, "\(keys)")
        let row = try XCTUnwrap(sample().frames.first)
        XCTAssertEqual(Set(row.keys), keys.union(["timestampMs", "event"]))
    }

    func testAReportReadsBackAsItWasScored() throws {
        let report = sample()
        let scenario = try XCTUnwrap((try decoded([report])["scenarios"] as? [[String: Any]])?.first)
        XCTAssertEqual(scenario["id"] as? String, "p")
        XCTAssertEqual(scenario["observedReps"] as? Int, 2)
        XCTAssertEqual(scenario["signedError"] as? Int, 0)
        XCTAssertEqual(scenario["category"] as? String, "clean-valid")
        XCTAssertEqual(scenario["status"] as? String, "passed")
        XCTAssertEqual(scenario["setup"] as? String, report.setup)
        XCTAssertEqual((scenario["countTimestampsMs"] as? [Int])?.count, 2)
        XCTAssertEqual(scenario["firstCountMs"] as? Int, report.countTimes.first.map(Int.init))
        XCTAssertEqual((scenario["frames"] as? [Any])?.count, report.frames.count)
        XCTAssertEqual(try decoded([report])["pose"] as? String, "vision")
    }

    func testASkippedScenarioIsWrittenAsSkippedWithItsReason() throws {
        let skipped = ScenarioReport.skipped(Scenario(id: "s", video: "v", exercise: "Pullup", expectedReps: 5, tags: ["youtube"]),
                                             because: "missing fixture: v")
        let scenario = try XCTUnwrap((try decoded([skipped])["scenarios"] as? [[String: Any]])?.first)
        XCTAssertEqual(scenario["status"] as? String, "skipped")
        XCTAssertEqual(scenario["skipReason"] as? String, "missing fixture: v")
        XCTAssertEqual(scenario["exercise"] as? String, "pullup")
        XCTAssertEqual(scenario["expectedReps"] as? Int, 5)
        XCTAssertEqual(scenario["observedReps"] as? Int, 0)
    }

    /// a signal that is not a number is null, as Python writes it
    func testANaNSignalIsNull() throws {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.empty(), frames: 3)   // nobody in shot, so nothing to take a signal from
        let report = ScenarioScorer.score(Scenario(id: "p", video: "v", exercise: "pullup", expectedReps: 0), frames: clip.frames)
        XCTAssertEqual(report.frames[0]["signal"], .null)
        let rows = try XCTUnwrap((try decoded([report])["scenarios"] as? [[String: Any]])?.first?["frames"] as? [[String: Any]])
        XCTAssertTrue(rows[0]["signal"] is NSNull)
    }

    func testRoundingIsPythonsRound() {
        XCTAssertEqual(JSONValue.rounded(0.125, places: 2), .double(0.12))   // half to even
        XCTAssertEqual(JSONValue.rounded(0.375, places: 2), .double(0.38))
        XCTAssertEqual(JSONValue.rounded(1.2346, places: 3), .double(1.235))
        XCTAssertEqual(JSONValue.rounded(.nan, places: 3), .null)
        XCTAssertEqual(JSONValue.rounded(.infinity, places: 3), .null)
    }

    func testPerMovementIsWrittenForACindyScenario() throws {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pullup(170))
        clip.pullups(2)
        let report = ScenarioScorer.score(
            Scenario(id: "c", video: "v", exercise: "cindy", setup: "skip", expectedRepsByMovement: ["pullup": 2]),
            frames: clip.frames)
        let scenario = try XCTUnwrap((try decoded([report])["scenarios"] as? [[String: Any]])?.first)
        let movements = try XCTUnwrap(scenario["perMovement"] as? [String: [String: Any]])
        XCTAssertEqual(Set(movements.keys), ["pullup", "pushup", "squat"])
        XCTAssertEqual(movements["pullup"]?["expected"] as? Int, 2)
        XCTAssertEqual(movements["pullup"]?["observed"] as? Int, 2)
        XCTAssertEqual((movements["pullup"]?["eventsMs"] as? [Int])?.count, 2)
    }
}
