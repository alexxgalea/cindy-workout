import Foundation

/// Everything the Progress screen needs to decide what to show, from the attempts on the board
/// and where and when it is. The page itself is `ProgressPageBuilder.build`; the screen only draws
/// what it returns. Port of `RecordsActivity`'s `render`.
public struct ProgressInput {
    public var attempts: [Attempt]
    public var today: LocalDate
    /// The instant "now" is, for the right edge of the chart.
    public var nowMs: Int64
    public var zone: Zone
    public var firstDayOfWeek: DayOfWeek
    /// The athlete's own name, once they have given one; "You" until then.
    public var displayName: String?
    public var is24Hour: Bool

    public init(attempts: [Attempt], today: LocalDate, nowMs: Int64, zone: Zone, firstDayOfWeek: DayOfWeek,
                displayName: String? = nil, is24Hour: Bool = true) {
        self.attempts = attempts
        self.today = today
        self.nowMs = nowMs
        self.zone = zone
        self.firstDayOfWeek = firstDayOfWeek
        self.displayName = displayName
        self.is24Hour = is24Hour
    }
}

/// One streak: its name, then the number. Read out as a single sentence.
public struct StreakColumn: Equatable, Sendable {
    public let label: String
    public let value: Int
    public let unit: String
    /// The daily streak carries a flame, lit while there is a streak.
    public let flame: Bool
    public let spoken: String
}

/// The habit rather than the scores: a line that is true today, both streaks, which days of this
/// week were trained.
public struct HeroCard: Equatable, Sendable {
    public let headline: String
    /// With no attempts there is only this line under the headline.
    public let emptyNote: String?
    public let daily: StreakColumn?
    public let weekly: StreakColumn?
    public let weekStart: LocalDate?
    public let trained: Set<LocalDate>
    public let nextStep: String?
    /// "12 days trained · 14 sessions".
    public let tally: String?
}

/// One figure of the week: label, value and, when it moved, the change since last week.
public struct WeekTile: Equatable, Sendable {
    public let label: String
    public let value: String
    public let change: String?
    /// Green when it went up; the rest are quiet.
    public let up: Bool
    public let spoken: String
}

public struct ThisWeek: Equatable, Sendable {
    public let tiles: [WeekTile]
    public let monthNote: String
}

public struct PeakRow: Equatable, Sendable {
    public let rank: Int
    public let title: String
    public let detail: String
    public let value: String
    public let spoken: String
}

public struct PeaksSection: Equatable, Sendable {
    public let rows: [PeakRow]
    public let footnote: String
}

/// The month grid with arrows back through the athlete's history.
public struct CalendarSection: Equatable, Sendable {
    public let month: YearMonth
    public let canGoBack: Bool
    public let canGoForward: Bool
    public let trained: Set<LocalDate>
    public let currentRun: Set<LocalDate>
    public let today: LocalDate
}

/// What the chart draws.
public enum ChartData {
    case bars(points: [ProgressPoint], edgeLabels: (String, String))
    case line(points: [ProgressPoint], best: [Double], xStart: Int64, xEnd: Int64, invertY: Bool,
              edgeLabels: (String, String))
}

/// The chart card: what to plot, over how long, and (when more than one kind of Cindy has been
/// trained) which one.
public struct ProgressCard {
    public let metricLabels: [String]
    public let metric: Int
    public let rangeLabels: [String]
    public let range: Int
    public let overview: Readout
    /// Nil when the range holds no sessions.
    public let chart: ChartData?
    public let empty: String
    /// One sentence for the whole chart.
    public let spoken: String
    public let categoryLabels: [String]?
    public let category: Int
    public let note: String
    /// Only a selected line point is one session; a bar is a week of them.
    public let opensSessions: Bool
}

/// A row of the leaderboard.
public struct LeaderRow: Equatable, Sendable {
    public let rank: String
    public let name: String
    public let detail: String
    public let score: String
    public let mine: Bool
    public let best: Bool
    /// The session this row reopens; nil for the benchmark, which is not a session.
    public let opens: Int64?
    public let spoken: String
}

public struct Leaderboard: Equatable, Sendable {
    public let rows: [LeaderRow]
    public let emptyNote: String?
}

public struct ProgressPage {
    public let hero: HeroCard
    public let thisWeek: ThisWeek?
    public let progress: ProgressCard?
    public let peaks: PeaksSection?
    public let calendar: CalendarSection?
    public let leaderboard: Leaderboard
    /// CLEAR is offered only when there is something to clear.
    public let canClear: Bool
}

/// The sessions of one trained day, in a sheet.
public struct DaySheet: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let time: String
        public let value: String
        public let opens: Int64
        public var spoken: String { "\(time), \(value)" }
    }

    public let title: String
    public let subtitle: String
    public let rows: [Row]
}

/// The question CLEAR asks, arranged so that a reflex second tap cancels.
public struct ClearQuestion: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    /// The filled, safe action.
    public let keep = "KEEP THEM"
    /// The quiet one, painted in the alert colour.
    public let delete = "DELETE"
}
