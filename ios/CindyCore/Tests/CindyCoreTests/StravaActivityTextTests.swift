import XCTest
import CindyCore

/// The name and description Strava shows for a finished Cindy.
///
/// Mirrors `StravaActivityTextTest.kt`.
final class StravaActivityTextTests: XCTestCase {

    private func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func changing(_ a: Attempt, _ change: (inout Attempt) -> Void) -> Attempt {
        var copy = a
        change(&copy)
        return copy
    }

    // ---- name() ---------------------------------------------------------------------------

    /// a standard Cindy names itself with the score
    func testAStandardCindyNamesItselfWithTheScore() {
        let a = Attempt(rounds: 17, reps: 12, atMillis: 0, profile: CindyProfile.standard)
        XCTAssertEqual(StravaActivityText.name(a), "Cindy — 17 + 12")
    }

    /// an adaptive Cindy names the mode instead of Cindy
    func testAnAdaptiveCindyNamesTheModeInsteadOfCindy() {
        let a = Attempt(rounds: 9, reps: 0, atMillis: 0, profile: CindyProfile(push: .kneePushUp))
        XCTAssertEqual(StravaActivityText.name(a), "Adaptive Cindy — 9")
    }

    /// a lower-bound score is prefixed as at least
    func testALowerBoundScoreIsPrefixedAsAtLeast() {
        let a = Attempt(rounds: 14, reps: 3, atMillis: 0, profile: CindyProfile.standard, untrackedMs: 45_000)
        XCTAssertTrue(a.scoreIsLowerBound)
        XCTAssertEqual(StravaActivityText.name(a), "Cindy — at least 14 + 3")
    }

    // ---- description() ----------------------------------------------------------------------

    private let fullCindy = Attempt(
        rounds: 17, reps: 12, atMillis: 0, durationMs: 20 * 60 * 1000,
        profile: CindyProfile.standard, countedReps: 522)

    /// the first line states rounds, reps, total and duration
    func testTheFirstLineStatesRoundsRepsTotalAndDuration() {
        let text = lines(StravaActivityText.description(fullCindy, .none))
        XCTAssertEqual(text[0], "17 rounds + 12 reps · 522 reps in 20:00")
    }

    /// one round and one rep are singular
    func testOneRoundAndOneRepAreSingular() {
        let one = changing(fullCindy) { $0.rounds = 1; $0.reps = 1; $0.countedReps = 31 }
        let text = lines(StravaActivityText.description(one, .none))
        XCTAssertEqual(text[0], "1 round + 1 rep · 31 reps in 20:00")
    }

    /// stopping before the clock runs out says so on the first line
    func testStoppingBeforeTheClockRunsOutSaysSoOnTheFirstLine() {
        let stopped = changing(fullCindy) { $0.durationMs = 12 * 60 * 1000 + 34_000; $0.countedReps = 300 }
        let text = lines(StravaActivityText.description(stopped, .none))
        XCTAssertEqual(text[0], "17 rounds + 12 reps · 300 reps in 12:34 — stopped early")
    }

    /// a standard attempt's second line is its level caption
    func testAStandardAttemptsSecondLineIsItsLevelCaption() {
        let text = lines(StravaActivityText.description(fullCindy, .none))
        XCTAssertEqual(text[1], fullCindy.caption)
        XCTAssertEqual(text[1], "Advanced")
    }

    /// an adaptive attempt's second line names the changed movements
    func testAnAdaptiveAttemptsSecondLineNamesTheChangedMovements() {
        let adaptive = changing(fullCindy) { $0.profile = CindyProfile(push: .kneePushUp) }
        let text = lines(StravaActivityText.description(adaptive, .none))
        XCTAssertEqual(text[1], "knee push-ups")
    }

    /// an unrecognised profile's second line falls back to the caption
    func testAnUnrecognisedProfilesSecondLineFallsBackToTheCaption() {
        let unrecognised = changing(fullCindy) { $0.profile = nil }
        let text = lines(StravaActivityText.description(unrecognised, .none))
        XCTAssertEqual(text[1], "Movements not recognised")
    }

    /// no line names round splits when there are none
    func testNoLineNamesRoundSplitsWhenThereAreNone() {
        XCTAssertFalse(StravaActivityText.description(fullCindy, .none).contains("Average round"))
    }

    /// splits produce an average, fastest and slowest line
    func testSplitsProduceAnAverageFastestAndSlowestLine() {
        let withSplits = changing(fullCindy) { $0.roundSplitsMs = [70_000, 58_000, 85_000, 70_000] }
        let description = StravaActivityText.description(withSplits, .none)
        XCTAssertTrue(description.contains("Average round \(formatDuration(withSplits.avgRoundMs!))"))
        XCTAssertTrue(description.contains("fastest 0:58"))
        XCTAssertTrue(description.contains("slowest 1:25"))
    }

    /// no line mentions pausing when nothing was paused
    func testNoLineMentionsPausingWhenNothingWasPaused() {
        XCTAssertFalse(StravaActivityText.description(fullCindy, .none).contains("Paused"))
    }

    /// a pause names both the paused time and the real time
    func testAPauseNamesBothThePausedTimeAndTheRealTime() {
        let paused = changing(fullCindy) { $0.pausedMs = 90_000 }
        XCTAssertTrue(StravaActivityText.description(paused, .none).contains("Paused 1:30 · 21:30 real time"))
    }

    /// no line mentions hand-added reps when none were added
    func testNoLineMentionsHandAddedRepsWhenNoneWereAdded() {
        XCTAssertFalse(StravaActivityText.description(fullCindy, .none).contains("added by hand"))
    }

    /// manual reps are named against the total they contributed to
    func testManualRepsAreNamedAgainstTheTotalTheyContributedTo() {
        let manual = changing(fullCindy) { $0.manualReps = 12 }
        XCTAssertTrue(StravaActivityText.description(manual, .none).contains("12 of the 522 reps were added by hand"))
    }

    /// no line claims a lower bound when the camera never lost the athlete
    func testNoLineClaimsALowerBoundWhenTheCameraNeverLostTheAthlete() {
        XCTAssertFalse(StravaActivityText.description(fullCindy, .none).contains("lower bound"))
    }

    /// losing the camera is named and the score is called a lower bound
    func testLosingTheCameraIsNamedAndTheScoreIsCalledALowerBound() {
        let blind = changing(fullCindy) { $0.untrackedMs = 45_000 }
        XCTAssertTrue(StravaActivityText.description(blind, .none)
            .contains("The camera lost you for 0:45, so the score is a lower bound"))
    }

    /// no calorie line at all when there is nothing to base one on
    func testNoCalorieLineAtAllWhenThereIsNothingToBaseOneOn() {
        XCTAssertFalse(StravaActivityText.description(fullCindy, .none).contains("Calories"))
    }

    /// a body-weight calorie basis names the MET estimate
    func testABodyWeightCalorieBasisNamesTheMetEstimate() {
        let description = StravaActivityText.description(fullCindy, .bodyWeight)
        let met = Calories.met(totalReps: fullCindy.totalReps, activeMs: fullCindy.durationMs)
        XCTAssertTrue(description.contains("≈ \(JavaText.fixed(met, 1)) METs"))
        XCTAssertTrue(description.contains("Calories estimated from body weight"))
    }

    /// a heart-rate calorie basis with full coverage says so plainly
    func testAHeartRateCalorieBasisWithFullCoverageSaysSoPlainly() {
        let description = StravaActivityText.description(fullCindy, .heartRate, heartRateMs: fullCindy.durationMs)
        XCTAssertTrue(description.contains("Calories estimated from heart rate"))
    }

    /// a heart-rate calorie basis with no coverage given says so plainly
    func testAHeartRateCalorieBasisWithNoCoverageGivenSaysSoPlainly() {
        XCTAssertTrue(StravaActivityText.description(fullCindy, .heartRate).contains("Calories estimated from heart rate"))
    }

    /// partial heart-rate coverage names the split with body weight
    func testPartialHeartRateCoverageNamesTheSplitWithBodyWeight() {
        let description = StravaActivityText.description(fullCindy, .heartRate, heartRateMs: 14 * 60 * 1_000 + 20_000)
        XCTAssertTrue(description.contains("Calories from heart rate for 14:20 of 20:00, body weight for the rest"))
    }

    /// the last line always credits the app
    func testTheLastLineAlwaysCreditsTheApp() {
        XCTAssertEqual(lines(StravaActivityText.description(fullCindy, .none)).last, "Counted by Cindy Tracker")
    }
}
