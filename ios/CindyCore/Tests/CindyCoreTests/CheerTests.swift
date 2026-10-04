import XCTest
import CindyCore

/// The encouraging sentences. Port of `CheerTest.kt`.
final class CheerTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private let today = LocalDate(2026, 9, 9)
    private let monday = DayOfWeek.monday

    /// 13 rounds + 10 reps is 400 reps; the score is set with rounds and reps, not a total.
    private func attempt(_ iso: String, _ rounds: Int = 13, _ reps: Int = 10, hour: Int = 12) -> Attempt {
        let at = zone.epochMs(LocalDate(parse: iso)!, hour: hour)
        return Attempt(rounds: rounds, reps: reps, atMillis: at, durationMs: 20 * 60_000)
    }

    private func headline(_ a: Attempt...) -> String { Cheer.headline(a, today: today, zone: zone, firstDayOfWeek: monday) }
    private func headline(array a: [Attempt]) -> String { Cheer.headline(a, today: today, zone: zone, firstDayOfWeek: monday) }
    private func nextStep(_ a: Attempt...) -> String? { Cheer.nextStep(a, today: today, zone: zone, firstDayOfWeek: monday) }
    private func forResult(_ all: [Attempt], _ one: Attempt) -> [Celebration] {
        Cheer.forResult(all, one, zone: zone, firstDayOfWeek: monday)
    }

    /// no attempts opens with the first Cindy
    func testNoAttemptsOpensWithTheFirstCindy() {
        XCTAssertEqual(headline(), "Your first Cindy starts everything.")
    }

    /// a record set today is announced with its score
    func testARecordSetTodayIsAnnouncedWithItsScore() {
        XCTAssertEqual(headline(attempt("2026-08-01"), attempt("2026-09-09", 15, 0)), "New personal record: 15.")
    }

    /// three days in a row is a milestone
    func testThreeDaysInARowIsAMilestone() {
        XCTAssertEqual(headline(attempt("2026-09-07", 15, 0), attempt("2026-09-08", 14, 0), attempt("2026-09-09", 13, 0)),
                       "3 days in a row.")
    }

    /// the longest streak yet is named
    func testTheLongestStreakYetIsNamed() {
        XCTAssertEqual(headline(attempt("2026-08-01", 15, 0), attempt("2026-09-08", 14, 0), attempt("2026-09-09", 13, 0)),
                       "Longest streak yet: 2 days.")
    }

    /// tying the longest streak is not called the longest yet
    func testTyingTheLongestStreakIsNotCalledTheLongestYet() {
        let earlier = ["2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04"].map { attempt($0, 15, 0) }
        let current = ["2026-09-06", "2026-09-07", "2026-09-08", "2026-09-09"].map { attempt($0, 13, 0) }
        XCTAssertNotEqual(headline(array: earlier + current), "Longest streak yet: 4 days.")
    }

    /// beating the longest streak by a day is named
    func testBeatingTheLongestStreakByADayIsNamed() {
        let earlier = ["2026-08-01", "2026-08-02", "2026-08-03"].map { attempt($0, 15, 0) }
        let current = ["2026-09-06", "2026-09-07", "2026-09-08", "2026-09-09"].map { attempt($0, 13, 0) }
        XCTAssertEqual(headline(array: earlier + current), "Longest streak yet: 4 days.")
    }

    /// a streak that yesterday kept alive invites training today
    func testAStreakThatYesterdayKeptAliveInvitesTrainingToday() {
        XCTAssertEqual(headline(attempt("2026-09-07"), attempt("2026-09-08")), "Train today to make it 3 days.")
    }

    /// three trained weeks in a row are counted
    func testThreeTrainedWeeksInARowAreCounted() {
        XCTAssertEqual(headline(attempt("2026-08-26", 15, 0), attempt("2026-09-02", 14, 0), attempt("2026-09-09", 13, 0)),
                       "3 weeks in a row.")
    }

    /// a week without a session yet says what one would make
    func testAWeekWithoutASessionYetSaysWhatOneWouldMake() {
        XCTAssertEqual(headline(attempt("2026-08-26"), attempt("2026-09-02")), "A session this week makes it 3 weeks in a row.")
    }

    /// more sessions than last week is said with the difference
    func testMoreSessionsThanLastWeekIsSaidWithTheDifference() {
        XCTAssertEqual(headline(attempt("2026-08-10", 16, 0), attempt("2026-09-07", 14, 0), attempt("2026-09-09", 13, 0)),
                       "2 sessions this week, 2 more than last week.")
    }

    /// best above the first attempt is said in reps
    func testBestAboveTheFirstAttemptIsSaidInReps() {
        XCTAssertEqual(headline(attempt("2026-08-01"), attempt("2026-08-10", 16, 20)),
                       "Your best is 100 reps above your first Cindy.")
    }

    /// otherwise the headline states the best
    func testOtherwiseTheHeadlineStatesTheBest() {
        XCTAssertEqual(headline(attempt("2026-08-01")), "Your best is 13 + 10.")
    }

    /// an adaptive category is named for what it is
    func testAnAdaptiveCategoryIsNamedForWhatItIs() {
        let knee = CindyProfile(push: .kneePushUp)
        var first = attempt("2026-08-01")
        first.profile = knee
        var best = attempt("2026-08-10", 16, 20)
        best.profile = knee
        XCTAssertEqual(headline(first, best), "Your best is 100 reps above your first Adaptive Cindy.")
    }

    /// next step counts the days to the next daily milestone
    func testNextStepCountsTheDaysToTheNextDailyMilestone() {
        XCTAssertEqual(nextStep(attempt("2026-09-08"), attempt("2026-09-09")), "1 more day to a 3-day streak.")
    }

    /// next step falls back to weeks when no day streak runs
    func testNextStepFallsBackToWeeksWhenNoDayStreakRuns() {
        XCTAssertEqual(nextStep(attempt("2026-08-26"), attempt("2026-09-02")), "2 more weeks to a 4-week streak.")
    }

    /// next step is null with nothing to count
    func testNextStepIsNullWithNothingToCount() {
        XCTAssertNil(nextStep())
    }

    /// the very first attempt is celebrated as the first
    func testTheVeryFirstAttemptIsCelebratedAsTheFirst() {
        let a = attempt("2026-09-09")
        XCTAssertEqual(forResult([a], a), [Celebration(.first, "First Cindy on the board.")])
    }

    /// a record that completes a streak milestone gives both
    func testARecordThatCompletesAStreakMilestoneGivesBoth() {
        let last = attempt("2026-09-09", 15, 0)
        let all = [attempt("2026-09-07"), attempt("2026-09-08"), last]
        XCTAssertEqual(forResult(all, last), [Celebration(.record, "New personal record."),
                                              Celebration(.daily, "3 days in a row.")])
    }

    /// a second session on the same day adds no streak line
    func testASecondSessionOnTheSameDayAddsNoStreakLine() {
        let last = attempt("2026-09-09", 12, 0, hour: 18)
        let all = [attempt("2026-09-07", 15, 0), attempt("2026-09-08", 14, 0), attempt("2026-09-09", 13, 0, hour: 8), last]
        XCTAssertTrue(forResult(all, last).isEmpty)
    }

    /// a new longest streak is celebrated
    func testANewLongestStreakIsCelebrated() {
        let last = attempt("2026-09-09", 12, 0)
        let all = [attempt("2026-08-01", 15, 0), attempt("2026-09-08", 14, 0), last]
        XCTAssertEqual(forResult(all, last), [Celebration(.daily, "Longest streak yet: 2 days.")])
    }

    /// a weekly milestone is celebrated
    func testAWeeklyMilestoneIsCelebrated() {
        let last = attempt("2026-09-09", 12, 0)
        let all = [attempt("2026-08-19", 15, 0), attempt("2026-08-26", 14, 0), attempt("2026-09-02", 13, 0), last]
        XCTAssertEqual(forResult(all, last), [Celebration(.weekly, "4 weeks in a row.")])
    }

    /// an attempt that is not stored celebrates nothing
    func testAnAttemptThatIsNotStoredCelebratesNothing() {
        let stored = attempt("2026-09-08")
        XCTAssertTrue(forResult([stored], attempt("2026-09-09")).isEmpty)
    }
}
