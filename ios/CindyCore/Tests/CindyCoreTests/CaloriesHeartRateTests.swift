import XCTest
import CindyCore

/// Mirrors `CaloriesHeartRateTest.kt`: the heart-rate half of `Calories`.
final class CaloriesHeartRateTests: XCTestCase {

    private let twentyMinutes: Int64 = 20 * 60 * 1000
    private let tolerance = 1e-4

    private func body(_ kg: Double, _ age: Int?, _ sex: Sex?) -> Body { Body(kg, age: age, sex: sex) }

    // MARK: Keytel kcal/min, reference values computed independently of this implementation

    /// keytel kcal per minute matches the reference table
    func testKeytelKcalPerMinuteMatchesTheReferenceTable() {
        XCTAssertEqual(Calories.keytelKcalPerMinute(bpm: 150, body: body(70.0, 30, .male)), 14.222060, accuracy: tolerance)
        XCTAssertEqual(Calories.keytelKcalPerMinute(bpm: 150, body: body(60.0, 30, .female)), 9.875669, accuracy: tolerance)
        XCTAssertEqual(Calories.keytelKcalPerMinute(bpm: 150, body: body(70.0, 30, .unstated)), 11.897933, accuracy: tolerance)
        XCTAssertEqual(Calories.keytelKcalPerMinute(bpm: 170, body: body(80.0, 40, .male)), 18.195053, accuracy: tolerance)
        XCTAssertEqual(Calories.keytelKcalPerMinute(bpm: 120, body: body(65.0, 25, .female)), 6.429804, accuracy: tolerance)
        // Below the fit's range the raw equation undershoots resting metabolism; the floor catches it.
        XCTAssertEqual(Calories.keytelKcalPerMinute(bpm: 60, body: body(70.0, 30, .male)), 1.225, accuracy: tolerance)
        XCTAssertEqual(Calories.keytelKcalPerMinute(bpm: 60, body: body(60.0, 30, .female)), 1.05, accuracy: tolerance)
    }

    // MARK: estimate()

    /// (i) no trace matches burned exactly
    func testNoTraceMatchesBurnedExactly() {
        let b = body(70.0, 30, .male)
        let est = Calories.estimate(totalReps: 300, activeMs: twentyMinutes, body: b, trace: nil)!
        XCTAssertEqual(est.kcal, 196)
        XCTAssertEqual(Calories.burned(totalReps: 300, activeMs: twentyMinutes, bodyWeightKg: 70.0), est.kcal)
        XCTAssertEqual(est.heartRateMs, 0)
        XCTAssertEqual(est.estimatedMs, twentyMinutes)
        XCTAssertFalse(est.usedHeartRate)
    }

    /// (ii) a trace with age missing behaves as if there were none
    func testATraceWithAgeMissingBehavesAsIfThereWereNone() {
        let b = body(70.0, nil, .male)
        let trace = HeartRateTrace(startedAtMillis: 0, samples: [HeartRateSample(0, 150)], pauses: [])
        let est = Calories.estimate(totalReps: 300, activeMs: twentyMinutes, body: b, trace: trace)!
        XCTAssertEqual(Calories.burned(totalReps: 300, activeMs: twentyMinutes, bodyWeightKg: 70.0), est.kcal)
        XCTAssertEqual(est.heartRateMs, 0)
    }

    /// (iii) 1 Hz heart rate covering the whole workout
    func testOneHzHeartRateCoveringTheWholeWorkout() {
        let b = body(70.0, 30, .male)
        let samples = (0..<1200).map { HeartRateSample(Int64($0) * 1000, 150) }
        let trace = HeartRateTrace(startedAtMillis: 0, samples: samples, pauses: [])
        let est = Calories.estimate(totalReps: 300, activeMs: twentyMinutes, body: b, trace: trace)!
        XCTAssertEqual(est.kcal, 284)
        XCTAssertEqual(est.heartRateMs, twentyMinutes)
        XCTAssertEqual(est.estimatedMs, 0)
    }

    /// (iv) heart rate only for the first ten minutes
    func testHeartRateOnlyForTheFirstTenMinutes() {
        let b = body(70.0, 30, .male)
        // 1 Hz from clock 0 to 595_000; the last sample then holds for maxHoldMs, landing the
        // covered window exactly on the ten-minute mark.
        let samples = (0...595).map { HeartRateSample(Int64($0) * 1000, 150) }
        let trace = HeartRateTrace(startedAtMillis: 0, samples: samples, pauses: [])
        let est = Calories.estimate(totalReps: 300, activeMs: twentyMinutes, body: b, trace: trace)!
        XCTAssertEqual(est.kcal, 240)
        XCTAssertEqual(est.heartRateMs, 600_000)
        XCTAssertEqual(est.estimatedMs, 600_000)
    }

    /// (v) a gap wider than the hold window is estimated past the hold
    func testAGapWiderThanTheHoldWindowIsEstimatedPastTheHold() {
        let b = body(70.0, 30, .male)
        let activeMs: Int64 = 25_000
        let trace = HeartRateTrace(startedAtMillis: 0,
                                   samples: [HeartRateSample(0, 150), HeartRateSample(20_000, 150)], pauses: [])
        let est = Calories.estimate(totalReps: 0, activeMs: activeMs, body: b, trace: trace)!
        // Each sample holds for maxHoldMs; the 20s gap between them leaves 15s uncovered.
        XCTAssertEqual(est.heartRateMs, 2 * Calories.maxHoldMs)
        XCTAssertEqual(est.estimatedMs, 15_000)

        let heart = Calories.keytelKcalPerMinute(bpm: 150, body: b) * (Double(2 * Calories.maxHoldMs) / 60_000.0)
        let work = Calories.met(totalReps: 0, activeMs: activeMs) * 3.5 * b.weightKg / 200.0 * (Double(15_000) / 60_000.0)
        XCTAssertEqual(est.kcal, JavaText.roundToInt(heart + work))
    }

    /// (vi) samples beyond activeMs are ignored
    func testSamplesBeyondActiveMsAreIgnored() {
        let b = body(70.0, 30, .male)
        let activeMs: Int64 = 10_000
        let trace = HeartRateTrace(startedAtMillis: 0,
                                   samples: [HeartRateSample(0, 150), HeartRateSample(50_000, 150)], pauses: [])
        let est = Calories.estimate(totalReps: 0, activeMs: activeMs, body: b, trace: trace)!
        // Only the sample inside [0, activeMs) counts, and it holds for maxHoldMs.
        XCTAssertEqual(est.heartRateMs, Calories.maxHoldMs)
        XCTAssertEqual(est.estimatedMs, activeMs - Calories.maxHoldMs)
    }

    /// (vii) an implausible reading is ignored
    func testAnImplausibleReadingIsIgnored() {
        let b = body(70.0, 30, .male)
        let activeMs: Int64 = 10_000
        let trace = HeartRateTrace(startedAtMillis: 0, samples: [HeartRateSample(0, 250)], pauses: [])
        let est = Calories.estimate(totalReps: 0, activeMs: activeMs, body: b, trace: trace)!
        XCTAssertEqual(est.heartRateMs, 0)
        XCTAssertEqual(est.estimatedMs, activeMs)
        XCTAssertEqual(Calories.burned(totalReps: 0, activeMs: activeMs, bodyWeightKg: 70.0), est.kcal)
    }

    /// (viii) no weight or no clock yields null
    func testNoWeightOrNoClockYieldsNull() {
        let b = body(70.0, 30, .male)
        XCTAssertNil(Calories.estimate(totalReps: 300, activeMs: twentyMinutes, body: body(0.0, 30, .male), trace: nil))
        XCTAssertNil(Calories.estimate(totalReps: 300, activeMs: 0, body: b, trace: nil))
    }
}
