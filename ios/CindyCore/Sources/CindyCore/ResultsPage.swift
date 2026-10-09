import Foundation

/// Everything the results page needs to decide what to show, from one attempt and the records
/// around it. The page itself is `ResultsPageBuilder.build`; the screen only draws what it returns.
public struct ResultsInput {
    public var attempt: Attempt
    /// The workout ended before the clock ran out.
    public var stoppedEarly = false
    /// This page reopens a saved session rather than ending a live one.
    public var reviewing = false
    /// Smart squat counting switched the session to heels flat; the record cannot say so itself.
    public var heelsFlatSpotted = false
    /// Every attempt on the board, newest or oldest.
    public var records: [Attempt]
    public var body: Body
    /// This attempt's heart-rate trace, if a watch was heard from.
    public var heartTrace: HeartRateTrace?
    /// This attempt's rep marks, if the file exists.
    public var repMarks: [RepMark]?
    /// The rep marks of another attempt, by its time.
    public var marksFor: (Int64) -> [RepMark]?
    public var zone: Zone
    public var firstDayOfWeek: DayOfWeek
    public var today: LocalDate
    /// Whether the phone can draw an animal.
    public var font: EmojiFont
    public var is24Hour: Bool
    /// The time of the earlier session chosen to compare with, if one was chosen.
    public var comparisonAtMillis: Int64?

    public init(attempt: Attempt, stoppedEarly: Bool = false, reviewing: Bool = false,
                heelsFlatSpotted: Bool = false, records: [Attempt], body: Body,
                heartTrace: HeartRateTrace? = nil, repMarks: [RepMark]? = nil,
                marksFor: @escaping (Int64) -> [RepMark]? = { _ in nil },
                zone: Zone, firstDayOfWeek: DayOfWeek, today: LocalDate,
                font: EmojiFont = AnyEmojiFont.all, is24Hour: Bool = true, comparisonAtMillis: Int64? = nil) {
        self.attempt = attempt
        self.stoppedEarly = stoppedEarly
        self.reviewing = reviewing
        self.heelsFlatSpotted = heelsFlatSpotted
        self.records = records
        self.body = body
        self.heartTrace = heartTrace
        self.repMarks = repMarks
        self.marksFor = marksFor
        self.zone = zone
        self.firstDayOfWeek = firstDayOfWeek
        self.today = today
        self.font = font
        self.is24Hour = is24Hour
        self.comparisonAtMillis = comparisonAtMillis
    }
}

/// What a row asks for when it is tapped.
public enum ResultsAction: Equatable, Sendable {
    case askBodyWeight
    case askHeartRateDetails
    case explainHeelsFlat
}

/// A label and its figure. Tappable rows say what a tap does.
public struct StatRow: Equatable, Sendable {
    public let label: String
    public let value: String
    public let action: ResultsAction?
    /// A footnote under the row, which explains how its figure was reached.
    public let footnote: String?

    public init(_ label: String, _ value: String, action: ResultsAction? = nil, footnote: String? = nil) {
        self.label = label
        self.value = value
        self.action = action
        self.footnote = footnote
    }
}

/// The box under the score that says what this session earned.
public struct CelebrationBox: Equatable, Sendable {
    public enum Icon: Equatable, Sendable { case trophy, flame, badge(Badge) }

    public struct Row: Equatable, Sendable {
        public let icon: Icon
        public let text: String
        /// The first row, whichever kind, is the headline.
        public let headline: Bool
    }

    public let rows: [Row]
    /// "+2 more in your profile", when more badges were earned than are named.
    public let more: String?
}

/// The level panel, or what the session did instead of a level.
public struct LevelPanel: Equatable, Sendable {
    public let title: String
    /// "3 of 6"; nil for an adaptive session, which has no rung.
    public let rung: String?
    public let blurb: String
    /// 0...100; nil where there is no bar, because an empty one would read as no progress.
    public let progressPercent: Int?
    public let next: String
}

/// The round track: one pill per round, and what is said about it.
public struct TrackSection: Equatable, Sendable {
    public let rounds: [RoundStat]
    public let plurals: MovementPlurals
    public let atLeast: Bool
    public let hint: String
    public let footnote: String

    public func caption(_ i: Int) -> String { rounds[i].caption(plurals, atLeast: atLeast) }
}

/// One movement's column on the movement card.
public struct MovementColumn: Equatable, Sendable {
    public let movement: Exercise
    public let label: String
    public let reps: Int
    public let atLeast: Bool
    public let lines: [String]
    public let spoken: String
}

public struct MovementsSection: Equatable, Sendable {
    public let columns: [MovementColumn]
    /// Past this many characters a label no longer fits one line in a third of a phone.
    public let tall: Bool
    public let footnote: String
}

/// A big figure with a small word either side: "About 12,940 kg".
public struct Figure: Equatable, Sendable {
    public let prefix: String?
    public let number: String
    public let unit: String
}

/// The card between the level and the comparison: what the session lifted and burned.
public struct LiftedCard: Equatable, Sendable {
    public struct LiftedPart: Equatable, Sendable {
        public let animalEmoji: String?
        public let emojiCount: Int
        /// "×9" when there are more of the animal than are drawn.
        public let more: String?
        public let figure: Figure
        public let sentence: String?
    }

    public struct BurnedPart: Equatable, Sendable {
        public let figure: Figure
        public let emoji: String?
        public let sentence: String?
    }

    public let lifted: LiftedPart?
    public let burned: BurnedPart?
    public let note: String
    /// One sentence for the whole card: its parts are hidden, and the emoji, which a screen reader
    /// would otherwise name one by one, are never announced on their own.
    public let spoken: String
}

public enum LiftedSection: Equatable, Sendable {
    case hidden
    /// With no body weight on file, a row inviting the athlete to enter it.
    case invite
    case card(LiftedCard)
}

/// The card for the earlier session this one is measured against.
public struct ComparisonCard: Equatable, Sendable {
    public let attemptAtMillis: Int64
    public let referenceLine: String
    public let deltaLine: String
    /// Green when this session is ahead on reps.
    public let ahead: Bool
    public var spoken: String { "\(referenceLine), \(deltaLine)" }
}

public struct CompareSection: Equatable, Sendable {
    public let labels: [String]
    public let chosen: Int
    public let card: ComparisonCard
}

/// The round splits chart, its note, and what is read out above it.
public struct SplitsSection: Equatable, Sendable {
    public let split: RoundSplits.Split
    public let reference: [Int64?]
    public let note: String
    public let averageLabel: String
}

/// The session timeline: its lanes, the stops, and the words around it.
public struct TimelineSection {
    public let timeline: SessionTimeline
    public let lanes: [TimelineLane]
    public let stops: [TimelineStop]
    public let description: String
    public let legend: String?
}

/// The heart-rate card.
public struct HeartCard: Equatable, Sendable {
    public struct Figure: Equatable, Sendable {
        public let label: String
        public let value: String
        public let unit: String
        public let spoken: String
    }

    public struct ZoneRow: Equatable, Sendable {
        public let zone: HeartZone
        public let name: String
        public let time: String
        public let range: String
        public let spoken: String
        public let ms: Int64
    }

    public let figures: [Figure]
    public let zones: [ZoneRow]?
    public let zoneTimes: [ZoneTime]?
    /// With no age on file there are no zones: an invitation instead, which asks for the year.
    public let invitesAge: Bool
    public let hardestRound: String?
    public let hardestRoundSpoken: String?
    public let verdict: String?
    public let footnote: String
    public let coveredMs: Int64
}
