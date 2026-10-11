import XCTest
import CindyCore

/// Walking a trace's workout clock back onto the wall clock, and the composer that uses it.
///
/// The first six mirror `StravaHeartRateTest.kt`. `StravaComposer` has no test of its own on
/// Android (the upload worker's tests drive it); the rest are written here, because it is the one
/// place the calorie basis is chosen and a wrong choice would put a false line in the description.
final class StravaHeartRateTests: XCTestCase {

    private let start: Int64 = 1_700_000_000_000

    /// with no pauses the wall clock is just the start plus the clock reading
    func testWithNoPausesTheWallClockIsJustTheStartPlusTheClockReading() {
        let trace = HeartRateTrace(startedAtMillis: start, samples: [], pauses: [])
        XCTAssertEqual(StravaHeartRate.wallMillis(trace, 3_000), start + 3_000)
    }

    /// samples on either side of two pauses keep their true wall offsets
    func testSamplesOnEitherSideOfTwoPausesKeepTheirTrueWallOffsets() {
        let trace = HeartRateTrace(
            startedAtMillis: start,
            samples: [HeartRateSample(3_000, 90), HeartRateSample(7_000, 120), HeartRateSample(12_000, 140)],
            pauses: [HeartRatePause(atClockMs: 5_000, lengthMs: 2_000), HeartRatePause(atClockMs: 10_000, lengthMs: 3_000)])
        // Before either pause: no pause time to add back in.
        XCTAssertEqual(StravaHeartRate.wallMillis(trace, 3_000), start + 3_000)
        // Between the two pauses: only the first has happened by then.
        XCTAssertEqual(StravaHeartRate.wallMillis(trace, 7_000), start + 7_000 + 2_000)
        // After both pauses: both have happened by then.
        XCTAssertEqual(StravaHeartRate.wallMillis(trace, 12_000), start + 12_000 + 2_000 + 3_000)
    }

    /// a sample exactly at a pause's clock reading still counts that pause
    func testASampleExactlyAtAPausesClockReadingStillCountsThatPause() {
        let trace = HeartRateTrace(startedAtMillis: start, samples: [],
                                   pauses: [HeartRatePause(atClockMs: 5_000, lengthMs: 2_000)])
        // The formula's <=, not <: right at the pause's own moment, the pause already counts.
        XCTAssertEqual(StravaHeartRate.wallMillis(trace, 5_000), start + 5_000 + 2_000)
        // A tick earlier, it does not yet.
        XCTAssertEqual(StravaHeartRate.wallMillis(trace, 4_999), start + 4_999)
    }

    /// points reports each sample's seconds from the given start, floored
    func testPointsReportsEachSamplesSecondsFromTheGivenStartFloored() {
        let trace = HeartRateTrace(startedAtMillis: start,
                                   samples: [HeartRateSample(0, 90), HeartRateSample(3_500, 110)], pauses: [])
        XCTAssertEqual(StravaHeartRate.points(trace, startMillis: start), [HrPoint(0, 90), HrPoint(3, 110)])
    }

    /// points keeps true wall offsets across a pause, not just the clock reading
    func testPointsKeepsTrueWallOffsetsAcrossAPauseNotJustTheClockReading() {
        let trace = HeartRateTrace(
            startedAtMillis: start,
            samples: [HeartRateSample(3_000, 90), HeartRateSample(7_000, 120)],
            pauses: [HeartRatePause(atClockMs: 5_000, lengthMs: 10_000)])
        let points = StravaHeartRate.points(trace, startMillis: start)
        XCTAssertEqual(points[0].secondsFromStart, 3)
        // 7s on the clock, plus the 10s pause that had already happened by then.
        XCTAssertEqual(points[1].secondsFromStart, 17)
    }

    /// an empty trace gives an empty list
    func testAnEmptyTraceGivesAnEmptyList() {
        let trace = HeartRateTrace(startedAtMillis: start, samples: [], pauses: [])
        XCTAssertTrue(StravaHeartRate.points(trace, startMillis: start).isEmpty)
    }

    // ---- beyond the Kotlin: a sample before the start floors down, not towards zero -------

    /// a sample stamped before the payload's start floors to a negative second
    func testASampleStampedBeforeThePayloadsStartFloorsToANegativeSecond() {
        // The trace begins recording a touch before the first rep, so its start is earlier than the
        // attempt's; the payload clamps these later. -500 ms is second -1, not 0.
        let trace = HeartRateTrace(startedAtMillis: start, samples: [HeartRateSample(0, 90)], pauses: [])
        XCTAssertEqual(StravaHeartRate.points(trace, startMillis: start + 500).map(\.secondsFromStart), [-1])
    }

    // ---- StravaComposer --------------------------------------------------------------------

    private let finishedAt: Int64 = Int64(LocalDate(2026, 1, 1).epochDay) * 86_400_000 + 20 * 60_000
    private var attempt: Attempt {
        Attempt(rounds: 1, reps: 0, atMillis: finishedAt, durationMs: 20 * 60 * 1000,
                profile: CindyProfile.standard, countedReps: 30)
    }
    private let sets = [WorkoutSet(1, .pullup, 5), WorkoutSet(1, .pushup, 10), WorkoutSet(1, .squat, 15)]

    private func compose(trace: HeartRateTrace?, body: Body) throws -> (StravaComposition, [String: Any]) {
        let a = attempt
        let composed = try StravaComposer.compose(a, sets, startMillis: startMillisOf(a), utcOffsetSeconds: 0,
                                                   trace: trace, body: body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(composed.payload.utf8)) as? [String: Any])
        return (composed, json)
    }

    /// no body weight gives no calories in the payload and no calorie line
    func testNoBodyWeightGivesNoCaloriesInThePayloadAndNoCalorieLine() throws {
        let (composed, json) = try compose(trace: nil, body: Body(0))
        XCTAssertNil(json["total_calories"])
        XCTAssertFalse(composed.description.contains("Calories"))
    }

    /// a body weight and no trace is a body-weight estimate, with no streams
    func testABodyWeightAndNoTraceIsABodyWeightEstimateWithNoStreams() throws {
        let (composed, json) = try compose(trace: nil, body: Body(70))
        XCTAssertNotNil(json["total_calories"] as? Int)
        XCTAssertNil(json["streams"])
        XCTAssertTrue(composed.description.contains("Calories estimated from body weight"))
    }

    /// a trace the body cannot use still ships as streams, but the calories stay body-weight
    func testATraceTheBodyCannotUseStillShipsAsStreamsButTheCaloriesStayBodyWeight() throws {
        // No age or sex: Calories.estimate cannot apply the heart-rate equation.
        let trace = HeartRateTrace(startedAtMillis: finishedAt - 20 * 60_000,
                                   samples: [HeartRateSample(1_000, 120), HeartRateSample(2_000, 125)], pauses: [])
        let (composed, json) = try compose(trace: trace, body: Body(70))
        XCTAssertNotNil(json["streams"])
        XCTAssertTrue(composed.description.contains("Calories estimated from body weight"))
        XCTAssertFalse(composed.description.contains("from heart rate"))
    }

    /// a usable trace with age and sex is a heart-rate estimate, and the payload and the line agree
    func testAUsableTraceWithAgeAndSexIsAHeartRateEstimateAndThePayloadAndTheLineAgree() throws {
        let samples = (0..<1_200).map { HeartRateSample(Int64($0) * 1_000, 130) }
        let trace = HeartRateTrace(startedAtMillis: finishedAt - 20 * 60_000, samples: samples, pauses: [])
        let body = Body(70, age: 35, sex: .male)
        let (composed, json) = try compose(trace: trace, body: body)

        let estimate = try XCTUnwrap(Calories.estimate(totalReps: 30, activeMs: 20 * 60 * 1000, body: body, trace: trace))
        XCTAssertTrue(estimate.usedHeartRate)
        XCTAssertEqual(json["total_calories"] as? Int, estimate.kcal)
        XCTAssertTrue(composed.description.contains("Calories estimated from heart rate"))
        XCTAssertEqual(composed.name, "Cindy — 1")
    }

    /// an attempt with nothing banked is refused rather than composed
    func testAnAttemptWithNothingBankedIsRefusedRatherThanComposed() {
        let a = attempt
        XCTAssertThrowsError(try StravaComposer.compose(
            a, [WorkoutSet(1, .pullup, 0)], startMillis: startMillisOf(a), utcOffsetSeconds: 0,
            trace: nil, body: Body(70)))
    }
}
