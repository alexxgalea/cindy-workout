import XCTest
import CindyCore

/// Mirrors `SessionTimelineCaloriesTest.kt`.
///
/// The calorie line of the session timeline: how it is cut into measured and estimated stretches,
/// and what it says at a moment, for a round and in the legend. The line itself is
/// `Calories.timeline`'s, tested beside it; the points here are written out so each number can be
/// read off.
final class SessionTimelineCaloriesTests: XCTestCase {

    private func attempt(untracked: Int64 = 0) -> Attempt {
        Attempt(rounds: 2, reps: 3, atMillis: 1_000, durationMs: 120_000,
                roundSplitsMs: [60_000, 50_000], countedReps: 63,
                // No set times, so no reps line: what is under test here is the calorie words alone.
                untrackedMs: untracked, setSplits: [])
    }

    private func timeline(_ points: [CaloriePoint], untracked: Int64 = 0) -> SessionTimeline {
        SessionTimeline.of(attempt(untracked: untracked), marks: nil, trace: nil, calories: points)
    }

    private func point(_ clockMs: Int64, _ kcal: Double, _ fromHeartRate: Bool) -> CaloriePoint {
        CaloriePoint(clockMs, kcal, fromHeartRate: fromHeartRate)
    }

    /// Reps only: the origin and the end, one estimated stretch, 120 kcal over two minutes.
    private var estimatedOnly: [CaloriePoint] { [point(0, 0.0, false), point(120_000, 120.0, false)] }

    /// Estimated for the first half minute, measured to the minute, then estimated again.
    private var mixed: [CaloriePoint] {
        [point(0, 0.0, false), point(30_000, 30.0, false), point(60_000, 60.0, true), point(120_000, 100.0, false)]
    }

    // MARK: runs

    /// no points, or only the origin, draw no line
    func testNoPointsOrOnlyTheOriginDrawNoLine() {
        XCTAssertTrue(timeline([]).calorieRuns.isEmpty)
        XCTAssertTrue(timeline([point(0, 0.0, false)]).calorieRuns.isEmpty)
    }

    /// an estimate with no watch is one estimated run
    func testAnEstimateWithNoWatchIsOneEstimatedRun() {
        let runs = timeline(estimatedOnly).calorieRuns
        XCTAssertEqual(runs.count, 1)
        XCTAssertTrue(runs[0].estimated)
        XCTAssertEqual(runs[0].points, estimatedOnly)
    }

    /// runs change where the source changes and share the point they meet at
    func testRunsChangeWhereTheSourceChangesAndShareThePointTheyMeetAt() {
        let runs = timeline(mixed).calorieRuns
        XCTAssertEqual(runs.map { $0.estimated }, [true, false, true])
        XCTAssertEqual(runs[0].points.map { $0.clockMs }, [0, 30_000])
        XCTAssertEqual(runs[1].points.map { $0.clockMs }, [30_000, 60_000])
        XCTAssertEqual(runs[2].points.map { $0.clockMs }, [60_000, 120_000])
    }

    /// neighbouring stretches of one kind are one run
    func testNeighbouringStretchesOfOneKindAreOneRun() {
        let points = [point(0, 0.0, false), point(10_000, 10.0, true), point(20_000, 20.0, true), point(30_000, 30.0, false)]
        let runs = timeline(points).calorieRuns
        XCTAssertEqual(runs.map { $0.estimated }, [false, true])
        XCTAssertEqual(runs[0].points.map { $0.clockMs }, [0, 10_000, 20_000])
        XCTAssertEqual(runs[1].points.map { $0.clockMs }, [20_000, 30_000])
    }

    // MARK: the moment

    /// a moment reads the line between its two points, not the last one
    func testAMomentReadsTheLineBetweenItsTwoPointsNotTheLastOne() {
        let t = timeline(mixed)
        XCTAssertEqual(t.at(0).kcal, 0)
        XCTAssertEqual(t.at(15_000).kcal, 15)
        XCTAssertEqual(t.at(90_000).kcal, 80)
        XCTAssertEqual(t.at(120_000).kcal, 100)
    }

    /// without a calorie line there is no figure to say
    func testWithoutACalorieLineThereIsNoFigureToSay() {
        let t = timeline([])
        XCTAssertNil(t.at(60_000).kcal)
        XCTAssertFalse((t.readout(t.at(60_000)).detail ?? "").contains("kcal"))
    }

    /// the readout says estimated every time
    func testTheReadoutSaysEstimatedEveryTime() {
        let t = timeline(mixed)
        XCTAssertTrue(t.readout(t.at(90_000)).detail!.contains("80 kcal (est.)"))
        XCTAssertTrue(t.readout(t.at(15_000)).detail!.contains("15 kcal (est.)"))
    }

    /// a lower-bound score says at least wherever the figure leans on the reps
    func testALowerBoundScoreSaysAtLeastWhereverTheFigureLeansOnTheReps() {
        let t = timeline(mixed, untracked: Records.untrackedToleranceMs)
        // The first half minute is the reps' estimate: missing reps can only have lowered it.
        XCTAssertTrue(t.readout(t.at(15_000)).detail!.contains("at least 15 kcal (est.)"))
        XCTAssertTrue(t.readout(t.at(90_000)).detail!.contains("at least 80 kcal (est.)"))
    }

    /// a lower-bound score does not floor a figure the watch measured
    func testALowerBoundScoreDoesNotFloorAFigureTheWatchMeasured() {
        let measured = [point(0, 0.0, false), point(60_000, 60.0, true)]
        let t = timeline(measured, untracked: Records.untrackedToleranceMs)
        // The first stretch's flag is the one ending at 60 s: heart-rate measured, no floor.
        XCTAssertFalse(t.readout(t.at(60_000)).detail!.contains("at least"))
    }

    /// a score that is not a lower bound never says at least
    func testAScoreThatIsNotALowerBoundNeverSaysAtLeast() {
        XCTAssertFalse(timeline(mixed).readout(timeline(mixed).at(90_000)).detail!.contains("at least"))
    }

    // MARK: VoiceOver (Kotlin: TalkBack)

    /// a round says its estimated calories by its end
    func testARoundSaysItsEstimatedCaloriesByItsEnd() {
        let t = timeline(mixed)
        let said = t.describeRound(t.rounds[0])
            .replacingOccurrences(of: ", \\d+ reps? by its end", with: "", options: .regularExpression)
        XCTAssertEqual(said, "Round 1, 0:00 to 1:00, 1 minute, 60 kilocalories, estimated, by its end")
    }

    /// a lower-bound round says at least
    func testALowerBoundRoundSaysAtLeast() {
        let t = timeline(mixed, untracked: Records.untrackedToleranceMs)
        XCTAssertTrue(t.describeRound(t.rounds[1]).contains("at least 93 kilocalories, estimated, by its end"))
    }

    // MARK: the legend

    /// no calorie line leaves the legend as it was
    func testNoCalorieLineLeavesTheLegendAsItWas() {
        XCTAssertNil(timeline([]).legend())
    }

    /// the legend says the line is an estimate and what its dashes are
    func testTheLegendSaysTheLineIsAnEstimateAndWhatItsDashesAre() {
        XCTAssertEqual(timeline(estimatedOnly).legend(),
                       "KCAL is an estimate from your reps. The Calories (est.) row below says how.")
        XCTAssertEqual(timeline(mixed).legend(),
                       "KCAL is an estimate; its dashed stretches come from your reps, not your heart rate. "
                       + "The Calories (est.) row below says how.")
        let measured = [point(0, 0.0, false), point(60_000, 60.0, true)]
        XCTAssertEqual(timeline(measured).legend(),
                       "KCAL is an estimate from your heart rate. The Calories (est.) row below says how.")
    }

    /// the legend says why a lower-bound score reads at least
    func testTheLegendSaysWhyALowerBoundScoreReadsAtLeast() {
        XCTAssertTrue(timeline(mixed, untracked: Records.untrackedToleranceMs).legend()!
            .contains("since some reps may be missing"))
    }
}
