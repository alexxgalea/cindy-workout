import XCTest
import CindyCore

/// Mirrors `CaloriesTest.kt`.
final class CaloriesTests: XCTestCase {

    private let twentyMinutes: Int64 = 20 * 60 * 1000

    /// no body weight means no number
    func testNoBodyWeightMeansNoNumber() {
        XCTAssertNil(Calories.burned(totalReps: 300, activeMs: twentyMinutes, bodyWeightKg: 0.0))
        XCTAssertNil(Calories.burned(totalReps: 300, activeMs: twentyMinutes, bodyWeightKg: -5.0))
    }

    /// no clock means no number
    func testNoClockMeansNoNumber() {
        XCTAssertNil(Calories.burned(totalReps: 300, activeMs: 0, bodyWeightKg: 80.0))
    }

    /// the reference effort lands on the reference MET
    func testTheReferenceEffortLandsOnTheReferenceMET() {
        // Ten rounds in twenty minutes is what the 8-MET figure is taken to describe.
        XCTAssertEqual(Calories.met(totalReps: 10 * 30, activeMs: twentyMinutes), Calories.referenceMet, accuracy: 0.001)
    }

    /// the reference effort matches the MET equation by hand
    func testTheReferenceEffortMatchesTheMETEquationByHand() {
        // 8 MET x 3.5 x 80kg / 200 x 20min = 224 kcal.
        XCTAssertEqual(Calories.burned(totalReps: 10 * 30, activeMs: twentyMinutes, bodyWeightKg: 80.0), 224)
    }

    /// working harder for the same time burns more
    func testWorkingHarderForTheSameTimeBurnsMore() {
        let easy = Calories.burned(totalReps: 5 * 30, activeMs: twentyMinutes, bodyWeightKg: 80.0)!
        let hard = Calories.burned(totalReps: 15 * 30, activeMs: twentyMinutes, bodyWeightKg: 80.0)!
        XCTAssertTrue(hard > easy, "\(hard) should exceed \(easy)")
    }

    /// a heavier athlete burns more for the same work
    func testAHeavierAthleteBurnsMoreForTheSameWork() {
        let light = Calories.burned(totalReps: 10 * 30, activeMs: twentyMinutes, bodyWeightKg: 60.0)!
        let heavy = Calories.burned(totalReps: 10 * 30, activeMs: twentyMinutes, bodyWeightKg: 100.0)!
        XCTAssertTrue(heavy > light, "\(heavy) should exceed \(light)")
    }

    /// an idle twenty minutes does not read as vigorous exercise
    func testAnIdleTwentyMinutesDoesNotReadAsVigorousExercise() {
        XCTAssertEqual(Calories.met(totalReps: 0, activeMs: twentyMinutes), Calories.minMet, accuracy: 0.001)
        XCTAssertEqual(Calories.met(totalReps: 30, activeMs: twentyMinutes), Calories.minMet, accuracy: 0.001)
    }

    /// a superhuman score does not run off the top of the scale
    func testASuperhumanScoreDoesNotRunOffTheTopOfTheScale() {
        // The compendium does not describe sustaining this, so the estimate stops following it.
        XCTAssertEqual(Calories.met(totalReps: 40 * 30, activeMs: twentyMinutes), Calories.maxMet, accuracy: 0.001)
        XCTAssertEqual(Calories.met(totalReps: 100 * 30, activeMs: twentyMinutes), Calories.maxMet, accuracy: 0.001)
    }

    /// a workout stopped early is charged for the time it ran
    func testAWorkoutStoppedEarlyIsChargedForTheTimeItRan() {
        let full = Calories.burned(totalReps: 10 * 30, activeMs: twentyMinutes, bodyWeightKg: 80.0)!
        let half = Calories.burned(totalReps: 5 * 30, activeMs: twentyMinutes / 2, bodyWeightKg: 80.0)!
        // Same work rate, half the time: about half the energy.
        XCTAssertTrue(abs(half - full / 2) <= 2, "\(half) should be about half of \(full)")
    }
}
