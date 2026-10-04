import XCTest
import CindyCore

/// The numbers behind the progress chart and the week card. Port of `ProgressTest.kt`.
final class ProgressTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private let today = LocalDate(2026, 9, 9)
    private let monday = DayOfWeek.monday
    private let knee = CindyProfile(push: .kneePushUp)
    private let standard: CindyProfile? = CindyProfile.standard

    private func attempt(_ iso: String, rounds: Int, reps: Int = 0, hour: Int = 12,
                         profile: CindyProfile? = CindyProfile.standard,
                         durationMs: Int64 = 20 * 60_000, splits: [Int64]? = nil,
                         untrackedMs: Int64 = 0) -> Attempt {
        let at = zone.epochMs(LocalDate(parse: iso)!, hour: hour)
        return Attempt(rounds: rounds, reps: reps, atMillis: at, durationMs: durationMs,
                       roundSplitsMs: splits ?? Array(repeating: 60_000, count: rounds),
                       profile: profile, untrackedMs: untrackedMs)
    }

    /// An attempt worth exactly `total` reps (rounds of 30 plus the remainder).
    private func scored(_ iso: String, _ total: Int, profile: CindyProfile? = CindyProfile.standard,
                        untrackedMs: Int64 = 0) -> Attempt {
        attempt(iso, rounds: total / 30, reps: total % 30, profile: profile, untrackedMs: untrackedMs)
    }

    /// A full session whose rounds each took `seconds`.
    private func paced(_ iso: String, _ seconds: Int, durationMs: Int64 = 20 * 60_000,
                       untrackedMs: Int64 = 0) -> Attempt {
        attempt(iso, rounds: 10, durationMs: durationMs, splits: Array(repeating: Int64(seconds) * 1000, count: 10),
                untrackedMs: untrackedMs)
    }

    /// categories list the most recent first
    func testCategoriesListTheMostRecentFirst() {
        let list = [scored("2026-08-01", 400), scored("2026-08-05", 300, profile: knee), scored("2026-08-10", 410)]
        XCTAssertEqual(Progress.categories(list), [CindyProfile.standard, knee])
    }

    /// a record is flagged when it is set
    func testARecordIsFlaggedWhenItIsSet() {
        let list = [400, 380, 420, 420, 450].enumerated().map { scored("2026-08-0\($0.offset + 1)", $0.element) }
        let s = Progress.scoreSeries(list, category: standard, from: nil, zone: zone)
        XCTAssertEqual(s.points.map { $0.record }, [true, false, true, false, true])
        XCTAssertEqual(s.best, [400.0, 400.0, 420.0, 420.0, 450.0])
    }

    /// a lower-bound score is plotted but never a record
    func testALowerBoundScoreIsPlottedButNeverARecord() {
        let list = [scored("2026-08-01", 400), scored("2026-08-02", 450, untrackedMs: 60_000), scored("2026-08-03", 440)]
        let s = Progress.scoreSeries(list, category: standard, from: nil, zone: zone)
        XCTAssertEqual(s.points.map { $0.record }, [true, false, false])
        XCTAssertEqual(s.points.map { $0.lowerBound }, [false, true, false])
        XCTAssertEqual(s.best, [400.0, 450.0, 450.0])
    }

    /// other categories stay off the line
    func testOtherCategoriesStayOffTheLine() {
        let list = [scored("2026-08-01", 400), scored("2026-08-02", 300, profile: knee)]
        let s = Progress.scoreSeries(list, category: standard, from: nil, zone: zone)
        XCTAssertEqual(s.points.map { $0.value }, [400.0])
    }

    /// the range cuts points but remembers the whole history
    func testTheRangeCutsPointsButRemembersTheWholeHistory() {
        let list = [scored("2026-05-01", 500), scored("2026-09-01", 480), scored("2026-09-05", 490)]
        let from = ProgressRange.month.start(today)
        let s = Progress.scoreSeries(list, category: standard, from: from, zone: zone)
        XCTAssertEqual(s.points.map { $0.value }, [480.0, 490.0])
        XCTAssertEqual(s.points.map { $0.record }, [false, false])
        XCTAssertEqual(s.best, [500.0, 500.0])
    }

    /// pace counts full sessions only and faster is better
    func testPaceCountsFullSessionsOnlyAndFasterIsBetter() {
        let list = [paced("2026-08-01", 70), paced("2026-08-02", 65), paced("2026-08-03", 68),
                    paced("2026-08-04", 50, durationMs: 10 * 60_000)]
        let s = Progress.paceSeries(list, category: standard, from: nil, zone: zone)
        XCTAssertEqual(s.points.map { $0.value }, [70.0, 65.0, 68.0])
        XCTAssertEqual(s.points.map { $0.record }, [true, true, false])
        XCTAssertEqual(s.best, [70.0, 65.0, 65.0])
        XCTAssertTrue(s.lowerIsBetter)
    }

    /// a lower-bound pace does not lower the best line
    func testALowerBoundPaceDoesNotLowerTheBestLine() {
        let list = [paced("2026-08-01", 70), paced("2026-08-02", 60, untrackedMs: 60_000), paced("2026-08-03", 65)]
        let s = Progress.paceSeries(list, category: standard, from: nil, zone: zone)
        XCTAssertEqual(s.points.map { $0.record }, [true, false, true])
        XCTAssertEqual(s.best, [70.0, 70.0, 65.0])
        XCTAssertTrue(s.points[1].lowerBound)
    }

    /// a lower-bound first pace is shown but is not a record
    func testALowerBoundFirstPaceIsShownButIsNotARecord() {
        let list = [paced("2026-08-01", 60, untrackedMs: 60_000), paced("2026-08-02", 70)]
        let s = Progress.paceSeries(list, category: standard, from: nil, zone: zone)
        XCTAssertEqual(s.points.map { $0.record }, [false, true])
        XCTAssertEqual(s.best[0], 60.0, accuracy: 0.0)
        XCTAssertEqual(s.best[1], 70.0, accuracy: 0.0)
        XCTAssertTrue(s.best.allSatisfy { $0 < 1e9 })
    }

    /// weekly volume keeps empty weeks
    func testWeeklyVolumeKeepsEmptyWeeks() {
        let list = [scored("2026-08-17", 400), scored("2026-08-19", 410), scored("2026-09-02", 420)]
        let v = Progress.weeklyVolume(list, from: nil, today: today, zone: zone, firstDayOfWeek: monday)
        XCTAssertEqual(v.map { $0.value }, [810.0, 0.0, 420.0, 0.0])
        XCTAssertEqual(v.map { $0.sessions }, [2, 0, 1, 0])
    }

    /// weekly volume starts at the range
    func testWeeklyVolumeStartsAtTheRange() {
        let list = [scored("2026-08-17", 400), scored("2026-09-02", 420)]
        let v = Progress.weeklyVolume(list, from: LocalDate(2026, 8, 26), today: today, zone: zone, firstDayOfWeek: monday)
        let first = zone.epochMs(LocalDate(2026, 8, 24))
        XCTAssertEqual(v.first!.atMillis, first)
    }

    /// the summary compares this week with last
    func testTheSummaryComparesThisWeekWithLast() {
        let list = [scored("2026-09-07", 400), scored("2026-09-09", 420), scored("2026-09-01", 390)]
        let s = Progress.summary(list, today: today, zone: zone, firstDayOfWeek: monday)
        XCTAssertEqual(s.thisWeek, Period(sessions: 2, reps: 820, clockMs: 40 * 60_000))
        XCTAssertEqual(s.lastWeek, Period(sessions: 1, reps: 390, clockMs: 20 * 60_000))
        XCTAssertEqual(s.thisMonth, Period(sessions: 3, reps: 1210, clockMs: 60 * 60_000))
    }

    /// the summary uses the locale's week
    func testTheSummaryUsesTheLocalesWeek() {
        let list = [scored("2026-09-06", 400)]
        XCTAssertEqual(Progress.summary(list, today: today, zone: zone, firstDayOfWeek: .sunday).thisWeek.sessions, 1)
        XCTAssertEqual(Progress.summary(list, today: today, zone: zone, firstDayOfWeek: monday).lastWeek.sessions, 1)
        XCTAssertEqual(Progress.summary(list, today: today, zone: zone, firstDayOfWeek: monday).thisWeek.sessions, 0)
    }

    /// ticks land on round numbers
    func testTicksLandOnRoundNumbers() {
        XCTAssertEqual(Progress.niceTicks(410.0, 522.0), [400.0, 450.0, 500.0, 550.0])
        XCTAssertEqual(Progress.niceTicks(62.0, 75.0), [60.0, 65.0, 70.0, 75.0])
        XCTAssertEqual(Progress.niceTicks(0.0, 3.0), [0.0, 1.0, 2.0, 3.0])
    }

    /// a flat line still gets ticks
    func testAFlatLineStillGetsTicks() {
        let t = Progress.niceTicks(500.0, 500.0)
        XCTAssertEqual(t.sorted(), t)
        XCTAssertTrue(t.contains { $0 == 500.0 })
        XCTAssertTrue((2...6).contains(t.count))
    }

    /// the nearest point wins, ties go left
    func testTheNearestPointWinsTiesGoLeft() {
        XCTAssertEqual(Progress.nearestIndex([], 3), -1)
        XCTAssertEqual(Progress.nearestIndex([10], 99), 0)
        let xs: [Float] = [10, 20, 30]
        XCTAssertEqual(Progress.nearestIndex(xs, 14), 0)
        XCTAssertEqual(Progress.nearestIndex(xs, 15), 0)
        XCTAssertEqual(Progress.nearestIndex(xs, 16), 1)
        XCTAssertEqual(Progress.nearestIndex(xs, -5), 0)
        XCTAssertEqual(Progress.nearestIndex(xs, 100), 2)
    }

    /// formats
    func testFormats() {
        XCTAssertEqual(Progress.formatReps(1490), "1,490")
        XCTAssertEqual(Progress.formatClock(0), "0 min")
        XCTAssertEqual(Progress.formatClock(42 * 60_000), "42 min")
        XCTAssertEqual(Progress.formatClock(62 * 60_000), "1 h 02 min")
        XCTAssertEqual(Progress.formatDelta(3), "+3")
        XCTAssertEqual(Progress.formatDelta(-2), "−2")
        XCTAssertNil(Progress.formatDelta(0))
    }

    private func scorePoints(_ a: Attempt...) -> [ProgressPoint] {
        Progress.scoreSeries(a, category: standard, from: nil, zone: zone).points
    }

    private func describeScore(_ points: [ProgressPoint], _ i: Int) -> Readout {
        Progress.describe(.score, points, i, zone: zone)
    }

    private func pacePoints(_ list: [Attempt]) -> [ProgressPoint] {
        Progress.paceSeries(list, category: standard, from: nil, zone: zone).points
    }

    /// describe a first score has no comparison
    func testDescribeAFirstScoreHasNoComparison() {
        let points = scorePoints(scored("2026-09-01", 400))
        let r = describeScore(points, 0)
        XCTAssertEqual(r.headline, "1 Sep · 13 + 10")
        XCTAssertEqual(r.detail, "400 reps · personal record · first in this range")
    }

    /// describe a score that beat the session before
    func testDescribeAScoreThatBeatTheSessionBefore() {
        let points = scorePoints(scored("2026-09-01", 400), scored("2026-09-03", 414))
        XCTAssertEqual(describeScore(points, 1).detail, "414 reps · personal record · +14 on the session before")
    }

    /// describe a score below the session before uses words
    func testDescribeAScoreBelowTheSessionBeforeUsesWords() {
        let points = scorePoints(scored("2026-09-01", 400), scored("2026-09-03", 394))
        XCTAssertEqual(describeScore(points, 1).detail, "394 reps · 6 below the session before")
    }

    /// describe a level score
    func testDescribeALevelScore() {
        let points = scorePoints(scored("2026-09-01", 400), scored("2026-09-03", 400))
        XCTAssertEqual(describeScore(points, 1).detail, "400 reps · level with the session before")
    }

    /// describe a lower bound says the camera lost you and is no record
    func testDescribeALowerBoundSaysTheCameraLostYouAndIsNoRecord() {
        let points = scorePoints(scored("2026-09-01", 300), scored("2026-09-03", 350, untrackedMs: 60_000))
        XCTAssertEqual(describeScore(points, 1).detail, "350 reps · at least — camera lost you · +50 on the session before")
    }

    /// describe pace says how much faster
    func testDescribePaceSaysHowMuchFaster() {
        let points = pacePoints([paced("2026-09-01", 70), paced("2026-09-03", 66)])
        let r = Progress.describe(.pace, points, 1, zone: zone)
        XCTAssertEqual(r.headline, "3 Sep · 1:06 a round")
        XCTAssertEqual(r.detail, "fastest yet · 4s faster than the session before")
    }

    /// describe pace says how much slower and has no record flag
    func testDescribePaceSaysHowMuchSlowerAndHasNoRecordFlag() {
        let points = pacePoints([paced("2026-09-01", 60), paced("2026-09-03", 63)])
        XCTAssertEqual(Progress.describe(.pace, points, 1, zone: zone).detail, "3s slower than the session before")
    }

    /// describe pace can be the same or the first
    func testDescribePaceCanBeTheSameOrTheFirst() {
        let points = pacePoints([paced("2026-09-01", 60), paced("2026-09-03", 60)])
        XCTAssertEqual(Progress.describe(.pace, points, 0, zone: zone).detail, "fastest yet · first in this range")
        XCTAssertEqual(Progress.describe(.pace, points, 1, zone: zone).detail, "same pace as the session before")
    }

    /// describe a volume bar names the week and counts sessions
    func testDescribeAVolumeBarNamesTheWeekAndCountsSessions() {
        let bars = Progress.weeklyVolume([scored("2026-09-07", 400), scored("2026-09-08", 300)],
                                         from: LocalDate(2026, 9, 7), today: today, zone: zone, firstDayOfWeek: monday)
        XCTAssertEqual(Progress.describe(.volume, bars, 0, zone: zone), Readout("Week of 7 Sep", "700 reps · 2 sessions"))
        let one = Progress.weeklyVolume([scored("2026-09-07", 1200)], from: LocalDate(2026, 9, 7), today: today,
                                        zone: zone, firstDayOfWeek: monday)
        XCTAssertEqual(Progress.describe(.volume, one, 0, zone: zone).detail, "1,200 reps · 1 session")
    }

    /// overview of nothing
    func testOverviewOfNothing() {
        for m in ProgressMetric.allCases {
            XCTAssertEqual(Progress.overview(m, []), Readout("No sessions in this range", ""))
        }
    }

    /// overview of scores skips a lower bound unless all are
    func testOverviewOfScoresSkipsALowerBoundUnlessAllAre() {
        let mixed = scorePoints(scored("2026-09-01", 300), scored("2026-09-03", 500, untrackedMs: 60_000))
        XCTAssertEqual(Progress.overview(.score, mixed), Readout("Best 10", "2 sessions in this range"))
        let only = scorePoints(scored("2026-09-03", 500, untrackedMs: 60_000))
        XCTAssertEqual(Progress.overview(.score, only), Readout("Best 16 + 20", "1 session in this range"))
    }

    /// overview of pace names the fastest round
    func testOverviewOfPaceNamesTheFastestRound() {
        let points = pacePoints([paced("2026-09-01", 70), paced("2026-09-03", 66), paced("2026-09-05", 68)])
        XCTAssertEqual(Progress.overview(.pace, points), Readout("Best 1:06 a round", "3 full sessions in this range"))
        XCTAssertEqual(Progress.overview(.pace, Array(points.prefix(1))).detail, "1 full session in this range")
    }

    /// overview of volume totals the bars
    func testOverviewOfVolumeTotalsTheBars() {
        let bars = Progress.weeklyVolume([scored("2026-08-31", 400), scored("2026-09-08", 900)],
                                         from: LocalDate(2026, 8, 31), today: today, zone: zone, firstDayOfWeek: monday)
        XCTAssertEqual(Progress.overview(.volume, bars), Readout("1,300 reps", "2 sessions in this range"))
    }

    // MARK: boundaries the Kotlin tests leave open (written for the port)

    /// a second short of the whole clock is not a full session, and the whole clock less the slack is
    func testASecondShortOfTheWholeClockIsNotAFullSession() {
        XCTAssertTrue(Progress.isFullSession(attempt("2026-08-01", rounds: 1, durationMs: 1_199_000)))
        XCTAssertFalse(Progress.isFullSession(attempt("2026-08-01", rounds: 1, durationMs: 1_198_999)))
        XCTAssertEqual(Progress.fullSessionMs, 1_199_000)
    }

    /// a session that counted nothing is never a record
    func testASessionThatCountedNothingIsNeverARecord() {
        let list = [attempt("2026-08-01", rounds: 0, reps: 0), scored("2026-08-02", 10)]
        let s = Progress.scoreSeries(list, category: standard, from: nil, zone: zone)
        XCTAssertEqual(s.points.map { $0.record }, [false, true])
    }

    /// ticks at exactly twice the magnitude still step by two
    func testTicksAtExactlyTwiceTheMagnitudeStillStepByTwo() {
        XCTAssertEqual(Progress.niceTicks(0, 8), [0.0, 2.0, 4.0, 6.0, 8.0])
        XCTAssertEqual(Progress.niceTicks(0, 4), [0.0, 1.0, 2.0, 3.0, 4.0])
        XCTAssertEqual(Progress.niceTicks(0, 20), [0.0, 5.0, 10.0, 15.0, 20.0])
    }

    /// an hour on the clock is "1 h 00 min", not "60 min"
    func testAnHourOnTheClockIsOneHour() {
        XCTAssertEqual(Progress.formatClock(60 * 60_000), "1 h 00 min")
        XCTAssertEqual(Progress.formatClock(59 * 60_000 + 59_999), "59 min")
        XCTAssertEqual(Progress.formatClock(125 * 60_000), "2 h 05 min")
    }

    /// categories are listed by the latest use of each, whichever was used first
    func testCategoriesAreListedByTheLatestUseOfEachWhicheverWasUsedFirst() {
        let list = [scored("2026-08-01", 400), scored("2026-08-10", 300, profile: knee)]
        XCTAssertEqual(Progress.categories(list), [knee, CindyProfile.standard])
        XCTAssertEqual(Progress.defaultCategory(list), knee)
    }

    /// each range starts where its label says
    func testEachRangeStartsWhereItsLabelSays() {
        XCTAssertEqual(ProgressRange.month.start(today), LocalDate(2026, 8, 9))
        XCTAssertEqual(ProgressRange.quarter.start(today), LocalDate(2026, 6, 9))
        XCTAssertEqual(ProgressRange.year.start(today), LocalDate(2025, 9, 9))
        XCTAssertNil(ProgressRange.all.start(today))
        XCTAssertEqual(ProgressRange.allCases.map { $0.label }, ["1M", "3M", "1Y", "All"])
        XCTAssertEqual(ProgressMetric.allCases.map { $0.label }, ["Score", "Pace", "Volume"])
    }
}
