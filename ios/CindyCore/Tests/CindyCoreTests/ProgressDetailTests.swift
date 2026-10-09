import XCTest
@testable import CindyCore

/// What the Progress screen says beyond the Robolectric smoke tests: the streak columns, the week
/// tiles, the calendar's paging, the leaderboard's ranks, the chart card's words and the question
/// CLEAR asks. Written for the port, from the lines of `RecordsActivity` that decide each.
final class ProgressDetailTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private lazy var today = LocalDate(2026, 10, 8)   // a Thursday
    private lazy var now = zone.epochMs(today, hour: 12)
    private let day: Int64 = 24 * 60 * 60 * 1000

    private func attempt(_ rounds: Int, at: Int64, reps: Int = 0, profile: CindyProfile? = .standard,
                         untrackedMs: Int64 = 0, durationMs: Int64 = 20 * 60_000, splits: Bool = true) -> Attempt {
        Attempt(rounds: rounds, reps: reps, atMillis: at, durationMs: durationMs,
                roundSplitsMs: splits ? (0..<rounds).map { 60_000 + Int64($0) * 500 } : [], profile: profile,
                untrackedMs: untrackedMs)
    }

    private func input(_ attempts: [Attempt], name: String? = nil, is24Hour: Bool = true) -> ProgressInput {
        ProgressInput(attempts: attempts, today: today, nowMs: now, zone: zone, firstDayOfWeek: .monday,
                      displayName: name, is24Hour: is24Hour)
    }

    private func model(_ attempts: [Attempt], name: String? = nil, is24Hour: Bool = true) -> ProgressModel {
        ProgressModel(input(attempts, name: name, is24Hour: is24Hour))
    }

    // MARK: the habit

    /// Both streaks are read as one sentence each, and only the daily one carries a flame.
    func testTheStreakColumnsAreReadAsOneSentenceEach() {
        let p = model([attempt(12, at: now - day), attempt(13, at: now)]).page.hero

        XCTAssertEqual(p.daily, StreakColumn(label: "DAILY STREAK", value: 2, unit: "days", flame: true,
                                             spoken: "Daily streak: 2 days"))
        XCTAssertEqual(p.weekly, StreakColumn(label: "WEEKLY STREAK", value: 1, unit: "week", flame: false,
                                              spoken: "Weekly streak: 1 week"))
        XCTAssertEqual(p.weekStart, LocalDate(2026, 10, 5))
        XCTAssertEqual(p.trained, [LocalDate(2026, 10, 7), today])
        XCTAssertEqual(p.tally, "2 days trained · 2 sessions")
    }

    /// One day and one session are singular.
    func testOneDayAndOneSessionAreSingular() {
        let p = model([attempt(12, at: now)]).page.hero
        XCTAssertEqual(p.daily?.unit, "day")
        XCTAssertEqual(p.tally, "1 day trained · 1 session")
    }

    /// A streak that has lapsed is a zero, said as a zero.
    func testALapsedStreakIsAZero() {
        let p = model([attempt(12, at: now - 5 * day)]).page.hero
        XCTAssertEqual(p.daily?.value, 0)
        XCTAssertEqual(p.daily?.unit, "days")
        XCTAssertEqual(p.daily?.spoken, "Daily streak: 0 days")
    }

    /// The next step is whatever Cheer says it is, and absent when it has nothing to say.
    func testTheNextStepIsCheers() {
        let a = [attempt(12, at: now - day), attempt(13, at: now)]
        XCTAssertEqual(model(a).page.hero.nextStep,
                       Cheer.nextStep(a, today: today, zone: zone, firstDayOfWeek: .monday))
    }

    // MARK: this week

    /// Each tile says its figure and how it moved since last week; the time tile in minutes.
    func testTheWeekTilesSayHowTheyMoved() {
        // Last week: one 20-minute session of 12 rounds. This week: two, of 13 and 14.
        let a = [attempt(12, at: now - 7 * day), attempt(13, at: now - day), attempt(14, at: now)]
        let tiles = model(a).page.thisWeek!.tiles

        XCTAssertEqual(tiles.map { $0.label }, ["Sessions", "Reps", "Time"])
        XCTAssertEqual(tiles[0].value, "2")
        XCTAssertEqual(tiles[0].change, "+1")
        XCTAssertTrue(tiles[0].up)
        XCTAssertEqual(tiles[0].spoken, "Sessions this week: 2, 1 more than last week")
        XCTAssertEqual(tiles[1].value, "810")
        XCTAssertEqual(tiles[1].change, "+450")
        XCTAssertEqual(tiles[2].value, "40 min")
        XCTAssertEqual(tiles[2].change, "+20 min")
        XCTAssertEqual(tiles[2].spoken, "Time this week: 40 min, 20 min more than last week")
    }

    /// A tile that fell is quiet and says so; one that did not move says nothing.
    func testATileThatFellIsQuietAndOneThatDidNotMoveSaysNothing() {
        let a = [attempt(12, at: now - 7 * day), attempt(12, at: now - 6 * day), attempt(12, at: now)]
        let tiles = model(a).page.thisWeek!.tiles

        XCTAssertEqual(tiles[0].change, "−1")
        XCTAssertFalse(tiles[0].up)
        XCTAssertEqual(tiles[0].spoken, "Sessions this week: 1, 1 fewer than last week")

        let level = model([attempt(12, at: now - 7 * day), attempt(12, at: now)]).page.thisWeek!.tiles
        XCTAssertNil(level[0].change)
        XCTAssertEqual(level[0].spoken, "Sessions this week: 1")
    }

    /// The month so far is a footnote, singular where it is one.
    func testTheMonthSoFarIsAFootnote() {
        XCTAssertEqual(model([attempt(12, at: now)]).page.thisWeek!.monthNote,
                       "This month: 1 session · 360 reps · 20 min.")
        XCTAssertEqual(model([attempt(12, at: now), attempt(12, at: now - day)]).page.thisWeek!.monthNote,
                       "This month: 2 sessions · 720 reps · 40 min.")
    }

    // MARK: peaks

    /// The peaks are read with their value, and the footnote says what they are compared with.
    func testThePeaksAreReadWithTheirValue() {
        let p = model([attempt(12, at: now - day), attempt(14, at: now)]).page.peaks!

        XCTAssertEqual(p.rows[0].title, "Best score")
        XCTAssertEqual(p.rows[0].rank, 1)
        XCTAssertEqual(p.rows[0].spoken, "Best score, 14, 8 Oct 2026 · 420 reps")
        XCTAssertTrue(p.footnote.hasPrefix("Scores and rounds are compared only with sessions at the same movements."))
        XCTAssertTrue(p.footnote.hasSuffix("Streaks and weeks count everything."))
    }

    /// Choosing another kind of Cindy turns the peaks to it, and keeps it when the board changes.
    func testChoosingAnotherCategoryTurnsThePeaksToIt() {
        let knee = CindyProfile(push: .kneePushUp)
        let a = [attempt(12, at: now - 3 * day), attempt(20, at: now - 2 * day, profile: knee), attempt(14, at: now)]
        let m = model(a)
        XCTAssertEqual(m.page.peaks?.rows[0].value, "14")

        m.chooseCategory(1)

        XCTAssertEqual(m.page.progress?.category, 1)
        XCTAssertEqual(m.page.peaks?.rows[0].value, "20")
        m.reload(a + [attempt(15, at: now + 1000)])
        XCTAssertEqual(m.page.peaks?.rows[0].value, "20", "a chosen category stays chosen")
        // Choosing the one already shown builds nothing.
        var builds = 0
        m.onChange = { builds += 1 }
        m.chooseCategory(1)
        XCTAssertEqual(builds, 0)
    }

    /// Until one is chosen the category follows the latest session.
    func testTheCategoryFollowsTheLatestUntilChosen() {
        let knee = CindyProfile(push: .kneePushUp)
        let m = model([attempt(12, at: now - 3 * day), attempt(20, at: now - 2 * day, profile: knee)])
        XCTAssertEqual(m.category, knee)
        m.reload([attempt(12, at: now - 3 * day), attempt(20, at: now - 2 * day, profile: knee), attempt(13, at: now)])
        XCTAssertEqual(m.category, .standard)
    }

    // MARK: the calendar

    /// The calendar opens on this month and pages back as far as the first trained month.
    func testTheCalendarPagesBackToTheFirstTrainedMonthAndNoFurtherThanNow() {
        let m = model([attempt(12, at: zone.epochMs(LocalDate(2026, 8, 20), hour: 12)), attempt(12, at: now)])
        var c = m.page.calendar!
        XCTAssertEqual(c.month, YearMonth(2026, 10))
        XCTAssertTrue(c.canGoBack)
        XCTAssertFalse(c.canGoForward)

        m.showNextMonth()
        XCTAssertEqual(m.page.calendar?.month, YearMonth(2026, 10))

        m.showPreviousMonth()
        m.showPreviousMonth()
        c = m.page.calendar!
        XCTAssertEqual(c.month, YearMonth(2026, 8))
        XCTAssertFalse(c.canGoBack)
        XCTAssertTrue(c.canGoForward)

        m.showPreviousMonth()
        XCTAssertEqual(m.page.calendar?.month, YearMonth(2026, 8), "no month before the first session")

        m.showNextMonth()
        XCTAssertEqual(m.page.calendar?.month, YearMonth(2026, 9))
    }

    /// Paging across a year end.
    func testPagingCrossesAYearEnd() {
        let m = ProgressModel(ProgressInput(attempts: [attempt(12, at: zone.epochMs(LocalDate(2025, 11, 20), hour: 12))],
                                            today: LocalDate(2026, 1, 15), nowMs: now, zone: zone, firstDayOfWeek: .monday))
        m.showPreviousMonth()
        XCTAssertEqual(m.page.calendar?.month, YearMonth(2025, 12))
        m.showPreviousMonth()
        XCTAssertEqual(m.page.calendar?.month, YearMonth(2025, 11))
    }

    /// The calendar knows the trained days, and the current run to paint in the earned colour.
    func testTheCalendarKnowsTheTrainedDaysAndTheCurrentRun() {
        let a = [attempt(12, at: now - 5 * day), attempt(12, at: now - day), attempt(12, at: now)]
        let c = model(a).page.calendar!

        XCTAssertEqual(c.trained, [LocalDate(2026, 10, 3), LocalDate(2026, 10, 7), today])
        XCTAssertEqual(c.currentRun, [LocalDate(2026, 10, 7), today])
        XCTAssertEqual(c.today, today)
    }

    /// A day with no sessions has no sheet.
    func testADayWithNoSessionsHasNoSheet() {
        XCTAssertNil(model([attempt(12, at: now)]).daySheet(LocalDate(2026, 10, 7)))
    }

    /// A day's sessions, oldest first, with the time the phone's way.
    func testADaysSessionsAreOldestFirstWithTheTimeThePhonesWay() {
        let early = attempt(12, at: zone.epochMs(today, hour: 9, minute: 5))
        let late = attempt(14, at: zone.epochMs(today, hour: 18, minute: 30))

        let h24 = model([late, early]).daySheet(today)!
        XCTAssertEqual(h24.rows.map { $0.time }, ["09:05", "18:30"])
        XCTAssertEqual(h24.rows[0].spoken, "09:05, 12 · Intermediate")

        let h12 = model([late, early], is24Hour: false).daySheet(today)!
        XCTAssertEqual(h12.rows.map { $0.time }, ["9:05 AM", "6:30 PM"])
        let noon = model([attempt(12, at: zone.epochMs(today, hour: 12, minute: 0)),
                          attempt(12, at: zone.epochMs(today, hour: 0, minute: 7))], is24Hour: false).daySheet(today)!
        XCTAssertEqual(noon.rows.map { $0.time }, ["12:07 AM", "12:00 PM"])
        XCTAssertEqual(model([early]).daySheet(today)?.subtitle, "1 session")
    }

    // MARK: the leaderboard

    /// Your sessions are ranked by score, below the benchmark until they pass it, and the best at
    /// each kind of Cindy is marked.
    func testSessionsAreRankedBelowTheBenchmarkUntilTheyPassIt() {
        let knee = CindyProfile(push: .kneePushUp)
        let a = [attempt(14, at: now), attempt(12, at: now - day), attempt(16, at: now - 2 * day, profile: knee)]
        let rows = model(a).page.leaderboard.rows

        XCTAssertEqual(rows.map { $0.name }, ["Tom Holland", "You", "You", "You"])
        XCTAssertEqual(rows.map { $0.rank }, ["1", "2", "3", "4"])
        XCTAssertEqual(rows.map { $0.score }, ["27", "16", "14", "12"])
        XCTAssertEqual(rows.map { $0.best }, [false, true, true, false])
        XCTAssertEqual(rows.map { $0.mine }, [false, true, true, true])
        XCTAssertEqual(rows[0].detail, "the benchmark · 810 reps")
        XCTAssertNil(rows[0].opens)
        XCTAssertEqual(rows[2].detail, "8 Oct 2026 · Intermediate · 1:03/round")
        XCTAssertEqual(rows[2].spoken, "3, You, 14, 8 Oct 2026 · Intermediate · 1:03/round")
    }

    /// Passing the benchmark puts you above it.
    func testPassingTheBenchmarkPutsYouAboveIt() {
        let rows = model([attempt(28, at: now), attempt(14, at: now - day)]).page.leaderboard.rows

        XCTAssertEqual(rows.map { $0.name }, ["Tom Holland", "You", "You"])
        XCTAssertEqual(rows.map { $0.rank }, ["2", "1", "3"])
    }

    /// The athlete's own name, once they have given one.
    func testTheAthletesOwnNameOnceTheyHaveGivenOne() {
        let rows = model([attempt(14, at: now)], name: "Alex").page.leaderboard.rows
        XCTAssertEqual(rows[1].name, "Alex")
        XCTAssertTrue(rows[1].spoken.contains("Alex, 14"))
    }

    /// A session with no round at all has no pace on its row; one with rounds but no times is paced
    /// by dividing the clock.
    func testASessionWithNoRoundHasNoPaceOnItsRow() {
        let none = model([attempt(0, at: now, reps: 10, splits: false)]).page.leaderboard.rows
        XCTAssertFalse(none[1].detail.contains("/round"), none[1].detail)

        let untimed = model([attempt(14, at: now, splits: false)]).page.leaderboard.rows
        XCTAssertEqual(untimed[1].detail, "8 Oct 2026 · Intermediate · 1:25/round")
    }

    // MARK: the chart card

    /// The overview is the whole range, the score note says how far the athlete has come, and the
    /// chart is described in one sentence.
    func testTheScoreNoteSaysHowFarTheAthleteHasCome() {
        let m = model([attempt(12, at: now - day), attempt(14, at: now)])
        let card = m.page.progress!

        XCTAssertEqual(card.note, "2 attempts · up 60 reps since your first")
        XCTAssertEqual(card.overview.headline, "Best 14")
        XCTAssertEqual(card.spoken, "Score chart, Best 14, 2 sessions in this range")

        m.reload([attempt(14, at: now - day), attempt(12, at: now)])
        XCTAssertEqual(m.page.progress!.note, "2 attempts · 60 reps below your first")
        m.reload([attempt(12, at: now - day), attempt(12, at: now)])
        XCTAssertEqual(m.page.progress!.note, "2 attempts · level with your first")
    }

    /// The score note counts only the chosen category.
    func testTheScoreNoteCountsOnlyTheChosenCategory() {
        let a = [attempt(12, at: now - 2 * day), attempt(20, at: now - day, profile: CindyProfile(push: .kneePushUp)),
                 attempt(15, at: now)]
        XCTAssertEqual(model(a).page.progress!.note, "2 attempts · up 90 reps since your first")
    }

    /// One attempt at the movements is said without a comparison.
    func testOneAttemptAtTheMovementsIsSaidWithoutAComparison() {
        let a = [attempt(12, at: now - 2 * day, profile: CindyProfile(push: .kneePushUp)), attempt(15, at: now)]
        XCTAssertEqual(model(a).page.progress!.note, "1 attempt at these movements")
    }

    /// The chart is a line for score and pace and bars for volume, with the dates at its edges.
    func testTheChartIsALineForScoreAndPaceAndBarsForVolume() {
        let m = model([attempt(12, at: now - 3 * day), attempt(14, at: now)])

        guard case .line(let points, let best, let xStart, let xEnd, let invertY, let edges)? = m.page.progress!.chart else {
            return XCTFail("score is a line")
        }
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(best.count, 2)
        XCTAssertEqual(xStart, zone.epochMs(LocalDate(2026, 10, 5)))
        XCTAssertEqual(xEnd, now)
        XCTAssertFalse(invertY)
        XCTAssertEqual(edges.0, "5 Oct")
        XCTAssertEqual(edges.1, "8 Oct")

        m.chooseMetric(1)
        guard case .line(_, _, _, _, let inverted, _)? = m.page.progress!.chart else { return XCTFail("pace is a line") }
        XCTAssertTrue(inverted, "a smaller number is faster")

        m.chooseMetric(2)
        guard case .bars(let weeks, let barEdges)? = m.page.progress!.chart else { return XCTFail("volume is bars") }
        XCTAssertEqual(weeks.map { $0.sessions }.reduce(0, +), 2)
        XCTAssertEqual(barEdges.0, "5 Oct")
    }

    /// A range starts at its own edge, not at the first session.
    func testARangeStartsAtItsOwnEdge() {
        let m = model([attempt(12, at: now - 100 * day), attempt(14, at: now - day)])
        m.chooseRange(0)
        guard case .line(_, _, let xStart, _, _, let edges)? = m.page.progress!.chart else { return XCTFail("no line") }
        XCTAssertEqual(xStart, zone.epochMs(LocalDate(2026, 9, 8)))
        XCTAssertEqual(edges.0, "8 Sep")
    }

    /// The readout follows the point selected, and falls back to the whole range.
    func testTheReadoutFollowsThePointSelected() {
        let m = model([attempt(12, at: now - day), attempt(14, at: now)])

        XCTAssertEqual(m.readout(selected: nil).headline, "Best 14")
        XCTAssertEqual(m.readout(selected: 1).headline, "8 Oct · 14")
        XCTAssertEqual(m.readout(selected: 1).detail, "420 reps · personal record · +60 on the session before")
        XCTAssertEqual(m.spoken(point: 1), "8 Oct · 14. 420 reps · personal record · +60 on the session before")
        XCTAssertEqual(m.readout(selected: 9).headline, "Best 14")
    }

    /// With one session there is no chart card, and with none no Progress card either.
    func testAChartNeedsTwoSessions() {
        XCTAssertNil(model([attempt(12, at: now)]).page.progress)
        XCTAssertNil(model([]).page.progress)
    }

    // MARK: CLEAR

    /// It names what is at stake and says it cannot be undone.
    func testClearNamesWhatIsAtStake() {
        XCTAssertNil(model([]).clearQuestion)

        let one = model([attempt(12, at: now)]).clearQuestion!
        XCTAssertEqual(one.title, "Delete your 1 session?")
        XCTAssertEqual(one.keep, "KEEP THEM")
        XCTAssertEqual(one.delete, "DELETE")
        XCTAssertTrue(one.subtitle.contains("This cannot be undone."))
        XCTAssertTrue(one.subtitle.contains("The benchmark stays."))
        XCTAssertTrue(one.subtitle.contains("Your name and photo stay."))

        XCTAssertEqual(model([attempt(12, at: now), attempt(13, at: now - day), attempt(14, at: now - 2 * day)])
            .clearQuestion?.title, "Delete all 3 sessions?")
    }

    /// Once the board is cleared the page is the empty page again.
    func testOnceTheBoardIsClearedThePageIsTheEmptyPageAgain() {
        let m = model([attempt(12, at: now), attempt(13, at: now - day)])
        m.reload([])
        XCTAssertNil(m.page.progress)
        XCTAssertNil(m.page.calendar)
        XCTAssertFalse(m.page.canClear)
        XCTAssertEqual(m.page.hero.headline, "Your first Cindy starts everything.")
        XCTAssertEqual(ProgressPageBuilder.clearedToast, "Records cleared")
    }
}
