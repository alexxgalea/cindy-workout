import Foundation

/// What a badge is about, in the order the profile lists them.
public enum BadgeFamily: CaseIterable, Sendable {
    case sessions, rounds, streaks, volume, pace, craft

    public var label: String {
        switch self {
        case .sessions: return "Sessions"
        case .rounds: return "Rounds"
        case .streaks: return "Streaks"
        case .volume: return "Volume"
        case .pace: return "Pace"
        case .craft: return "Craft"
        }
    }
}

/// What earns a badge, so that one evaluator reads the whole catalogue.
enum BadgeRule: Sendable {
    /// Sessions finished, of any kind.
    case sessions
    /// Rounds in one standard Cindy the camera could stand behind.
    case roundCount
    /// A standard Cindy that passed the benchmark.
    case benchmark
    /// Consecutive days trained.
    case days
    /// Consecutive weeks trained.
    case weeks
    /// Reps across every session.
    case reps
    /// A round in a standard Cindy faster than a number of seconds.
    case roundSeconds
    /// A whole twenty minutes the camera read, with nothing tapped in, in a session recorded by a
    /// build that counted reps, since an older one cannot say whether anything was.
    case everyRepSeen
    /// A session at movements other than the standard three.
    case adaptive
}

private func rungRequirement(_ level: Level, _ rest: String = "") -> String {
    "\(level.minRounds) rounds in a standard Cindy\(rest)."
}

/// Everything an athlete can earn, in the order the profile shows it.
///
/// Each badge is a fact about the sessions already recorded, worked out by `Badges` rather than
/// stored: it cannot disagree with the record board, it comes back with it from a backup, and it
/// goes when the records are cleared. Nothing here is a reward for opening the app.
///
/// The rules follow the ones the rest of the app already keeps. A badge about a score is earned
/// only by a standard Cindy the camera could stand behind, the same line a personal record draws,
/// because the rungs are calibrated against the strict workout. A badge about showing up counts
/// every session, lower-bound and adaptive included, because those were still sessions. The round
/// rungs are read from `Level`, so retuning the ladder retunes them. Port of `Badges.kt`.
public enum Badge: CaseIterable, Hashable, Sendable {
    case firstCindy, sessions10, sessions25, sessions50, sessions100
    case firstRound, novice, intermediate, advanced, elite, legend, pastBenchmark
    case streak3, streak7, streak14, streak30, weeks4, weeks12, weeks26
    case reps1000, reps5000, reps10000
    case roundUnder2, roundUnder45
    case everyRepSeen, madeItYours

    struct Spec {
        let title: String
        /// What the badge shows inside its disc: a few characters at most.
        let face: String
        let requirement: String
        let family: BadgeFamily
        let rule: BadgeRule
        /// The figure the rule compares against: sessions, rounds, days, weeks, reps or seconds.
        let target: Int

        init(_ title: String, _ face: String, _ requirement: String, _ family: BadgeFamily,
             _ rule: BadgeRule, _ target: Int = 0) {
            self.title = title
            self.face = face
            self.requirement = requirement
            self.family = family
            self.rule = rule
            self.target = target
        }
    }

    private static func rung(_ level: Level, _ rest: String = "") -> Spec {
        Spec(level.title, "\(level.minRounds)R", rungRequirement(level, rest), .rounds, .roundCount, level.minRounds)
    }

    var spec: Spec {
        switch self {
        case .firstCindy: return Spec("First Cindy", "1st", "Finish your first session.", .sessions, .sessions, 1)
        case .sessions10: return Spec("10 sessions", "×10", "Finish 10 sessions.", .sessions, .sessions, 10)
        case .sessions25: return Spec("25 sessions", "×25", "Finish 25 sessions.", .sessions, .sessions, 25)
        case .sessions50: return Spec("50 sessions", "×50", "Finish 50 sessions.", .sessions, .sessions, 50)
        case .sessions100: return Spec("100 sessions", "×100", "Finish 100 sessions.", .sessions, .sessions, 100)

        case .firstRound: return Spec("First round", "R1", "Complete a round of standard Cindy.", .rounds, .roundCount, 1)
        case .novice: return Self.rung(.novice)
        case .intermediate: return Self.rung(.intermediate, " — a complete Cindy")
        case .advanced: return Self.rung(.advanced)
        case .elite: return Self.rung(.elite)
        case .legend: return Self.rung(.legend, " — level with \(Records.benchmarkName)")
        case .pastBenchmark:
            return Spec("Past \(Records.benchmarkName)", "\(Records.benchmark.totalReps)+",
                        "Beat \(Records.benchmark.rounds) rounds in a standard Cindy.", .rounds, .benchmark)

        case .streak3: return Spec("3 days in a row", "3d", "Train 3 days in a row.", .streaks, .days, 3)
        case .streak7: return Spec("7 days in a row", "7d", "Train 7 days in a row.", .streaks, .days, 7)
        case .streak14: return Spec("14 days in a row", "14d", "Train 14 days in a row.", .streaks, .days, 14)
        case .streak30: return Spec("30 days in a row", "30d", "Train 30 days in a row.", .streaks, .days, 30)
        case .weeks4: return Spec("4 weeks in a row", "4w", "Train in 4 weeks in a row.", .streaks, .weeks, 4)
        case .weeks12: return Spec("12 weeks in a row", "12w", "Train in 12 weeks in a row.", .streaks, .weeks, 12)
        case .weeks26: return Spec("26 weeks in a row", "26w", "Train in 26 weeks in a row.", .streaks, .weeks, 26)

        case .reps1000: return Spec("1,000 reps", "1k", "1,000 reps across all sessions.", .volume, .reps, 1_000)
        case .reps5000: return Spec("5,000 reps", "5k", "5,000 reps across all sessions.", .volume, .reps, 5_000)
        case .reps10000: return Spec("10,000 reps", "10k", "10,000 reps across all sessions.", .volume, .reps, 10_000)

        // The two marks for a round that the Help screen quotes.
        case .roundUnder2:
            return Spec("Round under 2 minutes", "2:00", "A round under 2:00 in a standard Cindy.", .pace, .roundSeconds, 120)
        case .roundUnder45:
            return Spec("Round under 45 seconds", "0:45", "A round under 0:45 in a standard Cindy.", .pace, .roundSeconds, 45)

        case .everyRepSeen:
            return Spec("Every rep seen", "100%",
                        "A full 20 minutes with no reps tapped in and the camera keeping track of you.", .craft, .everyRepSeen)
        case .madeItYours:
            return Spec("Made it yours", "A", "Finish an Adaptive Cindy.", .craft, .adaptive)
        }
    }

    public var title: String { spec.title }
    public var face: String { spec.face }
    public var requirement: String { spec.requirement }
    public var family: BadgeFamily { spec.family }

    /// Its place in the catalogue.
    public var ordinal: Int { Badge.allCases.firstIndex(of: self)! }
}

/// A badge, and the session that first earned it.
public struct EarnedBadge: Equatable, Sendable {
    public let badge: Badge
    public let atMillis: Int64

    public init(_ badge: Badge, _ atMillis: Int64) {
        self.badge = badge
        self.atMillis = atMillis
    }
}

/// How far along a badge that is not yet earned is.
public struct BadgeProgress: Equatable, Sendable {
    public let current: Int
    public let target: Int
    public let unit: String

    public init(_ current: Int, _ target: Int, _ unit: String) {
        self.current = current
        self.target = target
        self.unit = unit
    }

    /// "1,240 of 5,000 reps", said the same way on the tile and in its sheet.
    public var label: String { "\(Progress.formatReps(current)) of \(Progress.formatReps(target)) \(unit)" }
}

/// Works the badges out from the recorded sessions.
///
/// Pure: no clock of its own and no zone of its own, like `Streak` and `Peaks`, which it leans on
/// for what a day and a week are. Nothing is remembered between calls, so a badge is always the
/// answer to "what do these sessions add up to", never to "what was once awarded".
public enum Badges {

    /// A score is only ever credited to a standard Cindy the camera could stand behind.
    private static func standardAndExact(_ a: Attempt) -> Bool {
        a.profile?.isStandard == true && !a.scoreIsLowerBound
    }

    /// Every badge earned, in catalogue order, each stamped with the session that first earned it.
    ///
    /// The sessions are replayed oldest first, keeping what a rule needs as it goes: how many, how
    /// many reps, which days and weeks were trained. Replaying rather than asking once is what makes
    /// the stamp honest: a later, better session does not take an earlier one's badge.
    public static func earned(_ attempts: [Attempt], zone: Zone, firstDayOfWeek: DayOfWeek) -> [EarnedBadge] {
        var stamps: [Badge: Int64] = [:]
        var sessions = 0
        var reps = 0
        var days = Set<LocalDate>()
        var weeks = Set<LocalDate>()

        for a in JavaText.sortedStably(attempts, by: { $0.atMillis }) {
            sessions += 1
            reps += a.totalReps
            let day = Progress.localDate(a, zone: zone)
            let week = Streak.weekStart(day, firstDayOfWeek: firstDayOfWeek)
            days.insert(day)
            weeks.insert(week)
            // Sessions arrive oldest first, so a run can only have grown at its end.
            let dayRun = runEndingAt(day, days) { $0.minusDays(1) }
            let weekRun = runEndingAt(week, weeks) { $0.minusWeeks(1) }

            for badge in Badge.allCases where stamps[badge] == nil
                && met(badge, a, sessions: sessions, reps: reps, dayRun: dayRun, weekRun: weekRun) {
                stamps[badge] = a.atMillis
            }
        }
        return Badge.allCases.compactMap { badge in stamps[badge].map { EarnedBadge(badge, $0) } }
    }

    /// The badges `attempt` itself earned: the ones whose stamp is this session.
    ///
    /// Empty for a session that was never stored. Nothing is stamped with a moment that no stored
    /// session has, which is the same rule `Cheer.forResult` states outright: a score that was never
    /// filed has earned nothing.
    public static func earnedBy(_ attempts: [Attempt], _ attempt: Attempt, zone: Zone, firstDayOfWeek: DayOfWeek) -> [Badge] {
        earned(attempts, zone: zone, firstDayOfWeek: firstDayOfWeek)
            .filter { $0.atMillis == attempt.atMillis }
            .map { $0.badge }
    }

    /// How far along `badge` is, or nil for one that is simply had or not.
    ///
    /// Only the badges that count something have a figure: sessions, rounds, days, weeks and reps.
    /// "Complete a round" at one of one is a yes or a no, and saying "0 of 1" beside it would be noise.
    public static func progress(_ badge: Badge, _ attempts: [Attempt], today: LocalDate, zone: Zone,
                                firstDayOfWeek: DayOfWeek) -> BadgeProgress? {
        let target = badge.spec.target
        if target <= 1 { return nil }
        switch badge.spec.rule {
        case .sessions:
            return BadgeProgress(min(attempts.count, target), target, "sessions")
        case .roundCount:
            let best = attempts.filter(standardAndExact).map { $0.rounds }.max() ?? 0
            return BadgeProgress(min(best, target), target, "rounds")
        case .days:
            let current = Streak.current(Streak.daysTrained(attempts, zone: zone), today: today)
            return BadgeProgress(min(current, target), target, "days")
        case .weeks:
            let weeks = Streak.weeksTrained(Streak.daysTrained(attempts, zone: zone), firstDayOfWeek: firstDayOfWeek)
            let current = Streak.currentWeeks(weeks, today: today, firstDayOfWeek: firstDayOfWeek)
            return BadgeProgress(min(current, target), target, "weeks")
        case .reps:
            return BadgeProgress(min(attempts.reduce(0) { $0 + $1.totalReps }, target), target, "reps")
        case .benchmark, .roundSeconds, .everyRepSeen, .adaptive:
            return nil
        }
    }

    /// A day the way every screen here writes one: "12 Mar 2026", in English whatever the phone speaks.
    public static func day(_ atMillis: Int64, zone: Zone) -> String {
        DateText.long(zone.localDate(epochMs: atMillis))
    }

    /// The line on a badge's sheet: when it was earned, how far along it is, or that it is still to come.
    public static func status(_ earned: EarnedBadge?, _ progress: BadgeProgress?, zone: Zone) -> String {
        if let earned { return "Earned \(day(earned.atMillis, zone: zone))" }
        if let progress { return progress.label }
        return "Not earned yet"
    }

    /// What a tile in the grid says to a screen reader. One sentence, because the tile is one
    /// control, and it says the same thing the sheet behind it does.
    public static func description(_ badge: Badge, _ earned: EarnedBadge?, _ progress: BadgeProgress?, zone: Zone) -> String {
        if let earned { return "\(badge.title), earned \(day(earned.atMillis, zone: zone))" }
        if let progress { return "\(badge.title), locked, \(progress.label)" }
        return "\(badge.title), locked"
    }

    /// The line under the athlete's name on the profile screen.
    public static func trainingLine(_ attempts: [Attempt], zone: Zone) -> String {
        guard let first = attempts.map({ $0.atMillis }).min() else { return "Finish a session and your badges start here." }
        let sessions = attempts.count == 1 ? "1 session" : "\(attempts.count) sessions"
        return "Training since \(day(first, zone: zone)) \u{00B7} \(sessions)"
    }

    /// The highest rung of the ladder among the badges held, or nil before the first.
    ///
    /// Read from the badges rather than from the sessions, so that whatever the menu says the
    /// athlete has reached is something they can open their profile and see earned: a session the
    /// camera could not stand behind never earns a rung, and so never gets one named here either.
    public static func highestLevel(_ earned: [EarnedBadge]) -> Level? {
        Level.allCases.last { level in
            earned.contains { $0.badge.spec.rule == .roundCount && $0.badge.spec.target == level.minRounds }
        }
    }

    /// What the menu says under the athlete's name: how many badges, and the highest level among
    /// them. Nil while there are none, because "0 badges" is a reproach rather than a fact.
    public static func headline(_ earned: [EarnedBadge]) -> String? {
        if earned.isEmpty { return nil }
        let count = earned.count == 1 ? "1 badge" : "\(earned.count) badges"
        return highestLevel(earned).map { "\(count) · \($0.title)" } ?? count
    }

    private static func met(_ badge: Badge, _ a: Attempt, sessions: Int, reps: Int, dayRun: Int, weekRun: Int) -> Bool {
        let spec = badge.spec
        switch spec.rule {
        case .sessions: return sessions >= spec.target
        case .roundCount: return standardAndExact(a) && a.rounds >= spec.target
        case .benchmark: return Records.beatsBenchmark(a)
        case .days: return dayRun >= spec.target
        case .weeks: return weekRun >= spec.target
        case .reps: return reps >= spec.target
        case .roundSeconds:
            return standardAndExact(a) && (a.fastestRoundMs ?? Int64.max) < Int64(spec.target) * 1_000
        // Only a session from a build that counted reps can say none were tapped in. An older one
        // decodes with no taps and no blind time because they were not recorded, not because there
        // were none, and "the camera saw every rep" is not a claim to make from that.
        case .everyRepSeen:
            return a.countedReps != nil && Progress.isFullSession(a) && a.manualReps == 0
                && !a.scoreIsLowerBound && a.totalReps > 0
        // A profile this build cannot read is not claimed as an adaptation: what it was is unknown.
        case .adaptive: return a.profile?.isStandard == false
        }
    }

    /// How many steps back from `end`, one `previous` at a time, are all in `present`.
    private static func runEndingAt(_ end: LocalDate, _ present: Set<LocalDate>, _ previous: (LocalDate) -> LocalDate) -> Int {
        var length = 0
        var cursor = end
        while present.contains(cursor) {
            length += 1
            cursor = previous(cursor)
        }
        return length
    }
}
