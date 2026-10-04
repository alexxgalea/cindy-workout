import Foundation

/// What the progress chart can plot.
public enum ProgressMetric: CaseIterable, Sendable {
    case score, pace, volume

    public var label: String {
        switch self {
        case .score: return "Score"
        case .pace: return "Pace"
        case .volume: return "Volume"
        }
    }
}

/// How far back the chart looks.
public enum ProgressRange: CaseIterable, Sendable {
    case month, quarter, year, all

    public var label: String {
        switch self {
        case .month: return "1M"
        case .quarter: return "3M"
        case .year: return "1Y"
        case .all: return "All"
        }
    }

    /// The first local date inside the range, or nil for everything.
    public func start(_ today: LocalDate) -> LocalDate? {
        switch self {
        case .month: return today.minusMonths(1)
        case .quarter: return today.minusMonths(3)
        case .year: return today.minusYears(1)
        case .all: return nil
        }
    }
}

/// One plotted value.
public struct ProgressPoint: Equatable, Sendable {
    /// The attempt's time, or local midnight at the start of the week for a volume bar.
    public let atMillis: Int64
    /// Reps (score), seconds per round (pace) or reps in the week (volume).
    public let value: Double
    /// A personal record at the moment it was set.
    public let record: Bool
    public let lowerBound: Bool
    /// The attempt behind a line point; nil for a volume bar.
    public let attempt: Attempt?
    /// Sessions in the week, for a volume bar.
    public let sessions: Int

    public init(atMillis: Int64, value: Double, record: Bool = false, lowerBound: Bool = false,
                attempt: Attempt? = nil, sessions: Int = 0) {
        self.atMillis = atMillis
        self.value = value
        self.record = record
        self.lowerBound = lowerBound
        self.attempt = attempt
        self.sessions = sessions
    }
}

/// Points plus the best-so-far value at each of them, measured over the whole history.
public struct Series: Equatable, Sendable {
    public let points: [ProgressPoint]
    public let best: [Double]
    public let lowerIsBetter: Bool
}

/// Totals over a stretch of days.
public struct Period: Equatable, Sendable {
    public let sessions: Int
    public let reps: Int
    public let clockMs: Int64

    public init(sessions: Int, reps: Int, clockMs: Int64) {
        self.sessions = sessions
        self.reps = reps
        self.clockMs = clockMs
    }
}

public struct WeekSummary: Equatable, Sendable {
    public let thisWeek: Period
    public let lastWeek: Period
    public let thisMonth: Period
}

/// What the readout under the chart says: a headline and a detail line.
public struct Readout: Equatable, Sendable {
    public let headline: String
    public let detail: String

    public init(_ headline: String, _ detail: String) {
        self.headline = headline
        self.detail = detail
    }
}

/// The numbers behind the progress chart and the "this week" card.
///
/// Pure: no clock, no zone of its own. Scores are only ever compared within one category, and a
/// lower-bound attempt is plotted but never claims a record, as in `Records`. Port of `Progress.kt`.
public enum Progress {

    /// A session that ran the whole clock. Only these can set a pace, which fresh rounds would
    /// flatter. Twenty minutes less a second of slack.
    public static let fullSessionMs: Int64 = 20 * 60_000 - 1_000

    public static func isFullSession(_ a: Attempt) -> Bool { a.durationMs >= fullSessionMs }

    public static func localDate(_ a: Attempt, zone: Zone) -> LocalDate {
        zone.localDate(epochMs: a.atMillis)
    }

    /// Every category trained, most recently used first.
    public static func categories(_ attempts: [Attempt]) -> [CindyProfile?] {
        var out: [CindyProfile?] = []
        for a in JavaText.sortedStably(attempts, by: { $0.atMillis }, descending: true) where !out.contains(a.profile) {
            out.append(a.profile)
        }
        return out
    }

    /// The category of the latest attempt, which is what the athlete is training now.
    public static func defaultCategory(_ attempts: [Attempt]) -> CindyProfile? {
        // `maxByOrNull` keeps the first of equals.
        var latest: Attempt?
        for a in attempts where latest == nil || a.atMillis > latest!.atMillis { latest = a }
        return latest?.profile
    }

    /// Reps per attempt in one category. A lower-bound score does raise the bar, because the true
    /// score was at least that, exactly as `Records.personalRecord` treats it.
    public static func scoreSeries(_ attempts: [Attempt], category: CindyProfile?, from: LocalDate?, zone: Zone) -> Series {
        let own = JavaText.sortedStably(attempts.filter { $0.profile == category }, by: { $0.atMillis })
        var best = Int.min
        var points: [ProgressPoint] = []
        var bests: [Double] = []
        var dates: [LocalDate] = []
        for a in own {
            let record = !a.scoreIsLowerBound && a.totalReps > 0 && a.totalReps > best
            best = max(best, a.totalReps)
            points.append(ProgressPoint(atMillis: a.atMillis, value: Double(a.totalReps), record: record,
                                        lowerBound: a.scoreIsLowerBound, attempt: a))
            bests.append(Double(best))
            dates.append(localDate(a, zone: zone))
        }
        return cut(points, bests, dates, from: from, lowerIsBetter: false)
    }

    /// Seconds per round, full sessions only, where faster is better. A lower-bound pace never sets
    /// the bar, because unlike a score it says nothing about how fast the athlete really was. It is
    /// still plotted, and before any exact attempt its own value stands in for the displayed best so
    /// the line stays finite.
    public static func paceSeries(_ attempts: [Attempt], category: CindyProfile?, from: LocalDate?, zone: Zone) -> Series {
        let own = JavaText.sortedStably(
            attempts.filter { $0.profile == category && isFullSession($0) && $0.avgRoundMs != nil },
            by: { $0.atMillis })
        var best = Double.greatestFiniteMagnitude
        var points: [ProgressPoint] = []
        var bests: [Double] = []
        var dates: [LocalDate] = []
        for a in own {
            guard let avg = a.avgRoundMs else { continue }
            let seconds = Double(avg) / 1000.0
            let record = !a.scoreIsLowerBound && seconds < best
            if !a.scoreIsLowerBound { best = min(best, seconds) }
            points.append(ProgressPoint(atMillis: a.atMillis, value: seconds, record: record,
                                        lowerBound: a.scoreIsLowerBound, attempt: a))
            bests.append(best == Double.greatestFiniteMagnitude ? seconds : best)
            dates.append(localDate(a, zone: zone))
        }
        return cut(points, bests, dates, from: from, lowerIsBetter: true)
    }

    /// Drops points (and their best-so-far entries together) dated before `from`.
    private static func cut(_ points: [ProgressPoint], _ bests: [Double], _ dates: [LocalDate],
                            from: LocalDate?, lowerIsBetter: Bool) -> Series {
        let keep = points.indices.filter { from == nil || !(dates[$0] < from!) }
        return Series(points: keep.map { points[$0] }, best: keep.map { bests[$0] }, lowerIsBetter: lowerIsBetter)
    }

    /// Reps per week, across all categories: volume is work done, not a comparison. Weeks with no
    /// session are kept so that a week off shows as a gap.
    public static func weeklyVolume(_ attempts: [Attempt], from: LocalDate?, today: LocalDate, zone: Zone,
                                    firstDayOfWeek: DayOfWeek) -> [ProgressPoint] {
        if attempts.isEmpty { return [] }
        let dated = attempts.map { (date: localDate($0, zone: zone), attempt: $0) }
        let first = from ?? dated.map { $0.date }.min()!
        let last = Streak.weekStart(today, firstDayOfWeek: firstDayOfWeek)
        var out: [ProgressPoint] = []
        var week = Streak.weekStart(first, firstDayOfWeek: firstDayOfWeek)
        while !(week > last) {
            let end = week.plusDays(7)
            let inWeek = dated.filter { !($0.date < week) && $0.date < end }
            out.append(ProgressPoint(atMillis: zone.epochMs(week),
                                     value: Double(inWeek.reduce(0) { $0 + $1.attempt.totalReps }),
                                     sessions: inWeek.count))
            week = end
        }
        return out
    }

    public static func summary(_ attempts: [Attempt], today: LocalDate, zone: Zone, firstDayOfWeek: DayOfWeek) -> WeekSummary {
        let thisStart = Streak.weekStart(today, firstDayOfWeek: firstDayOfWeek)
        let lastStart = thisStart.minusDays(7)
        let month = today.yearMonth
        let dated = attempts.map { (date: localDate($0, zone: zone), attempt: $0) }
        func period(_ match: (LocalDate) -> Bool) -> Period {
            let hit = dated.filter { match($0.date) }.map { $0.attempt }
            return Period(sessions: hit.count, reps: hit.reduce(0) { $0 + $1.totalReps },
                          clockMs: hit.reduce(Int64(0)) { $0 + $1.durationMs })
        }
        return WeekSummary(
            thisWeek: period { !($0 < thisStart) && $0 < thisStart.plusDays(7) },
            lastWeek: period { !($0 < lastStart) && $0 < thisStart },
            thisMonth: period { $0.yearMonth == month })
    }

    /// Round axis values in 1-2-5 steps that cover `min`...`max`.
    public static func niceTicks(_ min: Double, _ max: Double, maxTicks: Int = 4) -> [Double] {
        if max - min < 1e-9 {
            let pad = Swift.max(1.0, abs(min) * 0.05)
            return niceTicks(min - pad, max + pad, maxTicks: maxTicks)
        }
        let raw = (max - min) / Double(maxTicks)
        let mag = pow(10.0, floor(log10(raw)))
        let norm = raw / mag
        let step: Double
        if norm <= 1 { step = mag * 1.0 }
        else if norm <= 2 { step = mag * 2.0 }
        else if norm <= 5 { step = mag * 5.0 }
        else { step = mag * 10.0 }
        let lo = floor(min / step) * step
        let hi = ceil(max / step) * step
        var out: [Double] = []
        var i = 0
        while lo + Double(i) * step <= hi + step * 1e-9 {
            out.append(lo + Double(i) * step)
            i += 1
        }
        return out
    }

    /// Index of the value in ascending `xs` closest to `x`; a tie goes to the lower index.
    public static func nearestIndex(_ xs: [Float], _ x: Float) -> Int {
        if xs.isEmpty { return -1 }
        var lo = 0
        var hi = xs.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if xs[mid] < x { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return 0 }
        if lo == xs.count { return xs.count - 1 }
        return x - xs[lo - 1] <= xs[lo] - x ? lo - 1 : lo
    }

    private static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    private static func shortDate(_ atMillis: Int64, _ zone: Zone) -> String {
        DateText.short(zone.localDate(epochMs: atMillis))
    }

    private static func pace(_ seconds: Double) -> String { formatDuration(Int64(seconds * 1000)) }

    /// What the readout says about point `i`: a headline and a detail line.
    public static func describe(_ metric: ProgressMetric, _ points: [ProgressPoint], _ i: Int, zone: Zone) -> Readout {
        let p = points[i]
        let before: ProgressPoint? = i >= 1 ? points[i - 1] : nil
        let date = shortDate(p.atMillis, zone)
        var parts: [String] = []
        switch metric {
        case .score:
            let label = p.attempt?.scoreLabel ?? "\(JavaText.roundToInt(p.value))"
            parts.append("\(JavaText.roundToInt(p.value)) reps")
            if p.record { parts.append("personal record") }
            if p.lowerBound { parts.append("at least — camera lost you") }
            if let before {
                let d = JavaText.roundToInt(p.value) - JavaText.roundToInt(before.value)
                if d > 0 { parts.append("+\(d) on the session before") }
                else if d < 0 { parts.append("\(-d) below the session before") }
                else { parts.append("level with the session before") }
            } else {
                parts.append("first in this range")
            }
            return Readout("\(date) · \(label)", parts.joined(separator: " · "))
        case .pace:
            if p.record { parts.append("fastest yet") }
            if let before {
                // Seconds per round: a smaller number is faster.
                let d = JavaText.roundToInt(before.value - p.value)
                if d > 0 { parts.append("\(d)s faster than the session before") }
                else if d < 0 { parts.append("\(-d)s slower than the session before") }
                else { parts.append("same pace as the session before") }
            } else {
                parts.append("first in this range")
            }
            return Readout("\(date) · \(pace(p.value)) a round", parts.joined(separator: " · "))
        case .volume:
            return Readout("Week of \(date)",
                           "\(formatReps(JavaText.roundToInt(p.value))) reps · " + plural(p.sessions, "session"))
        }
    }

    /// What the readout says when nothing is selected.
    public static func overview(_ metric: ProgressMetric, _ points: [ProgressPoint]) -> Readout {
        if points.isEmpty { return Readout("No sessions in this range", "") }
        switch metric {
        case .score:
            let exact = points.filter { !$0.lowerBound }
            let pool = exact.isEmpty ? points : exact
            // `maxByOrNull` keeps the first of equals.
            var top = pool[0]
            for p in pool where p.value > top.value { top = p }
            let label = top.attempt?.scoreLabel ?? "\(JavaText.roundToInt(top.value))"
            return Readout("Best \(label)", "\(plural(points.count, "session")) in this range")
        case .pace:
            var top = points[0]
            for p in points where p.value < top.value { top = p }
            return Readout("Best \(pace(top.value)) a round", "\(plural(points.count, "full session")) in this range")
        case .volume:
            let reps = JavaText.roundToInt(points.reduce(0.0) { $0 + $1.value })
            return Readout("\(formatReps(reps)) reps",
                           "\(plural(points.reduce(0) { $0 + $1.sessions }, "session")) in this range")
        }
    }

    public static func formatReps(_ n: Int) -> String { JavaText.grouped(n) }

    /// "42 min", or "1 h 02 min" from an hour up; minutes rounded down.
    public static func formatClock(_ ms: Int64) -> String {
        let minutes = ms / 60_000
        return minutes < 60 ? "\(minutes) min" : String(format: "%ld h %02ld min", Int(minutes / 60), Int(minutes % 60))
    }

    /// "+3" or "−3" (U+2212); nil when nothing changed.
    public static func formatDelta(_ n: Int) -> String? {
        if n > 0 { return "+\(n)" }
        if n < 0 { return "−\(-n)" }
        return nil
    }
}
