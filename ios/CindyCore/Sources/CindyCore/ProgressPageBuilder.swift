import Foundation

/// The Progress screen, decided: which cards show and what each says. Port of
/// `RecordsActivity`'s `render`; the screen draws what this returns and decides nothing of its own.
public enum ProgressPageBuilder {

    public static let emptyHeroNote = "Finish a session and your streak, progress and peaks start here."
    public static let emptyLeaderboardNote = "No attempts yet. Finish a 20-minute Cindy and it lands here."
    public static let peaksFootnote = "Scores and rounds are compared only with sessions at the same movements. "
        + "Streaks and weeks count everything."
    public static let unrecognisedMovements = "Movements not recognised"
    public static let clearedToast = "Records cleared"

    /// What the page shows for `input` with the athlete's choices so far: the chart's metric and
    /// range, the kind of Cindy the chart and the peaks are about, and the month the calendar is on.
    public static func build(_ input: ProgressInput, metric: ProgressMetric, range: ProgressRange,
                             category: CindyProfile?, month: YearMonth) -> ProgressPage {
        let attempts = input.attempts
        let empty = attempts.isEmpty
        return ProgressPage(
            hero: hero(input),
            thisWeek: empty ? nil : thisWeek(input),
            progress: attempts.count < 2 ? nil : progressCard(input, metric, range, category),
            peaks: empty ? nil : peaks(input, category),
            calendar: empty ? nil : calendar(input, month),
            leaderboard: leaderboard(input),
            canClear: !empty)
    }

    // MARK: the habit

    static func hero(_ input: ProgressInput) -> HeroCard {
        let a = input.attempts
        let headline = Cheer.headline(a, today: input.today, zone: input.zone, firstDayOfWeek: input.firstDayOfWeek)
        if a.isEmpty {
            return HeroCard(headline: headline, emptyNote: emptyHeroNote, daily: nil, weekly: nil, weekStart: nil,
                            trained: [], nextStep: nil, tally: nil)
        }
        let days = Streak.daysTrained(a, zone: input.zone)
        let daily = Streak.current(days, today: input.today)
        let weeks = Streak.weeksTrained(days, firstDayOfWeek: input.firstDayOfWeek)
        let weekly = Streak.currentWeeks(weeks, today: input.today, firstDayOfWeek: input.firstDayOfWeek)
        return HeroCard(
            headline: headline, emptyNote: nil,
            daily: streakColumn("DAILY STREAK", daily, daily == 1 ? "day" : "days", flame: true),
            weekly: streakColumn("WEEKLY STREAK", weekly, weekly == 1 ? "week" : "weeks", flame: false),
            weekStart: Streak.weekStart(input.today, firstDayOfWeek: input.firstDayOfWeek), trained: days,
            nextStep: Cheer.nextStep(a, today: input.today, zone: input.zone, firstDayOfWeek: input.firstDayOfWeek),
            tally: "\(days.count) day\(days.count == 1 ? "" : "s") trained · "
                + "\(a.count) session\(a.count == 1 ? "" : "s")")
    }

    static func streakColumn(_ label: String, _ value: Int, _ unit: String, flame: Bool) -> StreakColumn {
        // "Daily streak: 4 days", so a screen reader does not announce "4", "days" and
        // "daily streak" as three unrelated things.
        let name = label.prefix(1) + label.dropFirst().lowercased()
        return StreakColumn(label: label, value: value, unit: unit, flame: flame, spoken: "\(name): \(value) \(unit)")
    }

    // MARK: this week

    static func thisWeek(_ input: ProgressInput) -> ThisWeek {
        let s = Progress.summary(input.attempts, today: input.today, zone: input.zone, firstDayOfWeek: input.firstDayOfWeek)
        let now = s.thisWeek
        let before = s.lastWeek
        let month = s.thisMonth
        return ThisWeek(
            tiles: [
                tile("Sessions", "\(now.sessions)", now.sessions - before.sessions, ""),
                tile("Reps", Progress.formatReps(now.reps), now.reps - before.reps, ""),
                tile("Time", Progress.formatClock(now.clockMs), Int((now.clockMs - before.clockMs) / 60_000), " min")
            ],
            monthNote: "This month: \(month.sessions) session\(month.sessions == 1 ? "" : "s") · "
                + "\(Progress.formatReps(month.reps)) reps · \(Progress.formatClock(month.clockMs)).")
    }

    static func tile(_ label: String, _ value: String, _ delta: Int, _ suffix: String) -> WeekTile {
        let change = Progress.formatDelta(delta)
        let versus: String
        if delta > 0 { versus = ", \(delta)\(suffix) more than last week" }
        else if delta < 0 { versus = ", \(-delta)\(suffix) fewer than last week" }
        else { versus = "" }
        return WeekTile(label: label, value: value, change: change.map { $0 + suffix }, up: delta > 0,
                        spoken: "\(label) this week: \(value)\(versus)")
    }

    // MARK: peaks

    static func peaks(_ input: ProgressInput, _ category: CindyProfile?) -> PeaksSection? {
        let list = Peaks.of(input.attempts, category: category, today: input.today, zone: input.zone,
                            firstDayOfWeek: input.firstDayOfWeek)
        if list.isEmpty { return nil }
        return PeaksSection(
            rows: list.map { PeakRow(rank: $0.rank, title: $0.title, detail: $0.detail, value: $0.value,
                                     spoken: "\($0.title), \($0.value), \($0.detail)") },
            footnote: peaksFootnote)
    }

    // MARK: the calendar

    static func shifted(_ month: YearMonth, by n: Int) -> YearMonth { month.atDay(1).plusMonths(n).yearMonth }

    /// The first and last month the calendar may show: the athlete's first trained month, and now.
    static func monthBounds(_ input: ProgressInput) -> (earliest: YearMonth, latest: YearMonth) {
        let days = Streak.daysTrained(input.attempts, zone: input.zone)
        return (days.min().map { $0.yearMonth } ?? input.today.yearMonth, input.today.yearMonth)
    }

    /// `month` kept inside the bounds.
    static func clamped(_ month: YearMonth, _ input: ProgressInput) -> YearMonth {
        let b = monthBounds(input)
        var m = month
        if m > b.latest { m = b.latest }
        if m < b.earliest { m = b.earliest }
        return m
    }

    static func calendar(_ input: ProgressInput, _ month: YearMonth) -> CalendarSection {
        let days = Streak.daysTrained(input.attempts, zone: input.zone)
        let b = monthBounds(input)
        let shown = clamped(month, input)
        return CalendarSection(month: shown, canGoBack: shown > b.earliest, canGoForward: shown < b.latest,
                               trained: days, currentRun: Streak.currentRun(days, today: input.today),
                               today: input.today)
    }

    // MARK: the chart

    private static func edge(_ ms: Int64, _ zone: Zone) -> String { DateText.short(zone.localDate(epochMs: ms)) }

    static func progressCard(_ input: ProgressInput, _ metric: ProgressMetric, _ range: ProgressRange,
                             _ category: CindyProfile?) -> ProgressCard {
        let attempts = input.attempts
        let zone = input.zone
        let from = range.start(input.today)

        var series: Series?
        switch metric {
        case .score: series = Progress.scoreSeries(attempts, category: category, from: from, zone: zone)
        case .pace: series = Progress.paceSeries(attempts, category: category, from: from, zone: zone)
        case .volume: series = nil
        }
        let points = series?.points ?? Progress.weeklyVolume(attempts, from: from, today: input.today, zone: zone,
                                                             firstDayOfWeek: input.firstDayOfWeek)
        let overview = Progress.overview(metric, points)

        var chart: ChartData?
        if !points.isEmpty {
            if let series {
                let start = zone.epochMs(from ?? Progress.localDate(points[0].attempt!, zone: zone))
                chart = .line(points: points, best: series.best, xStart: start, xEnd: input.nowMs,
                              invertY: metric == .pace, edgeLabels: (edge(start, zone), edge(input.nowMs, zone)))
            } else {
                chart = .bars(points: points, edgeLabels: (edge(points[0].atMillis, zone),
                                                           edge(points[points.count - 1].atMillis, zone)))
            }
        }

        let categories = Progress.categories(attempts)
        return ProgressCard(
            metricLabels: ProgressMetric.allCases.map { $0.label }, metric: ProgressMetric.allCases.firstIndex(of: metric)!,
            rangeLabels: ProgressRange.allCases.map { $0.label }, range: ProgressRange.allCases.firstIndex(of: range)!,
            overview: overview, chart: chart, empty: "No sessions in this range",
            spoken: "\(metric.label) chart, \(overview.headline)" + (overview.detail.isEmpty ? "" : ", \(overview.detail)"),
            categoryLabels: categories.count > 1 ? categories.map { $0?.label() ?? unrecognisedMovements } : nil,
            category: categories.firstIndex { $0 == category } ?? 0,
            note: note(attempts, metric, category), opensSessions: series != nil)
    }

    /// The line under the chart card: how the athlete has moved, or what the chart counts.
    static func note(_ attempts: [Attempt], _ metric: ProgressMetric, _ category: CindyProfile?) -> String {
        switch metric {
        case .score:
            let past = JavaText.sortedStably(attempts.filter { $0.profile == category }, by: { $0.atMillis })
            if past.count < 2 {
                return "\(past.count) attempt\(past.count == 1 ? "" : "s") at these movements"
            }
            let delta = past[past.count - 1].totalReps - past[0].totalReps
            let how: String
            if delta > 0 { how = "up \(delta) reps since your first" }
            else if delta < 0 { how = "\(-delta) reps below your first" }
            else { how = "level with your first" }
            return "\(past.count) attempts · \(how)"
        case .pace: return "Higher is faster. Full 20-minute sessions only."
        case .volume: return "Every session counts toward volume, whatever the movements."
        }
    }

    // MARK: the leaderboard

    static func leaderboard(_ input: ProgressInput) -> Leaderboard {
        let mine = Records.ranked(input.attempts)
        let beaten = mine.first.map { Records.beatsBenchmark($0) } ?? false
        let benchmark = LeaderRow(
            rank: beaten ? "2" : "1", name: Records.benchmarkName,
            detail: "the benchmark · \(Records.benchmark.totalReps) reps", score: Records.benchmark.scoreLabel,
            mine: false, best: false, opens: nil,
            spoken: "\(beaten ? "2" : "1"), \(Records.benchmarkName), \(Records.benchmark.scoreLabel), "
                + "the benchmark · \(Records.benchmark.totalReps) reps")
        if mine.isEmpty { return Leaderboard(rows: [benchmark], emptyNote: emptyLeaderboardNote) }

        // The athlete's own name, once they have given one, and "You" until then.
        let who = input.displayName ?? "You"
        var rows = [benchmark]
        for (i, a) in mine.enumerated() {
            let outranks = Records.beatsBenchmark(a)
            let rank = outranks ? "\(i + 1)" : "\(i + 2)"
            let detail = "\(DateText.long(Progress.localDate(a, zone: input.zone))) · \(a.caption)"
                + (a.avgRoundMs.map { " · \(formatDuration($0))/round" } ?? "")
            rows.append(LeaderRow(
                rank: rank, name: who, detail: detail, score: a.scoreLabel, mine: true,
                // "Best" means best at these movements. Across categories it would be comparing a
                // band-assisted Cindy with a strict one and calling one better.
                best: a == Records.bestIn(mine, profile: a.profile), opens: a.atMillis,
                spoken: "\(rank), \(who), \(a.scoreLabel), \(detail)"))
        }
        return Leaderboard(rows: rows, emptyNote: nil)
    }

    // MARK: a day, and CLEAR

    /// The sessions of one trained day, oldest first. Nothing to show, no sheet.
    public static func daySheet(_ input: ProgressInput, _ date: LocalDate) -> DaySheet? {
        let sessions = input.attempts.filter { Progress.localDate($0, zone: input.zone) == date }
            .sorted { $0.atMillis < $1.atMillis }
        if sessions.isEmpty { return nil }
        return DaySheet(
            title: CalendarModel.spokenDate(date),
            subtitle: sessions.count == 1 ? "1 session" : "\(sessions.count) sessions",
            rows: sessions.map { a in
                DaySheet.Row(time: time(a.atMillis, input), value: "\(a.scoreLabel) · \(a.caption)", opens: a.atMillis)
            })
    }

    static func time(_ ms: Int64, _ input: ProgressInput) -> String {
        let minutes = input.zone.minuteOfDay(epochMs: ms)
        let h = minutes / 60, m = minutes % 60
        if input.is24Hour { return String(format: "%02d:%02d", h, m) }
        return "\(h % 12 == 0 ? 12 : h % 12):\(String(format: "%02d", m)) \(h < 12 ? "AM" : "PM")"
    }

    /// The one irreversible thing in the app, and it asks twice: the safe answer is the filled one,
    /// so a reflex second tap in the same place cancels, and the question names the number of
    /// sessions at stake. Nothing to ask when there is nothing to lose.
    public static func clearQuestion(_ input: ProgressInput) -> ClearQuestion? {
        let sessions = input.attempts.count
        if sessions == 0 { return nil }
        return ClearQuestion(
            title: sessions == 1 ? "Delete your 1 session?" : "Delete all \(sessions) sessions?",
            subtitle: "Every attempt logged on this phone goes, including your best and the badges they earned. "
                + "Your name and photo stay. This cannot be undone. The benchmark stays.")
    }
}
