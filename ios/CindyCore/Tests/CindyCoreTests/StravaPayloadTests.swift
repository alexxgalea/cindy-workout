import XCTest
import CindyCore

/// What goes to Strava as the activity's file: each variant's exercise type, and the JSON.
///
/// Mirrors `StravaPayloadTest.kt`, plus the one `StravaSetsTest` test that feeds the set list
/// through the payload's mapping (the other nine are `StravaSetsTests`, from P3).
final class StravaPayloadTests: XCTestCase {

    // ---- StravaExercises: every variant's exercise_type -----------------------------------

    /// every pull variant maps to the table's exercise type
    func testEveryPullVariantMapsToTheTablesExerciseType() {
        let expected: [PullVariant: String] = [
            .strictPullUp: "PULL_UP_GENERIC",
            .bandAssistedPullUp: "PULL_UP_GENERIC",
            .invertedRow: "INVERTED_ROW",
            .footAssistedPullUp: "PULL_UP_GENERIC",
            .negativePullUp: "NEGATIVE_PULL_UP"
        ]
        // Iterating the cases, rather than listing the table above by hand, is what would catch a
        // variant someone added and forgot to expect here: the same protection the exhaustive
        // `switch` in StravaExercises gives the production code.
        for variant in PullVariant.allCases {
            let profile = CindyProfile(pull: variant)
            XCTAssertEqual(StravaExercises.typeFor(.pullup, profile), expected[variant], variant.rawValue)
        }
    }

    /// every push variant maps to the table's exercise type
    func testEveryPushVariantMapsToTheTablesExerciseType() {
        let expected: [PushVariant: String] = [
            .standardPushUp: "PUSH_UP_GENERIC",
            .kneePushUp: "MODIFIED_PUSH_UP",
            .inclinePushUp: "INCLINE_PUSH_UP"
        ]
        for variant in PushVariant.allCases {
            let profile = CindyProfile(push: variant)
            XCTAssertEqual(StravaExercises.typeFor(.pushup, profile), expected[variant], variant.rawValue)
        }
    }

    /// every squat variant maps to the table's exercise type
    func testEverySquatVariantMapsToTheTablesExerciseType() {
        let expected: [SquatVariant: String] = [
            .airSquat: "AIR_SQUAT",
            .heelsFlat: "SQUAT_GENERIC",
            .boxSquat: "SQUAT_GENERIC",
            .supportedSquat: "SQUAT_GENERIC"
        ]
        for variant in SquatVariant.allCases {
            let profile = CindyProfile(squat: variant)
            XCTAssertEqual(StravaExercises.typeFor(.squat, profile), expected[variant], variant.rawValue)
        }
    }

    /// a null profile falls back to each movement's generic type
    func testANilProfileFallsBackToEachMovementsGenericType() {
        XCTAssertEqual(StravaExercises.typeFor(.pullup, nil), "PULL_UP_GENERIC")
        XCTAssertEqual(StravaExercises.typeFor(.pushup, nil), "PUSH_UP_GENERIC")
        XCTAssertEqual(StravaExercises.typeFor(.squat, nil), "SQUAT_GENERIC")
    }

    /// never claims equipment that was not used
    func testNeverClaimsEquipmentThatWasNotUsed() {
        // The exact regression the table exists to guard: a box squat is not a barbell squat.
        XCTAssertEqual(StravaExercises.typeFor(.squat, CindyProfile(squat: .boxSquat)), "SQUAT_GENERIC")
    }

    // ---- StravaPayload.build --------------------------------------------------------------

    /// 2026-01-01T00:11:00Z
    private let finishedAt: Int64 = Int64(LocalDate(2026, 1, 1).epochDay) * 86_400_000 + 11 * 60_000

    // 11 real minutes (10 running, 1 paused), so start_time backdates to an even 00:00:00Z.
    private var attempt: Attempt {
        Attempt(rounds: 5, reps: 3, atMillis: finishedAt, durationMs: 600_000, pausedMs: 60_000,
                profile: CindyProfile.standard, countedReps: 153)
    }

    private let standardSets = [
        WorkoutSet(1, .pullup, 5),
        WorkoutSet(1, .pushup, 10),
        WorkoutSet(1, .squat, 15)
    ]

    private func json(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func build(_ sets: [WorkoutSet]? = nil, utcOffsetSeconds: Int = 0, kcal: Int? = nil,
                       heartRate: [HrPoint]? = nil) throws -> [String: Any] {
        let a = attempt
        return try json(StravaPayload.build(a, sets ?? standardSets, startMillis: startMillisOf(a),
                                            utcOffsetSeconds: utcOffsetSeconds, kcal: kcal, heartRate: heartRate))
    }

    private func ints(_ any: Any?) -> [Int] { (any as? [Int]) ?? [] }

    /// the required top-level fields are all present
    func testTheRequiredTopLevelFieldsAreAllPresent() throws {
        let json = try build(utcOffsetSeconds: 3600)
        XCTAssertEqual(json["version"] as? String, "1.0")
        XCTAssertEqual(json["start_time"] as? String, "2026-01-01T00:00:00Z")
        XCTAssertEqual(json["utc_offset"] as? Int, 3600)
        XCTAssertEqual(json["elapsed_time"] as? Int, 660)  // 11 real minutes
        XCTAssertEqual(json["active_time"] as? Int, 600)   // 10 running minutes
        XCTAssertEqual((json["creator"] as? [String: Any])?["name"] as? String, "Cindy Tracker")
    }

    /// sets carry exercise_type and repetitions, and never weight
    func testSetsCarryExerciseTypeAndRepetitionsAndNeverWeight() throws {
        let array = try XCTUnwrap(try build()["sets"] as? [[String: Any]])
        XCTAssertEqual(array.count, 3)
        XCTAssertEqual(array[0]["exercise_type"] as? String, "PULL_UP_GENERIC")
        XCTAssertEqual(array[0]["repetitions"] as? Int, 5)
        XCTAssertNil(array[0]["weight"])
    }

    /// a zero-rep set is omitted, since nothing was banked
    func testAZeroRepSetIsOmittedSinceNothingWasBanked() throws {
        let array = try XCTUnwrap(try build(standardSets + [WorkoutSet(2, .pullup, 0)])["sets"] as? [[String: Any]])
        XCTAssertEqual(array.count, 3)
    }

    /// refuses to build a payload with nothing banked at all
    func testRefusesToBuildAPayloadWithNothingBankedAtAll() {
        // The caller must never upload a zero-rep attempt.
        XCTAssertThrowsError(try build([WorkoutSet(1, .pullup, 0)])) { error in
            XCTAssertEqual(error as? StravaPayloadError,
                           StravaPayloadError("Refusing to build a payload with no banked reps"))
        }
    }

    /// total_calories is omitted when kcal is null, present when given
    func testTotalCaloriesIsOmittedWhenKcalIsNilPresentWhenGiven() throws {
        XCTAssertNil(try build(kcal: nil)["total_calories"])
        XCTAssertEqual(try build(kcal: 420)["total_calories"] as? Int, 420)
    }

    /// streams is omitted when there is no heart rate at all
    func testStreamsIsOmittedWhenThereIsNoHeartRateAtAll() throws {
        XCTAssertNil(try build(heartRate: nil)["streams"])
        XCTAssertNil(try build(heartRate: [])["streams"])
    }

    /// streams holds equal-length time and heartrate arrays, with no active array
    func testStreamsHoldsEqualLengthTimeAndHeartrateArraysWithNoActiveArray() throws {
        let heartRate = [HrPoint(0, 90), HrPoint(30, 120), HrPoint(60, 140)]
        let streams = try XCTUnwrap(try build(heartRate: heartRate)["streams"] as? [String: Any])
        XCTAssertEqual(ints(streams["time"]).count, 3)
        XCTAssertEqual(ints(streams["time"]).count, ints(streams["heartrate"]).count)
        XCTAssertEqual(ints(streams["time"]), [0, 30, 60])
        XCTAssertEqual(ints(streams["heartrate"]), [90, 120, 140])
        // No samples exist while paused, so fabricating one would invent heart-rate data.
        XCTAssertNil(streams["active"])
    }

    /// heart rate seconds are clamped between zero and elapsed_time
    func testHeartRateSecondsAreClampedBetweenZeroAndElapsedTime() throws {
        // elapsed_time is 660s (11 real minutes); -10 and 700 both fall outside it.
        let heartRate = [HrPoint(-10, 80), HrPoint(300, 130), HrPoint(700, 150)]
        let streams = try XCTUnwrap(try build(heartRate: heartRate)["streams"] as? [String: Any])
        XCTAssertEqual(ints(streams["time"]), [0, 300, 660])
    }

    /// duplicate seconds created by clamping keep only the earliest-seen sample
    func testDuplicateSecondsCreatedByClampingKeepOnlyTheEarliestSeenSample() throws {
        // -5 and -1 both clamp to second 0; the first sample (80 bpm) must win, not 200.
        let heartRate = [HrPoint(-5, 80), HrPoint(-1, 200), HrPoint(10, 100)]
        let streams = try XCTUnwrap(try build(heartRate: heartRate)["streams"] as? [String: Any])
        XCTAssertEqual(ints(streams["time"]), [0, 10])
        XCTAssertEqual(ints(streams["heartrate"]), [80, 100])
    }

    /// startMillisOf backdates the finish timestamp by the real time the attempt took
    func testStartMillisOfBackdatesTheFinishTimestampByTheRealTimeTheAttemptTook() {
        let a = Attempt(rounds: 1, reps: 0, atMillis: 1_000_000, durationMs: 100_000, pausedMs: 50_000)
        XCTAssertEqual(startMillisOf(a), 850_000)
    }

    // ---- the Strava-phase test from StravaSetsTest ----------------------------------------

    /// the adaptive profile on the attempt reaches StravaPayload's mapping
    func testTheAdaptiveProfileOnTheAttemptReachesStravaPayloadsMapping() throws {
        let a = Attempt(rounds: 0, reps: 0, atMillis: 0, profile: CindyProfile(push: .kneePushUp),
                        countedReps: 13,  // 5 pull-ups + 8 knee push-ups in progress
                        setSplits: [SetSplit(.pullup, 1_000, 5, 0)])
        let sets = StravaSets.from(a)
        XCTAssertEqual(sets, [WorkoutSet(1, .pullup, 5), WorkoutSet(1, .pushup, 8)])

        let payload = try json(StravaPayload.build(a, try XCTUnwrap(sets), startMillis: startMillisOf(a),
                                                   utcOffsetSeconds: 0, kcal: nil, heartRate: nil))
        let pushSet = try XCTUnwrap(payload["sets"] as? [[String: Any]])[1]
        XCTAssertEqual(pushSet["exercise_type"] as? String, "MODIFIED_PUSH_UP")
    }

    // ---- beyond the Kotlin: the instant's text, which Kotlin gets from java.time ---------

    /// start_time is the instant truncated to the second, in UTC, before and after the epoch
    func testStartTimeIsTheInstantTruncatedToTheSecondInUtcBeforeAndAfterTheEpoch() throws {
        func startTime(_ millis: Int64) throws -> String? {
            let a = Attempt(rounds: 1, reps: 0, atMillis: millis)
            let text = try StravaPayload.build(a, [WorkoutSet(1, .pullup, 1)], startMillis: millis,
                                               utcOffsetSeconds: 0, kcal: nil, heartRate: nil)
            return try json(text)["start_time"] as? String
        }
        XCTAssertEqual(try startTime(0), "1970-01-01T00:00:00Z")
        XCTAssertEqual(try startTime(999), "1970-01-01T00:00:00Z")
        XCTAssertEqual(try startTime(-1), "1969-12-31T23:59:59Z")
        XCTAssertEqual(try startTime(1_700_000_000_000), "2023-11-14T22:13:20Z")
        XCTAssertEqual(try startTime(951_782_400_000), "2000-02-29T00:00:00Z")
    }
}
