import XCTest
@testable import CindyCore

/// The corners of the four chart models, and of the lanes the results page hands the timeline, that
/// the ported Robolectric tests do not reach. Written for the port, each from a line that could be
/// changed with every other test still passing.
final class ChartDetailTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private lazy var today = LocalDate(2026, 10, 8)
    private lazy var now = zone.epochMs(today, hour: 12)
    private let duration: Int64 = 20 * 60_000
    private let width = 1000.0

    // MARK: the lanes the page builds

    private func marks() -> [RepMark] {
        let movements = Array(repeating: Exercise.pullup, count: 5) + Array(repeating: Exercise.pushup, count: 10)
            + Array(repeating: Exercise.squat, count: 15)
        return movements.enumerated().map { RepMark(Int64($0.offset + 1) * 2_000, $0.element, manual: false) }
    }

    private func round(marks: [RepMark]?, trace: HeartRateTrace? = nil, body: Body = Body(0)) -> ResultsPage {
        let a = Attempt(rounds: 1, reps: 0, atMillis: now, durationMs: 120_000, roundSplitsMs: [60_000], profile: .standard,
                        countedReps: 30,
                        setSplits: [SetSplit(.pullup, 10_000, 5, 0), SetSplit(.pushup, 20_000, 10, 0), SetSplit(.squat, 30_000, 15, 0)])
        return ResultsPageBuilder.build(ResultsInput(attempt: a, records: [a], body: body, heartTrace: trace, repMarks: marks,
                                                     zone: zone, firstDayOfWeek: .monday, today: today))
    }

    /// Reps are banked and held, so the lane steps; with every rep timed the points are not marked,
    /// and with only the sets timed each set's end is.
    func testTheRepsLaneStepsAndMarksItsPointsOnlyWhenTheRepsWereNotTimed() {
        let timed = round(marks: marks()).timeline!.lanes[0]
        XCTAssertTrue(timed.stepped)
        XCTAssertTrue(timed.zeroBased)
        XCTAssertFalse(timed.markPoints)

        let bySet = round(marks: nil).timeline!.lanes[0]
        XCTAssertTrue(bySet.stepped)
        XCTAssertTrue(bySet.markPoints)
    }

    /// The pulse is held through a short silence, and the energy line is read between its points.
    func testThePulseIsHeldThroughASilenceAndTheEnergyLineIsInterpolated() {
        let trace = HeartRateTrace(startedAtMillis: now, samples: [HeartRateSample(1_000, 130)], pauses: [])
        let lanes = round(marks: marks(), trace: trace, body: Body(70)).timeline!.lanes

        XCTAssertEqual(lanes.map { $0.label }, ["REPS", "HEART RATE", "KCAL (EST.)"])
        XCTAssertEqual(lanes[1].holdMs, Calories.maxHoldMs)
        XCTAssertFalse(lanes[1].zeroBased)
        XCTAssertTrue(lanes[2].interpolate)
        XCTAssertTrue(lanes[2].zeroBased)
    }

    // MARK: the timeline model

    private func lane(_ points: [TimelinePoint], stepped: Bool = false, zeroBased: Bool = false) -> TimelineLane {
        TimelineLane(label: "L", tint: .reps, runs: [TimelineRun(points)], format: { String(Int($0)) },
                     stepped: stepped, zeroBased: zeroBased, height: 100)
    }

    private func timeline(_ lanes: [TimelineLane], stops: [TimelineStop] = []) -> SessionTimelineChartModel {
        let m = SessionTimelineChartModel()
        m.setLanes(lanes, durationMs: duration, roundEndsMs: [], stops: stops)
        return m
    }

    private var rising: [TimelinePoint] { (0...20).map { TimelinePoint(Int64($0) * 60_000, 50 + Double($0) * 2) } }

    /// Only a lane that starts at nothing is drawn from nothing.
    func testOnlyAZeroBasedLaneStartsAtNothing() {
        XCTAssertEqual(timeline([lane(rising, zeroBased: true)]).laneLo[0], 0)
        XCTAssertTrue(timeline([lane(rising)]).laneLo[0] > 0)
    }

    /// A drag that does not move the cursor does not report it again.
    func testADragThatDoesNotMoveTheCursorDoesNotReportItAgain() {
        let m = timeline([lane(rising, stepped: true)])
        var reports = 0
        m.onSelect = { _ in reports += 1 }
        m.touchDown(x: 100, y: 50)
        m.touchMove(x: 130, y: 50, width: width)
        let first = reports
        m.touchMove(x: 130, y: 50, width: width)

        XCTAssertEqual(first, 1)
        XCTAssertEqual(reports, first)
    }

    /// Moving within the stretch between two points ticks once, not at every step.
    func testAScrubTicksOnlyWhenItCrossesToAnotherPoint() {
        let m = timeline([lane(rising, stepped: true)])
        var ticks = 0
        m.onTick = { ticks += 1 }
        m.touchDown(x: 100, y: 50)
        // The points are a minute apart, 1000 wide over twenty minutes, so 50 points a point.
        m.touchMove(x: 120, y: 50, width: width)
        m.touchMove(x: 124, y: 50, width: width)
        m.touchMove(x: 128, y: 50, width: width)

        XCTAssertEqual(ticks, 1)
    }

    /// A cursor past the end of a shorter session is put away.
    func testACursorPastTheEndOfAShorterSessionIsPutAway() {
        let m = timeline([lane(rising)])
        m.select(900_000)
        XCTAssertEqual(m.selectedMs, 900_000)

        m.setLanes([lane(rising)], durationMs: 600_000, roundEndsMs: [], stops: [])

        XCTAssertNil(m.selectedMs)
    }

    /// A scrub announces a round once, when it crosses into it.
    func testAScrubAnnouncesARoundOnceWhenItCrossesIntoIt() {
        let stops = (0..<5).map { TimelineStop(Int64($0) * 240_000, Int64($0 + 1) * 240_000, "Round \($0 + 1)") }
        let m = timeline([lane(rising, stepped: true)], stops: stops)
        var announced: [Int] = []
        m.onStopChanged = { announced.append($0) }

        m.touchDown(x: 10, y: 50)
        m.touchMove(x: 40, y: 50, width: width)
        m.touchMove(x: 60, y: 50, width: width)
        m.touchMove(x: 80, y: 50, width: width)
        XCTAssertEqual(announced, [0])

        m.touchMove(x: 300, y: 50, width: width)
        XCTAssertEqual(announced, [0, 1])
    }

    /// A heart line of a sample a second is not a tick a second.
    func testADenseLineTicksNoOftenerThanEveryFiveSeconds() {
        let dense = lane((0...100).map { TimelinePoint(Int64($0) * 1_000, 100 + Double($0)) })

        let snaps = SessionTimelineChartModel.snapPoints(dense, [])

        XCTAssertEqual(snaps.count, 21)
        XCTAssertEqual(snaps.prefix(3), [0, 5_000, 10_000])
    }

    // MARK: the round track and the splits

    /// A round that was done more than asked is a full pill, not a longer one.
    func testAnOverfilledMovementFillsItsSegmentAndNoMore() {
        let model = RoundTrackModel()
        let round = RoundStat(number: 1, parts: [RoundPart(.pullup, 9, nil), RoundPart(.pushup, 10, nil), RoundPart(.squat, 15, nil)],
                              finished: true, timeMs: 60_000)
        model.show([round]) { _ in "" }

        XCTAssertEqual(model.segments(round: 0, pillWidth: 300).map { $0.reached }, [1, 1, 1])
    }

    /// A touch in the margin lands on the nearest round, however far out it is.
    func testATouchFarOutsideTheGridStillLandsOnTheNearestRound() {
        let model = RoundTrackModel()
        let stats = (1...12).map { RoundStat(number: $0, parts: [], finished: true, timeMs: nil) }
        model.show(stats) { _ in "" }

        XCTAssertEqual(model.nearest(x: 5_000, y: 0, in: width), 9)
        XCTAssertEqual(model.nearest(x: -5_000, y: 0, in: width), 0)
        XCTAssertEqual(model.nearest(x: 5_000, y: 5_000, in: width), 11)
    }

    /// The round numbers are thinned to fit, but the selected one is always there.
    func testTheSelectedRoundNumberIsDrawnWhateverTheThinning() {
        let model = RoundSplitsChartModel()
        let bars = (1...40).map { RoundSplits.Bar(round: $0, ms: 60_000, sets: nil) }
        model.show(bars: bars, fastest: 0, averageMs: 60_000, averageLabel: nil, describe: { "Round \($0 + 1)" })
        model.select(7)

        let drawn = model.numberIndices(width: 200)

        XCTAssertTrue(drawn.contains(7), "\(drawn)")
        XCTAssertFalse(drawn.contains(5), "the neighbour would overlap it: \(drawn)")
        XCTAssertFalse(drawn.contains(9), "\(drawn)")
    }
}
