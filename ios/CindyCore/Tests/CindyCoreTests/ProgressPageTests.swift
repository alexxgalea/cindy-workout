import XCTest
@testable import CindyCore

/// The Progress screen's decisions, ported from the Progress parts of `ScreenSmokeTest.kt`.
///
/// Robolectric inflated `RecordsActivity` and read its views; the same facts are read here off the
/// `ProgressPage` the screen draws and the `ProgressModel` that keeps its state. Each test is named
/// after the Kotlin one it comes from, or says it was written for the port. What the Kotlin tests
/// do by starting `ResultsActivity` (a leaderboard row, a day-sheet row, the chart's OPEN button)
/// is held as the session each one asks to reopen.
final class ProgressPageTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private lazy var today = LocalDate(2026, 10, 8)
    private lazy var now = zone.epochMs(today, hour: 12)
    private let day: Int64 = 24 * 60 * 60 * 1000

    private func attempt(_ rounds: Int, at: Int64, reps: Int = 0, profile: CindyProfile? = .standard,
                         untrackedMs: Int64 = 0, durationMs: Int64 = 20 * 60_000) -> Attempt {
        Attempt(rounds: rounds, reps: reps, atMillis: at, durationMs: durationMs,
                roundSplitsMs: (0..<rounds).map { 60_000 + Int64($0) * 500 }, profile: profile, untrackedMs: untrackedMs)
    }

    private func input(_ attempts: [Attempt], name: String? = nil, is24Hour: Bool = true) -> ProgressInput {
        ProgressInput(attempts: attempts, today: today, nowMs: now, zone: zone, firstDayOfWeek: .monday,
                      displayName: name, is24Hour: is24Hour)
    }

    private func model(_ attempts: [Attempt], name: String? = nil, is24Hour: Bool = true) -> ProgressModel {
        ProgressModel(input(attempts, name: name, is24Hour: is24Hour))
    }

    /// Three sessions on three days, the last today.
    private var history: [Attempt] { (0..<3).map { attempt(12 + $0, at: now - Int64(2 - $0) * day, reps: $0) } }

    // MARK: the screen builds

    /// the records screen builds when empty
    func testTheRecordsScreenBuildsWhenEmpty() {
        let p = model([]).page

        XCTAssertEqual(p.hero.headline, "Your first Cindy starts everything.")
        XCTAssertEqual(p.hero.emptyNote, "Finish a session and your streak, progress and peaks start here.")
        XCTAssertNil(p.hero.daily)
        XCTAssertNil(p.thisWeek)
        XCTAssertNil(p.progress)
        XCTAssertNil(p.peaks)
        XCTAssertNil(p.calendar)
        XCTAssertFalse(p.canClear)
        // The benchmark is always there to chase, and first with nobody to pass it.
        XCTAssertEqual(p.leaderboard.rows.map { $0.name }, ["Tom Holland"])
        XCTAssertEqual(p.leaderboard.rows[0].rank, "1")
        XCTAssertEqual(p.leaderboard.emptyNote, "No attempts yet. Finish a 20-minute Cindy and it lands here.")
        XCTAssertNil(p.leaderboard.rows[0].opens)
    }

    /// the records screen builds with history
    func testTheRecordsScreenBuildsWithHistory() {
        let p = model(history).page

        XCTAssertNil(p.hero.emptyNote)
        XCTAssertEqual(p.hero.daily?.value, 3)
        XCTAssertNotNil(p.thisWeek)
        XCTAssertNotNil(p.progress)
        XCTAssertNotNil(p.peaks)
        XCTAssertNotNil(p.calendar)
        XCTAssertTrue(p.canClear)
        XCTAssertEqual(p.leaderboard.rows.count, 4)
        XCTAssertNil(p.leaderboard.emptyNote)
    }

    /// the progress report builds across categories
    func testTheProgressReportBuildsAcrossCategories() {
        let attempts = [
            attempt(12, at: now - 16 * day),
            attempt(14, at: now - 11 * day, profile: CindyProfile(push: .kneePushUp)),
            attempt(13, at: now - 7 * day, profile: nil),
            attempt(15, at: now - 3 * day),
            attempt(16, at: now - day, untrackedMs: 60_000)
        ]
        let m = model(attempts)
        let card = m.page.progress!

        // Most recently used first; the unrecognised ones are named rather than hidden.
        XCTAssertEqual(card.categoryLabels, ["Cindy", "Movements not recognised", "Adaptive Cindy · knee push-ups"])
        XCTAssertEqual(card.category, 0)
        XCTAssertEqual(m.page.leaderboard.rows.count, 6)
        XCTAssertNotNil(m.page.peaks)
    }

    // MARK: the chart card

    /// the chart card switches metric and range
    func testTheChartCardSwitchesMetricAndRange() {
        let m = model(history)
        var builds = 0
        m.onChange = { builds += 1 }
        XCTAssertEqual(m.page.progress!.metricLabels, ["Score", "Pace", "Volume"])
        XCTAssertEqual(m.page.progress!.rangeLabels, ["1M", "3M", "1Y", "All"])

        m.chooseMetric(1)
        XCTAssertEqual(m.page.progress!.metric, 1)
        XCTAssertEqual(m.page.progress!.note, "Higher is faster. Full 20-minute sessions only.")
        m.chooseMetric(2)
        XCTAssertEqual(m.page.progress!.note, "Every session counts toward volume, whatever the movements.")
        m.chooseRange(0)
        XCTAssertEqual(m.page.progress!.range, 0)

        XCTAssertEqual(builds, 3)
    }

    /// the chart card handles a range with no sessions
    func testTheChartCardHandlesARangeWithNoSessions() {
        let old = now - 730 * day
        let m = model([attempt(12, at: old), attempt(13, at: old + day)])

        m.chooseRange(0)

        let card = m.page.progress!
        XCTAssertNil(card.chart)
        XCTAssertEqual(card.empty, "No sessions in this range")
        XCTAssertEqual(card.overview.headline, "No sessions in this range")
    }

    /// a trained day opens its sessions
    func testATrainedDayOpensItsSessions() {
        let m = model([attempt(12, at: now), attempt(13, at: now - 1000)])

        let sheet = m.daySheet(today)

        XCTAssertNotNil(sheet)
        XCTAssertEqual(sheet!.title, "Thursday 8 October")
        XCTAssertEqual(sheet!.subtitle, "2 sessions")
        XCTAssertEqual(sheet!.rows.count, 2)
    }

    /// tapping a leaderboard row opens that session
    func testTappingALeaderboardRowOpensThatSession() {
        let a = attempt(9, at: now)
        let rows = model([a]).page.leaderboard.rows

        let row = rows.first { $0.spoken.contains("You, 9") }
        XCTAssertNotNil(row, "no leaderboard row for the session: \(rows.map { $0.spoken })")
        XCTAssertEqual(row?.opens, a.atMillis)
    }

    /// tapping a day-sheet row opens that session and dismisses the sheet
    func testTappingADaySheetRowOpensThatSession() {
        let a = attempt(11, at: now)
        let sheet = model([a]).daySheet(today)!

        let row = sheet.rows.first { $0.spoken.contains("11 ·") }
        XCTAssertNotNil(row, "no day-sheet row for the session: \(sheet.rows.map { $0.spoken })")
        XCTAssertEqual(row?.opens, a.atMillis)
    }

    /// the chart's OPEN button opens the selected session
    func testTheChartsOpenButtonOpensTheSelectedSession() {
        let older = attempt(10, at: now - day)
        let newer = attempt(12, at: now)
        let m = model([older, newer])

        // The default metric (Score) sorts its points oldest first, so index 0 is `older`.
        XCTAssertEqual(m.openTarget(selected: 0), older.atMillis)
        XCTAssertEqual(m.openTarget(selected: 1), newer.atMillis)
        XCTAssertNil(m.openTarget(selected: nil), "nothing selected is the whole range")
        XCTAssertTrue(m.page.progress!.opensSessions)

        // A volume bar is a week of sessions, not one.
        m.chooseMetric(2)
        XCTAssertNil(m.openTarget(selected: 0))
        XCTAssertFalse(m.page.progress!.opensSessions)
    }
}
