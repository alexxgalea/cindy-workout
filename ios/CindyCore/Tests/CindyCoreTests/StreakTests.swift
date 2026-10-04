import XCTest
import CindyCore

/// Which days were trained, and how many ran back to back. Port of `StreakTest.kt`.
final class StreakTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private let today = LocalDate(2026, 9, 9)

    private func days(_ iso: String...) -> Set<LocalDate> { Set(iso.map { LocalDate(parse: $0)! }) }

    /// An attempt at a given local date and time in `zone`.
    private func attempt(_ iso: String, hour: Int = 12, minute: Int = 0) -> Attempt {
        let at = zone.epochMs(LocalDate(parse: iso)!, hour: hour, minute: minute)
        return Attempt(rounds: 10, reps: 0, atMillis: at)
    }

    /// no training is no streak
    func testNoTrainingIsNoStreak() {
        XCTAssertEqual(Streak.current([], today: today), 0)
        XCTAssertEqual(Streak.longest([]), 0)
    }

    /// training today starts a streak of one
    func testTrainingTodayStartsAStreakOfOne() {
        XCTAssertEqual(Streak.current(days("2026-09-09"), today: today), 1)
    }

    /// consecutive days run back from today
    func testConsecutiveDaysRunBackFromToday() {
        XCTAssertEqual(Streak.current(days("2026-09-09", "2026-09-08", "2026-09-07"), today: today), 3)
    }

    /// a gap ends the streak
    func testAGapEndsTheStreak() {
        // The 6th is stranded on the far side of a missed 7th.
        XCTAssertEqual(Streak.current(days("2026-09-09", "2026-09-08", "2026-09-06"), today: today), 2)
    }

    /// yesterday keeps the streak alive through today
    func testYesterdayKeepsTheStreakAliveThroughToday() {
        // At nine in the morning the streak is not broken; it is merely not extended yet.
        XCTAssertEqual(Streak.current(days("2026-09-08", "2026-09-07"), today: today), 2)
        XCTAssertTrue(Streak.atRisk(days("2026-09-08"), today: today))
    }

    /// two days off does break it
    func testTwoDaysOffDoesBreakIt() {
        XCTAssertEqual(Streak.current(days("2026-09-07", "2026-09-06"), today: today), 0)
    }

    /// training today is not at risk
    func testTrainingTodayIsNotAtRisk() {
        XCTAssertFalse(Streak.atRisk(days("2026-09-09", "2026-09-08"), today: today))
    }

    /// the longest run is found wherever it sits
    func testTheLongestRunIsFoundWhereverItSits() {
        let trained = days(
            "2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04",  // four
            "2026-08-20", "2026-08-21",                              // two
            "2026-09-09"                                             // one
        )
        XCTAssertEqual(Streak.longest(trained), 4)
        XCTAssertEqual(Streak.current(trained, today: today), 1)
    }

    /// a run is counted once, not once per day in it
    func testARunIsCountedOnceNotOncePerDayInIt() {
        XCTAssertEqual(Streak.longest(days("2026-09-01", "2026-09-02", "2026-09-03")), 3)
    }

    /// two attempts on one day are one day
    func testTwoAttemptsOnOneDayAreOneDay() {
        let trained = Streak.daysTrained([attempt("2026-09-09", hour: 7), attempt("2026-09-09", hour: 19)], zone: zone)
        XCTAssertEqual(trained.count, 1)
        XCTAssertEqual(Streak.current(trained, today: today), 1)
    }

    /// either side of midnight is two days, not twenty minutes
    func testEitherSideOfMidnightIsTwoDaysNotTwentyMinutes() {
        let trained = Streak.daysTrained(
            [attempt("2026-09-08", hour: 23, minute: 50), attempt("2026-09-09", hour: 0, minute: 10)], zone: zone)
        XCTAssertEqual(trained.count, 2)
        XCTAssertEqual(Streak.current(trained, today: today), 2, "twenty minutes apart, but a two-day streak")
    }

    /// days are the athlete's local days, not UTC ones
    func testDaysAreTheAthletesLocalDaysNotUTCOnes() {
        // 00:30 local on the 9th in Bucharest is still the 8th in UTC.
        let trained = Streak.daysTrained([attempt("2026-09-09", hour: 0, minute: 30)], zone: zone)
        XCTAssertEqual(trained, [LocalDate(2026, 9, 9)])
    }

    private let monday = DayOfWeek.monday

    private func weeks(_ iso: String...) -> Set<LocalDate> { Set(iso.map { LocalDate(parse: $0)! }) }

    /// weeks start where the locale says
    func testWeeksStartWhereTheLocaleSays() {
        XCTAssertEqual(Streak.weekStart(today, firstDayOfWeek: .monday), LocalDate(2026, 9, 7))
        XCTAssertEqual(Streak.weekStart(today, firstDayOfWeek: .sunday), LocalDate(2026, 9, 6))
    }

    /// a session a week is a weekly streak
    func testASessionAWeekIsAWeeklyStreak() {
        let w = Streak.weeksTrained(days("2026-08-26", "2026-09-01", "2026-09-09"), firstDayOfWeek: monday)
        XCTAssertEqual(Streak.currentWeeks(w, today: today, firstDayOfWeek: monday), 3)
    }

    /// last week keeps the weekly streak alive
    func testLastWeekKeepsTheWeeklyStreakAlive() {
        let w = Streak.weeksTrained(days("2026-08-26", "2026-09-01"), firstDayOfWeek: monday)
        XCTAssertEqual(Streak.currentWeeks(w, today: today, firstDayOfWeek: monday), 2)
        XCTAssertTrue(Streak.weekAtRisk(w, today: today, firstDayOfWeek: monday))
    }

    /// a week off breaks the weekly streak
    func testAWeekOffBreaksTheWeeklyStreak() {
        let w = Streak.weeksTrained(days("2026-08-19", "2026-08-26"), firstDayOfWeek: monday)
        XCTAssertEqual(Streak.currentWeeks(w, today: today, firstDayOfWeek: monday), 0)
    }

    /// training this week is not a week at risk
    func testTrainingThisWeekIsNotAWeekAtRisk() {
        let w = Streak.weeksTrained(days("2026-09-01", "2026-09-08"), firstDayOfWeek: monday)
        XCTAssertFalse(Streak.weekAtRisk(w, today: today, firstDayOfWeek: monday))
    }

    /// the locale decides which week a Sunday is in
    func testTheLocaleDecidesWhichWeekASundayIsIn() {
        let trained = days("2026-09-06", "2026-09-07")
        let mon = Streak.weeksTrained(trained, firstDayOfWeek: .monday)
        XCTAssertEqual(mon.count, 2)
        XCTAssertEqual(Streak.longestWeeks(mon), 2)
        XCTAssertEqual(Streak.weeksTrained(trained, firstDayOfWeek: .sunday).count, 1)
    }

    /// a weekly streak crosses the new year
    func testAWeeklyStreakCrossesTheNewYear() {
        let w = Streak.weeksTrained(days("2025-12-30", "2026-01-06"), firstDayOfWeek: monday)
        XCTAssertEqual(Streak.longestWeeks(w), 2)
    }

    /// the longest weekly run is found wherever it sits
    func testTheLongestWeeklyRunIsFoundWhereverItSits() {
        let w = weeks("2026-07-06", "2026-07-13", "2026-07-20", "2026-08-31")
        XCTAssertEqual(Streak.longestWeeks(w), 3)
    }

    /// the current run lists its days
    func testTheCurrentRunListsItsDays() {
        let trained = days("2026-09-05", "2026-09-07", "2026-09-08", "2026-09-09")
        let run = days("2026-09-07", "2026-09-08", "2026-09-09")
        XCTAssertEqual(Streak.currentRun(trained, today: today), run)
        XCTAssertEqual(Streak.currentRun(trained, today: LocalDate(2026, 9, 10)), run)
    }

    /// no current run is empty
    func testNoCurrentRunIsEmpty() {
        XCTAssertTrue(Streak.currentRun(days("2026-09-01"), today: today).isEmpty)
    }

    /// the longest run knows where it was
    func testTheLongestRunKnowsWhereItWas() {
        let trained = days(
            "2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04",
            "2026-08-20", "2026-08-21",
            "2026-09-09"
        )
        XCTAssertEqual(Streak.longestRun(trained), LocalDate(2026, 8, 1)...LocalDate(2026, 8, 4))
        XCTAssertNil(Streak.longestRun([]))
    }

    /// a tie goes to the most recent run
    func testATieGoesToTheMostRecentRun() {
        let trained = days("2026-08-01", "2026-08-02", "2026-08-10", "2026-08-11")
        XCTAssertEqual(Streak.longestRun(trained), LocalDate(2026, 8, 10)...LocalDate(2026, 8, 11))
    }

    /// the longest weekly run knows where it was
    func testTheLongestWeeklyRunKnowsWhereItWas() {
        let w = weeks("2026-07-06", "2026-07-13", "2026-08-31")
        XCTAssertEqual(Streak.longestWeeksRun(w), LocalDate(2026, 7, 6)...LocalDate(2026, 7, 13))
    }

    /// milestones
    func testMilestones() {
        XCTAssertEqual(Streak.nextMilestone(0, Streak.dailyMilestones), 3)
        XCTAssertEqual(Streak.nextMilestone(3, Streak.dailyMilestones), 7)
        XCTAssertNil(Streak.nextMilestone(365, Streak.dailyMilestones))
        XCTAssertTrue(Streak.isMilestone(7, Streak.dailyMilestones))
        XCTAssertFalse(Streak.isMilestone(8, Streak.dailyMilestones))
        XCTAssertEqual(Streak.nextMilestone(1, Streak.weeklyMilestones), 2)
    }

    // MARK: boundaries the Kotlin tests leave open (written for the port)

    /// a tie between weekly runs goes to the most recent, as it does between daily ones
    func testATieBetweenWeeklyRunsGoesToTheMostRecent() {
        let w = weeks("2026-07-06", "2026-07-13", "2026-08-10", "2026-08-17")
        XCTAssertEqual(Streak.longestWeeksRun(w), LocalDate(2026, 8, 10)...LocalDate(2026, 8, 17))
    }

    /// the milestones are the ones the app celebrates
    func testTheMilestonesAreTheOnesTheAppCelebrates() {
        XCTAssertEqual(Streak.dailyMilestones, [3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 365])
        XCTAssertEqual(Streak.weeklyMilestones, [2, 4, 8, 12, 26, 52])
        XCTAssertEqual(Streak.nextMilestone(13, Streak.dailyMilestones), 14)
        XCTAssertEqual(Streak.nextMilestone(14, Streak.dailyMilestones), 21)
        XCTAssertNil(Streak.nextMilestone(52, Streak.weeklyMilestones))
    }
}
