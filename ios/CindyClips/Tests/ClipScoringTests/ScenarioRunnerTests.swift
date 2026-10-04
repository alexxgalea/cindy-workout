import XCTest
import CindyCore
import CindyFixtures
import ClipScoring

/// A scenario that cannot be run is skipped with its reason and is never a pass.
final class ScenarioRunnerTests: XCTestCase {

    private struct Source: ClipFrameSource {
        var result: Result<[ClipFrame], Error>
        func frames(of video: URL, light: Light?) async throws -> [ClipFrame] { try result.get() }
    }

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("cindy-clips-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not a video".utf8).write(to: dir.appendingPathComponent("clip.mp4"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func scenario(video: String = "clip.mp4", expected: Int = 4) -> Scenario {
        Scenario(id: "clip", video: video, exercise: "pushup", expectedReps: expected, tags: ["youtube"])
    }

    private func frames() -> [ClipFrame] {
        var clip = ClipBuilder()
        clip.hold(PoseFixtures.pushup(175))
        clip.pushups(4)
        return clip.frames
    }

    func testAMissingClipIsSkippedWithItsPath() async {
        let runner = ScenarioRunner(root: dir, source: Source(result: .success(frames())))
        let report = await runner.run(scenario(video: "tests/fixtures/none.mp4"))
        XCTAssertEqual(report.status, .skipped)
        XCTAssertEqual(report.skipReason, "missing fixture: \(dir.path)/tests/fixtures/none.mp4")
        XCTAssertEqual(report.failures, [])
    }

    func testAnAbsolutePathIsUsedAsGiven() async {
        let runner = ScenarioRunner(root: URL(fileURLWithPath: "/nowhere"), source: Source(result: .success(frames())))
        let report = await runner.run(scenario(video: dir.appendingPathComponent("clip.mp4").path))
        XCTAssertEqual(report.status, .passed)
    }

    func testNoSourceSkipsWithTheReasonItWasGiven() async {
        let runner = ScenarioRunner(root: dir, source: nil, noSourceReason: "no Vision here")
        let report = await runner.run(scenario())
        XCTAssertEqual(report.status, .skipped)
        XCTAssertEqual(report.skipReason, "no Vision here")
    }

    /// with neither, the missing clip is what is reported: that is the thing to fix
    func testAMissingClipIsReportedBeforeAMissingSource() async {
        let report = await ScenarioRunner(root: dir, source: nil).run(scenario(video: "gone.mp4"))
        XCTAssertTrue(report.skipReason?.hasPrefix("missing fixture:") == true)
    }

    func testASourceThatCannotServeSkips() async {
        let runner = ScenarioRunner(root: dir, source: Source(result: .failure(ClipUnavailable("no GPU"))))
        let report = await runner.run(scenario())
        XCTAssertEqual(report.status, .skipped)
        XCTAssertEqual(report.skipReason, "no GPU")
    }

    /// a clip that is there and broken is a failure, not a skip
    func testAnUnreadableClipFails() async {
        let runner = ScenarioRunner(root: dir, source: Source(result: .failure(ClipUnreadable("cannot open video: clip.mp4"))))
        let report = await runner.run(scenario())
        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.failures, ["cannot open video: clip.mp4"])
        XCTAssertNil(report.skipReason)
    }

    func testAnythingElseThatGoesWrongFailsToo() async {
        struct Boom: Error {}
        let report = await ScenarioRunner(root: dir, source: Source(result: .failure(Boom()))).run(scenario())
        XCTAssertEqual(report.status, .failed)
    }

    func testAClipThatIsThereIsScored() async {
        let runner = ScenarioRunner(root: dir, source: Source(result: .success(frames())))
        let passed = await runner.run(scenario(expected: 4))
        XCTAssertEqual(passed.status, .passed)
        XCTAssertEqual(passed.observedReps, 4)
        let failed = await runner.run(scenario(expected: 9))
        XCTAssertEqual(failed.status, .failed)
    }

    // MARK: the summary

    private func summary(_ reports: [ScenarioReport]) -> String {
        RunSummary.summaryText(reports, reportPath: "r.json")
    }

    func testARunOfNothingButSkipsSaysSoAndMeasuresNothing() {
        let skipped = (1...3).map { ScenarioReport.skipped(Scenario(id: "c\($0)", video: "v", exercise: "pullup", expectedReps: 5), because: "missing fixture: v") }
        let text = summary(skipped)
        XCTAssertTrue(text.contains("0 passed, 0 failed, 3 skipped of 3 scenario(s)"), text)
        XCTAssertTrue(text.contains("a skipped scenario is not a pass"), text)
        XCTAssertFalse(text.contains("exact count"), text)
        XCTAssertFalse(text.contains("Metrics by category"), text)
        XCTAssertTrue(RunSummary.scenarioText(skipped[0], showFrames: false).contains("SKIPPED -- missing fixture: v"))
    }

    func testTheMetricsLeaveSkippedClipsOut() {
        var under = ScenarioReport(id: "under", exercise: "pullup", expectedReps: 10, observedReps: 9)
        under.tags = ["youtube"]
        let exact = ScenarioReport(id: "exact", exercise: "pushup", expectedReps: 4, observedReps: 4)
        let falsePositive = ScenarioReport(id: "fp", exercise: "pullup", expectedReps: 0, observedReps: 2,
                                           failures: ["expected 0 reps, observed 2"])
        let skipped = ScenarioReport.skipped(Scenario(id: "s", video: "v", exercise: "squat", expectedReps: 2), because: "x")
        let text = summary([under, exact, falsePositive, skipped])
        XCTAssertTrue(text.contains("clean-valid  (2 clip(s))"), text)
        XCTAssertTrue(text.contains("exact count:        1/2"), text)
        XCTAssertTrue(text.contains("mean absolute error: 0.50 reps"), text)
        XCTAssertTrue(text.contains("under-counting:      under"), text)
        XCTAssertTrue(text.contains("false positives:     2  <-- MUST BE ZERO"), text)
        XCTAssertTrue(text.contains("2 passed, 1 failed, 1 skipped of 4"), text.replacingOccurrences(of: "\n", with: "|"))
    }
}
