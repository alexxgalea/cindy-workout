import XCTest
import CindyCore

/// Mirrors `SessionTimelineViewTest.kt`: touch handling and layout of the session timeline, over a
/// twenty-minute clock on a 1000 wide view. Geometry is read back through `x(forClock:)` rather
/// than restated, so what is pinned down is the behaviour: a tap selects an instant, a second tap
/// on it clears it, a sideways drag scrubs. The Android tests that lay the view out and draw it
/// are held by the height and the cursor's lookups.
final class SessionTimelineChartModelTests: XCTestCase {

    private let duration: Int64 = 20 * 60_000
    private let width = 1000.0

    private func repsLane(withComparison: Bool = false) -> TimelineLane {
        TimelineLane(
            label: "REPS", tint: .reps,
            runs: [TimelineRun((0...20).map { TimelinePoint(Int64($0) * 60_000, Double($0) * 10) })],
            comparison: withComparison ? (0...18).map { TimelinePoint(Int64($0) * 60_000, Double($0) * 9) } : [],
            format: { String(Int($0)) }, stepped: true, zeroBased: true, height: 132)
    }

    private func heartLane() -> TimelineLane {
        TimelineLane(
            label: "HEART RATE", tint: .heart,
            runs: [TimelineRun((0...100).map { TimelinePoint(Int64($0) * 1_000, 100.0 + Double($0)) }),
                   TimelineRun((200...300).map { TimelinePoint(Int64($0) * 1_000, 140.0) })],
            format: { String(Int($0)) }, holdMs: Calories.maxHoldMs, height: 88)
    }

    private func kcalLane() -> TimelineLane {
        TimelineLane(
            label: "KCAL (EST.)", tint: .energy,
            runs: [TimelineRun([TimelinePoint(0, 0), TimelinePoint(300_000, 40)], dashed: true),
                   TimelineRun([TimelinePoint(300_000, 40), TimelinePoint(900_000, 130)]),
                   TimelineRun([TimelinePoint(900_000, 130), TimelinePoint(duration, 180)], dashed: true)],
            format: { String(Int($0)) }, zeroBased: true, interpolate: true, height: 88)
    }

    private func stops() -> [TimelineStop] {
        (0..<5).map { TimelineStop(Int64($0) * 240_000, Int64($0 + 1) * 240_000, "Round \($0 + 1)") }
    }

    private func model(_ lanes: [TimelineLane], ends: [Int64] = [], stops: [TimelineStop] = []) -> SessionTimelineChartModel {
        let m = SessionTimelineChartModel()
        m.setLanes(lanes, durationMs: duration, roundEndsMs: ends, stops: stops)
        return m
    }

    private func tap(_ m: SessionTimelineChartModel, _ x: Double) {
        m.touchDown(x: x, y: 100)
        m.touchUp(x: x, y: 100, width: width)
    }

    /// one lane lays out and draws
    func testOneLaneLaysOutAndDraws() {
        let m = model([repsLane()], ends: [240_000, 480_000], stops: stops())

        XCTAssertEqual(m.laneCount, 1)
        XCTAssertTrue(m.height > 0, "no height was asked for")
        let bounds = m.laneBounds()
        XCTAssertEqual(bounds.count, 1)
        XCTAssertTrue(bounds[0].bottom > bounds[0].top)
    }

    /// two lanes are taller than one and both draw, with a comparison and a gap in the heart
    func testTwoLanesAreTallerThanOneAndBothDrawWithAComparisonAndAGapInTheHeart() {
        let one = model([repsLane()])
        let two = model([repsLane(withComparison: true), heartLane()], ends: [240_000], stops: stops())

        XCTAssertEqual(two.laneCount, 2)
        XCTAssertTrue(two.height > one.height)
        two.select(130_000)
        // The cursor finds a value in the first lane, and in the second where a reading was held.
        XCTAssertNotNil(two.value(lane: 0, at: 130_000))
        XCTAssertNotNil(two.comparisonValue(lane: 0, at: 130_000))
        // 130 s is inside the first heart run, but past it by more than the hold: nothing to dot.
        XCTAssertNil(two.value(lane: 1, at: 130_000))
        XCTAssertNotNil(two.value(lane: 1, at: 50_000))
        XCTAssertNil(two.value(lane: 1, at: 150_000), "a gap stays a gap")
    }

    /// a calorie lane of solid and dashed runs adds a lane and draws with a cursor on every run
    func testACalorieLaneOfSolidAndDashedRunsAddsALaneAndDrawsWithACursorOnEveryRun() {
        let m = model([repsLane(), heartLane(), kcalLane()], ends: [240_000], stops: stops())

        XCTAssertEqual(m.laneCount, 3)
        // One instant inside each run: the cursor looks the lane's value up in whichever run holds it.
        for at in [150_000, 600_000, 1_000_000, duration] as [Int64] {
            m.select(at)
            XCTAssertNotNil(m.value(lane: 2, at: at), "no value at \(at)")
        }
        // The running total rides the line between two points rather than sitting on the last.
        XCTAssertEqual(m.value(lane: 2, at: 600_000)!, 85.0, accuracy: 1e-9)
    }

    /// a taller stack of lanes is measured taller
    func testATallerStackOfLanesIsMeasuredTaller() {
        let two = model([repsLane(), heartLane()])
        let three = model([repsLane(), heartLane(), kcalLane()])

        XCTAssertTrue(three.height > two.height)
    }

    /// a tap selects the instant under it, and reports it
    func testATapSelectsTheInstantUnderItAndReportsIt() {
        let m = model([repsLane(), heartLane()], stops: stops())
        var received: [Int64?] = []
        m.onSelect = { received.append($0) }

        tap(m, m.x(forClock: 600_000, width: width))

        let picked = m.selectedMs!
        XCTAssertTrue(abs(picked - 600_000) < 5_000, "picked \(picked)")
        XCTAssertEqual(received, [picked])
    }

    /// tapping the cursor again clears it
    func testTappingTheCursorAgainClearsIt() {
        let m = model([repsLane()], stops: stops())

        tap(m, m.x(forClock: 600_000, width: width))
        tap(m, m.x(forClock: 600_000, width: width))

        XCTAssertNil(m.selectedMs)
    }

    /// a sideways drag scrubs forward through the session
    func testASidewaysDragScrubsForwardThroughTheSession() {
        let m = model([repsLane(), heartLane()], stops: stops())
        var received: [Int64?] = []
        m.onSelect = { received.append($0) }
        let from = m.x(forClock: 100_000, width: width)
        let to = m.x(forClock: 900_000, width: width)

        m.touchDown(x: from, y: 100)
        var x = from
        while x < to {
            x = min(x + 20, to)
            m.touchMove(x: x, y: 100, width: width)
        }
        m.touchUp(x: to, y: 100, width: width)

        let clocks = received.compactMap { $0 }
        XCTAssertFalse(clocks.isEmpty, "nothing was reported")
        XCTAssertTrue(zip(clocks, clocks.dropFirst()).allSatisfy { $0 <= $1 }, "went backwards: \(clocks)")
        XCTAssertTrue(abs(clocks.last! - 900_000) < 5_000)
        XCTAssertEqual(m.selectedMs, clocks.last)
    }

    /// a cursor at the very ends stays on the clock
    func testACursorAtTheVeryEndsStaysOnTheClock() {
        let m = model([repsLane()], stops: stops())

        m.select(-10)
        XCTAssertEqual(m.selectedMs, 0)
        m.select(duration + 99_999)
        XCTAssertEqual(m.selectedMs, duration)
    }

    /// a selection survives swapping the lanes, as a comparison change does
    func testASelectionSurvivesSwappingTheLanesAsAComparisonChangeDoes() {
        let m = model([repsLane()], stops: stops())
        m.select(300_000)

        m.setLanes([repsLane(withComparison: true)], durationMs: duration, stops: stops())

        XCTAssertEqual(m.selectedMs, 300_000)
    }

    /// talkback gets one stop per round
    func testTalkbackGetsOneStopPerRound() {
        let m = model([repsLane(), heartLane()], stops: stops())

        XCTAssertEqual(m.stopCount, 5)
        XCTAssertEqual(m.stops[1].description, "Round 2")
        m.activate(stop: 1)
        XCTAssertEqual(m.selectedMs, 480_000)
    }

    /// no lanes does not crash, draws nothing and takes no touch
    func testNoLanesDoesNotCrashDrawsNothingAndTakesNoTouch() {
        let m = SessionTimelineChartModel()
        m.setLanes([], durationMs: 0)
        var received: [Int64?] = []
        m.onSelect = { received.append($0) }

        tap(m, 100)

        XCTAssertEqual(m.laneCount, 0)
        XCTAssertEqual(m.stopCount, 0)
        XCTAssertTrue(received.isEmpty)
        XCTAssertNil(m.selectedMs)
    }

    /// a lane with nothing in it does not crash
    func testALaneWithNothingInItDoesNotCrash() {
        let empty = TimelineLane(label: "HEART RATE", tint: .heart, runs: [], format: { String(Int($0)) })
        let m = model([empty])

        m.select(10_000)
        XCTAssertNil(m.value(lane: 0, at: 10_000))
        XCTAssertNotNil(m.selectedMs)
        XCTAssertNotEqual(m.laneCount, 0)
    }

    /// a heart run of one reading still draws
    func testAHeartRunOfOneReadingStillDraws() {
        let lone = TimelineLane(label: "HEART RATE", tint: .heart, runs: [TimelineRun([TimelinePoint(30_000, 120)])],
                                format: { String(Int($0)) }, holdMs: Calories.maxHoldMs)
        let m = model([lone])

        m.select(31_000)
        XCTAssertEqual(m.value(lane: 0, at: 31_000), 120)
        XCTAssertTrue(m.height > 0)
    }
}
