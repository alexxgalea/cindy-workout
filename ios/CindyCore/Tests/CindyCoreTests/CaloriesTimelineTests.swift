import XCTest
import CindyCore
import CindyFixtures

/// Mirrors `CaloriesTimelineTest.kt`.
///
/// `Calories.timeline` is the running total behind `Calories.estimate`, drawn on the results
/// timeline. What must hold is that the two can never disagree about the figure, so most of this is
/// that equality over traces nobody chose by hand. The generated ones draw from `KotlinRandom` with
/// the Kotlin test's own seeds, so they are the same traces.
final class CaloriesTimelineTests: XCTestCase {

    private let twentyMinutes: Int64 = 20 * 60 * 1000
    private let body = Body(70.0, age: 30, sex: .male)

    private func trace(_ samples: (Int64, Int)...) -> HeartRateTrace { trace(samples) }

    private func trace(_ samples: [(Int64, Int)]) -> HeartRateTrace {
        HeartRateTrace(startedAtMillis: 0, samples: samples.map { HeartRateSample($0.0, $0.1) }, pauses: [])
    }

    private func rounded(_ x: Double) -> Int { JavaText.roundToInt(x) }

    /// no weight or no clock gives no points, as estimate gives no number
    func testNoWeightOrNoClockGivesNoPointsAsEstimateGivesNoNumber() {
        XCTAssertTrue(Calories.timeline(totalReps: 300, activeMs: twentyMinutes, body: Body(0.0), trace: nil).isEmpty)
        XCTAssertTrue(Calories.timeline(totalReps: 300, activeMs: 0, body: body, trace: nil).isEmpty)
    }

    /// without a trace it is the origin and the end, both estimated
    func testWithoutATraceItIsTheOriginAndTheEndBothEstimated() {
        let points = Calories.timeline(totalReps: 300, activeMs: twentyMinutes, body: body, trace: nil)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0], CaloriePoint(0, 0.0, fromHeartRate: false))
        XCTAssertEqual(points[1].clockMs, twentyMinutes)
        XCTAssertFalse(points[1].fromHeartRate)
        XCTAssertEqual(Calories.estimate(totalReps: 300, activeMs: twentyMinutes, body: body, trace: nil)!.kcal,
                       Int(points[1].kcal))
    }

    /// a trace with no age on file stays on the reps, as estimate does
    func testATraceWithNoAgeOnFileStaysOnTheRepsAsEstimateDoes() {
        let noAge = Body(70.0, age: nil, sex: .male)
        let points = Calories.timeline(totalReps: 300, activeMs: twentyMinutes, body: noAge,
                                       trace: trace((0, 150), (1_000, 150)))
        XCTAssertEqual(points.count, 2)
        XCTAssertFalse(points.contains { $0.fromHeartRate })
        XCTAssertEqual(Calories.estimate(totalReps: 300, activeMs: twentyMinutes, body: noAge, trace: trace((0, 150)))!.kcal,
                       rounded(points[points.count - 1].kcal))
    }

    /// a trace of nothing usable is the reps-only pair
    func testATraceOfNothingUsableIsTheRepsOnlyPair() {
        let junk = trace((0, 10), (1_000, 300))
        let points = Calories.timeline(totalReps: 300, activeMs: twentyMinutes, body: body, trace: junk)
        XCTAssertEqual(points.count, 2)
        XCTAssertFalse(points[points.count - 1].fromHeartRate)
    }

    /// heart-rate stretches are flagged and the gaps between them are not
    func testHeartRateStretchesAreFlaggedAndTheGapsBetweenThemAreNot() {
        // 150 bpm for 3 s then silence until 10 s: the hold ends at 5 s, so 5..10 s is estimated.
        let points = Calories.timeline(totalReps: 300, activeMs: 20_000, body: body, trace: trace((0, 150), (10_000, 150)))
        XCTAssertEqual(points.map { $0.clockMs }, [0, 5_000, 10_000, 15_000, 20_000])
        XCTAssertEqual(points.map { $0.fromHeartRate }, [false, true, false, true, false])
    }

    /// the first sample not at zero leaves an estimated lead-in
    func testTheFirstSampleNotAtZeroLeavesAnEstimatedLeadIn() {
        let points = Calories.timeline(totalReps: 300, activeMs: 20_000, body: body, trace: trace((2_000, 150), (3_000, 150)))
        XCTAssertEqual(points.map { $0.clockMs }, [0, 2_000, 3_000, 8_000, 20_000])
        XCTAssertEqual(points.map { $0.fromHeartRate }, [false, false, true, true, false])
    }

    /// it never goes down and never stands still
    func testItNeverGoesDownAndNeverStandsStill() {
        var random = KotlinRandom(seed: 7)
        for _ in 0..<50 {
            let points = Calories.timeline(totalReps: 300, activeMs: twentyMinutes, body: body,
                                           trace: randomTrace(&random))
            for i in 1..<points.count {
                XCTAssertTrue(points[i].clockMs > points[i - 1].clockMs, "clock must advance at \(i)")
                XCTAssertTrue(points[i].kcal >= points[i - 1].kcal, "kcal must not fall at \(i)")
            }
            XCTAssertEqual(points[0].clockMs, 0)
            XCTAssertEqual(points[points.count - 1].clockMs, twentyMinutes)
        }
    }

    /// its last point rounds to the estimate over generated traces
    func testItsLastPointRoundsToTheEstimateOverGeneratedTraces() {
        var random = KotlinRandom(seed: 2026)
        for n in 0..<200 {
            let reps = Int(random.nextInt(0, 400))
            let activeMs = random.nextLong(30_000, twentyMinutes)
            let b: Body
            switch n % 4 {
            case 0: b = Body(65.0 + Double(n % 30), age: 25 + n % 40, sex: .female)
            case 1: b = Body(80.0, age: 41, sex: .male)
            case 2: b = Body(72.5, age: 33, sex: .unstated)
            default: b = Body(90.0, age: nil, sex: nil)
            }
            let t: HeartRateTrace? = n % 10 == 9 ? nil : randomTrace(&random, activeMs)
            let estimate = Calories.estimate(totalReps: reps, activeMs: activeMs, body: b, trace: t)!
            let points = Calories.timeline(totalReps: reps, activeMs: activeMs, body: b, trace: t)
            XCTAssertEqual(estimate.kcal, rounded(points[points.count - 1].kcal), "run \(n)")
            XCTAssertEqual(activeMs, points[points.count - 1].clockMs, "run \(n)")
            // And what it flags as measured is exactly what the estimate says the watch covered.
            var measured: Int64 = 0
            for i in 1..<points.count where points[i].fromHeartRate {
                measured += points[i].clockMs - points[i - 1].clockMs
            }
            XCTAssertEqual(estimate.heartRateMs, measured, "run \(n)")
        }
    }

    /// duplicate and out-of-order samples do not break the equality
    func testDuplicateAndOutOfOrderSamplesDoNotBreakTheEquality() {
        let t = trace((5_000, 140), (1_000, 150), (1_000, 152), (5_000, 141), (30_000, 160))
        let estimate = Calories.estimate(totalReps: 250, activeMs: 40_000, body: body, trace: t)!
        let points = Calories.timeline(totalReps: 250, activeMs: 40_000, body: body, trace: t)
        XCTAssertEqual(estimate.kcal, rounded(points[points.count - 1].kcal))
        for i in 1..<points.count { XCTAssertTrue(points[i].clockMs > points[i - 1].clockMs) }
    }

    /// Bursts of samples a second apart with silences of random length between them.
    private func randomTrace(_ random: inout KotlinRandom, _ activeMs: Int64? = nil) -> HeartRateTrace {
        let activeMs = activeMs ?? twentyMinutes
        var samples: [(Int64, Int)] = []
        var at = random.nextLong(0, 4_000)
        while at < activeMs + 2_000 {
            samples.append((at, Int(random.nextInt(25, 235))))
            at += random.nextInt(10) == 0 ? random.nextLong(5_001, 60_000) : random.nextLong(500, 2_500)
        }
        return trace(samples)
    }
}
