import XCTest
import CindyCore

/// The personal-best board. Port of `PeaksTest.kt`.
final class PeaksTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private let today = LocalDate(2026, 9, 9)
    private let monday = DayOfWeek.monday
    private let knee = CindyProfile(push: .kneePushUp)

    private func attempt(_ iso: String, _ rounds: Int, reps: Int = 0, profile: CindyProfile? = CindyProfile.standard,
                         durationMs: Int64 = 20 * 60_000, splits: [Int64]? = nil, untrackedMs: Int64 = 0) -> Attempt {
        let at = zone.epochMs(LocalDate(parse: iso)!, hour: 12)
        return Attempt(rounds: rounds, reps: reps, atMillis: at, durationMs: durationMs,
                       roundSplitsMs: splits ?? Array(repeating: 60_000, count: rounds),
                       profile: profile, untrackedMs: untrackedMs)
    }

    private func peaks(_ attempts: [Attempt], category: CindyProfile? = CindyProfile.standard) -> [Peak] {
        Peaks.of(attempts, category: category, today: today, zone: zone, firstDayOfWeek: monday)
    }

    private func titled(_ list: [Peak], _ title: String) -> Peak? { list.first { $0.title == title } }

    /// no attempts gives no peaks
    func testNoAttemptsGivesNoPeaks() {
        XCTAssertTrue(peaks([]).isEmpty)
    }

    /// top three scores come in order and a tie goes to the more recent
    func testTopThreeScoresComeInOrderAndATieGoesToTheMoreRecent() {
        let list = peaks([attempt("2026-08-01", 10), attempt("2026-08-03", 12),
                          attempt("2026-08-05", 12), attempt("2026-08-07", 8)])
        let top = Array(list.prefix(3))
        XCTAssertEqual(top.map { $0.title }, ["Best score", "2nd best", "3rd best"])
        XCTAssertEqual(top.map { $0.rank }, [1, 2, 3])
        XCTAssertEqual(top.map { $0.value }, ["12", "12", "10"])
        XCTAssertEqual(top[0].detail, "5 Aug 2026 · 360 reps")
        XCTAssertEqual(top[1].detail, "3 Aug 2026 · 360 reps")
    }

    /// a score with extra reps is labelled with them
    func testAScoreWithExtraRepsIsLabelledWithThem() {
        let list = peaks([attempt("2026-08-01", 10, reps: 5)])
        XCTAssertEqual(list[0].value, "10 + 5")
        XCTAssertEqual(list[0].detail, "1 Aug 2026 · 305 reps")
    }

    /// lower bound attempts are left out of scores and rounds
    func testLowerBoundAttemptsAreLeftOutOfScoresAndRounds() {
        let list = peaks([attempt("2026-08-01", 10),
                          attempt("2026-08-02", 20, splits: [1_000], untrackedMs: 60_000)])
        XCTAssertEqual(titled(list, "Best score")!.value, "10")
        XCTAssertNil(titled(list, "2nd best"))
        XCTAssertEqual(titled(list, "Fastest round")!.value, "1:00")
    }

    /// another category is left out of scores but counted in streaks and weeks
    func testAnotherCategoryIsLeftOutOfScoresButCountedInStreaksAndWeeks() {
        let all = [attempt("2026-08-03", 10), attempt("2026-08-04", 30, profile: knee), attempt("2026-08-05", 30, profile: knee)]
        let list = peaks(all)
        XCTAssertEqual(titled(list, "Best score")!.value, "10")
        XCTAssertNil(titled(list, "2nd best"))
        XCTAssertEqual(titled(list, "Longest daily streak")!.value, "3 days")
        XCTAssertEqual(titled(list, "Biggest week")!.value, "3 sessions")
        XCTAssertNil(titled(list, "Most reps in a week"))
    }

    /// fastest round names the round
    func testFastestRoundNamesTheRound() {
        let list = peaks([attempt("2026-08-01", 3, splits: [70_000, 55_000, 62_000])])
        let fastest = titled(list, "Fastest round")!
        XCTAssertEqual(fastest.value, "0:55")
        XCTAssertEqual(fastest.detail, "1 Aug 2026 · round 2")
        XCTAssertEqual(fastest.rank, 1)
    }

    /// fastest round tie goes to the more recent attempt
    func testFastestRoundTieGoesToTheMoreRecentAttempt() {
        let list = peaks([attempt("2026-08-01", 1, splits: [50_000]), attempt("2026-08-09", 1, splits: [50_000])])
        XCTAssertEqual(titled(list, "Fastest round")!.detail, "9 Aug 2026 · round 1")
    }

    /// best average round ignores a session stopped early
    func testBestAverageRoundIgnoresASessionStoppedEarly() {
        let list = peaks([attempt("2026-08-01", 10, splits: Array(repeating: 100_000, count: 10)),
                          attempt("2026-08-02", 3, durationMs: 5 * 60_000, splits: Array(repeating: 30_000, count: 3))])
        let best = titled(list, "Best average round")!
        XCTAssertEqual(best.value, "1:40")
        XCTAssertEqual(best.detail, "1 Aug 2026 · 10 rounds")
        XCTAssertEqual(titled(list, "Fastest round")!.value, "0:30")
    }

    /// best average round tie goes to the more recent session
    func testBestAverageRoundTieGoesToTheMoreRecentSession() {
        let list = peaks([attempt("2026-08-01", 10), attempt("2026-08-09", 10)])
        XCTAssertEqual(titled(list, "Best average round")!.detail, "9 Aug 2026 · 10 rounds")
    }

    /// a one day streak gives no streak peak
    func testAOneDayStreakGivesNoStreakPeak() {
        let list = peaks([attempt("2026-09-09", 10), attempt("2026-08-01", 10)])
        XCTAssertNil(titled(list, "Longest daily streak"))
        XCTAssertNil(titled(list, "Longest weekly streak"))
    }

    /// a daily streak ending today or yesterday is running now
    func testADailyStreakEndingTodayOrYesterdayIsRunningNow() {
        for last in ["2026-09-09", "2026-09-08"] {
            let end = LocalDate(parse: last)!
            let list = peaks([attempt(end.minusDays(1).description, 10), attempt(last, 10)])
            let streak = titled(list, "Longest daily streak")!
            XCTAssertEqual(streak.value, "2 days")
            XCTAssertEqual(streak.detail, "Running now")
        }
    }

    /// an old daily streak says when it ended
    func testAnOldDailyStreakSaysWhenItEnded() {
        let list = peaks([attempt("2026-08-03", 10), attempt("2026-08-04", 10)])
        XCTAssertEqual(titled(list, "Longest daily streak")!.detail, "Ended 4 Aug 2026")
    }

    /// weekly streak is running now through last week and ended after that
    func testWeeklyStreakIsRunningNowThroughLastWeekAndEndedAfterThat() {
        let recent = peaks([attempt("2026-08-26", 10), attempt("2026-09-02", 10)])
        let streak = titled(recent, "Longest weekly streak")!
        XCTAssertEqual(streak.value, "2 weeks")
        XCTAssertEqual(streak.detail, "Running now")

        let old = peaks([attempt("2026-08-05", 10), attempt("2026-08-12", 10)])
        XCTAssertEqual(titled(old, "Longest weekly streak")!.detail, "Ended week of 10 Aug 2026")
    }

    /// biggest week tie goes to the more recent week
    func testBiggestWeekTieGoesToTheMoreRecentWeek() {
        let list = peaks([attempt("2026-08-03", 10), attempt("2026-08-04", 10),
                          attempt("2026-08-17", 10), attempt("2026-08-18", 10)])
        let week = titled(list, "Biggest week")!
        XCTAssertEqual(week.value, "2 sessions")
        XCTAssertEqual(week.detail, "Week of 17 Aug 2026")
    }

    /// most reps in a week is absent when only one week was trained
    func testMostRepsInAWeekIsAbsentWhenOnlyOneWeekWasTrained() {
        let list = peaks([attempt("2026-08-03", 10), attempt("2026-08-04", 10)])
        XCTAssertNil(titled(list, "Most reps in a week"))
        XCTAssertNotNil(titled(list, "Biggest week"))
    }

    /// most reps in a week sums the week and ties go to the more recent
    func testMostRepsInAWeekSumsTheWeekAndTiesGoToTheMoreRecent() {
        let list = peaks([attempt("2026-08-03", 10), attempt("2026-08-04", 10),
                          attempt("2026-08-17", 20), attempt("2026-09-01", 5)])
        let reps = titled(list, "Most reps in a week")!
        XCTAssertEqual(reps.value, "600 reps")
        XCTAssertEqual(reps.detail, "Week of 17 Aug 2026")
        XCTAssertFalse(list.contains { !(1...3).contains($0.rank) })
    }

    private func withSets(_ base: Attempt, _ sets: SetSplit...) -> Attempt {
        var copy = base
        copy.setSplits = sets
        return copy
    }

    private func pull(_ ms: Int64, reps: Int = 5, manual: Int = 0) -> SetSplit {
        SetSplit(.pullup, ms, reps, manual)
    }

    /// the fastest measured set of each movement peaks with the right plural
    func testTheFastestMeasuredSetOfEachMovementPeaksWithTheRightPlural() {
        let a = withSets(attempt("2026-08-03", 10),
                         pull(15_000), SetSplit(.pushup, 17_000, 10, 0), SetSplit(.squat, 21_000, 15, 0), pull(13_500))
        let list = peaks([a])
        let fastPull = titled(list, "Fastest 5 strict pull-ups")!
        XCTAssertEqual(fastPull.value, "0:13")
        XCTAssertEqual(fastPull.detail, "3 Aug 2026")
        XCTAssertEqual(fastPull.rank, 1)
        XCTAssertEqual(titled(list, "Fastest 10 standard push-ups")!.value, "0:17")
        XCTAssertEqual(titled(list, "Fastest 15 air squats")!.value, "0:21")
        let firstSetPeak = list.firstIndex { $0.title.hasPrefix("Fastest 5") }!
        XCTAssertEqual(list[firstSetPeak - 1].title, "Best average round")
    }

    /// the title uses the plural of the category
    func testTheTitleUsesThePluralOfTheCategory() {
        let a = withSets(attempt("2026-08-03", 10, profile: knee), SetSplit(.pushup, 9_000, 10, 0))
        XCTAssertTrue(peaks([a], category: knee).contains { $0.title == "Fastest 10 \(knee.push.plural)" })
    }

    /// manual and skipped sets never peak
    func testManualAndSkippedSetsNeverPeak() {
        let a = withSets(attempt("2026-08-03", 10), pull(9_000, manual: 1), pull(8_000, reps: 3), pull(20_000))
        XCTAssertEqual(titled(peaks([a]), "Fastest 5 strict pull-ups")!.value, "0:20")
        let none = withSets(attempt("2026-08-03", 10), pull(9_000, manual: 5))
        XCTAssertNil(titled(peaks([none]), "Fastest 5 strict pull-ups"))
    }

    /// a lower-bound attempt never peaks a set
    func testALowerBoundAttemptNeverPeaksASet() {
        let lost = withSets(attempt("2026-08-03", 10, untrackedMs: 30_000), pull(9_000))
        let ok = withSets(attempt("2026-08-04", 10), pull(15_000))
        XCTAssertEqual(titled(peaks([lost, ok]), "Fastest 5 strict pull-ups")!.value, "0:15")
        XCTAssertNil(titled(peaks([lost]), "Fastest 5 strict pull-ups"))
    }

    /// no category gives no set peaks
    func testNoCategoryGivesNoSetPeaks() {
        let a = withSets(attempt("2026-08-03", 10, profile: nil), pull(9_000))
        XCTAssertFalse(peaks([a], category: nil).contains { $0.title.hasPrefix("Fastest ") && $0.title != "Fastest round" })
    }

    /// a tied set goes to the more recent attempt
    func testATiedSetGoesToTheMoreRecentAttempt() {
        let older = withSets(attempt("2026-08-03", 10), pull(14_000))
        let newer = withSets(attempt("2026-08-10", 10), pull(14_000))
        XCTAssertEqual(titled(peaks([older, newer]), "Fastest 5 strict pull-ups")!.detail, "10 Aug 2026")
        XCTAssertEqual(titled(peaks([newer, older]), "Fastest 5 strict pull-ups")!.detail, "10 Aug 2026")
    }
}
