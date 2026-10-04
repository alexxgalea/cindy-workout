import Foundation

/// Something the results screen celebrates. `kind` picks the icon.
public struct Celebration: Equatable, Sendable {
    public enum Kind: Sendable { case first, record, daily, weekly }

    public let kind: Kind
    public let text: String

    public init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

/// The encouraging sentences of the progress report and the results screen.
///
/// Every line is literally true for the data it is given, and none of them scolds: a lapsed streak
/// is met with an invitation, never a reproach. Pure, so the wording can be tested. Port of `Cheer.kt`.
public enum Cheer {

    private static func unit(_ n: Int, _ noun: String) -> String { n == 1 ? noun : "\(noun)s" }

    private static func plural(_ n: Int, _ noun: String) -> String { "\(n) \(unit(n, noun))" }

    /// The line the progress report opens with. Always true; never a guilt trip.
    public static func headline(_ attempts: [Attempt], today: LocalDate, zone: Zone, firstDayOfWeek: DayOfWeek) -> String {
        // Rule 1: nothing recorded yet.
        var latestOrNil: Attempt?
        for a in attempts where latestOrNil == nil || a.atMillis > latestOrNil!.atMillis { latestOrNil = a }
        guard let latest = latestOrNil else { return "Your first Cindy starts everything." }
        let days = Streak.daysTrained(attempts, zone: zone)
        let current = Streak.current(days, today: today)
        // The longest run other than the current one: a tie with it is not a new record.
        let longestBefore = Streak.longest(days.subtracting(Streak.currentRun(days, today: today)))
        let weeks = Streak.weeksTrained(days, firstDayOfWeek: firstDayOfWeek)
        let w = Streak.currentWeeks(weeks, today: today, firstDayOfWeek: firstDayOfWeek)
        let trainedToday = days.contains(today)
        let s = Progress.summary(attempts, today: today, zone: zone, firstDayOfWeek: firstDayOfWeek)

        let latestIsToday = Progress.localDate(latest, zone: zone) == today
        if latestIsToday && Records.isPersonalRecord(attempts, of: latest) {
            return "New personal record: \(latest.scoreLabel)."
        }
        if trainedToday && Streak.isMilestone(current, Streak.dailyMilestones) {
            return "\(current) days in a row."
        }
        if trainedToday && current >= 2 && current > longestBefore {
            return "Longest streak yet: \(current) days."
        }
        if Streak.atRisk(days, today: today) && current >= 1 {
            return "Train today to make it \(current + 1) days."
        }
        if weeks.contains(Streak.weekStart(today, firstDayOfWeek: firstDayOfWeek)) && w >= 2 {
            return "\(w) weeks in a row."
        }
        if Streak.weekAtRisk(weeks, today: today, firstDayOfWeek: firstDayOfWeek) && w >= 1 {
            return "A session this week makes it \(w + 1) weeks in a row."
        }
        if s.thisWeek.sessions >= 1 && s.thisWeek.sessions > s.lastWeek.sessions {
            let diff = s.thisWeek.sessions - s.lastWeek.sessions
            return "\(plural(s.thisWeek.sessions, "session")) this week, \(diff) more than last week."
        }
        let own = Records.inCategory(attempts, profile: latest.profile)
        var first = latest
        var firstSet = false
        for a in own where !firstSet || a.atMillis < first.atMillis { first = a; firstSet = true }
        let best = Records.bestIn(attempts, profile: latest.profile) ?? latest
        let delta = best.totalReps - first.totalReps
        if delta > 0 {
            return "Your best is \(delta) reps above your first \(latest.profile?.mode.label ?? "session")."
        }
        return "Your best is \(best.scoreLabel)."
    }

    /// What the next milestone costs, or nil. Shown under the streak numbers.
    public static func nextStep(_ attempts: [Attempt], today: LocalDate, zone: Zone, firstDayOfWeek: DayOfWeek) -> String? {
        let days = Streak.daysTrained(attempts, zone: zone)
        let current = Streak.current(days, today: today)
        let weeks = Streak.weeksTrained(days, firstDayOfWeek: firstDayOfWeek)
        let w = Streak.currentWeeks(weeks, today: today, firstDayOfWeek: firstDayOfWeek)
        if current >= 1, let m = Streak.nextMilestone(current, Streak.dailyMilestones) {
            return "\(m - current) more \(unit(m - current, "day")) to a \(m)-day streak."
        }
        if w >= 1, let m = Streak.nextMilestone(w, Streak.weeklyMilestones) {
            return "\(m - w) more \(unit(m - w, "week")) to a \(m)-week streak."
        }
        return nil
    }

    /// Up to two celebrations for the results screen, most important first.
    public static func forResult(_ attempts: [Attempt], _ attempt: Attempt, zone: Zone, firstDayOfWeek: DayOfWeek) -> [Celebration] {
        // Zero-rep attempts are never stored, so an attempt that is not here was not saved.
        if !attempts.contains(where: { $0.atMillis == attempt.atMillis }) { return [] }
        let before = attempts.filter { $0.atMillis != attempt.atMillis }
        let day = Progress.localDate(attempt, zone: zone)
        if before.isEmpty { return [Celebration(.first, "First Cindy on the board.")] }
        var out: [Celebration] = []
        if Records.isPersonalRecord(attempts, of: attempt) {
            out.append(Celebration(.record, "New personal record."))
        }
        let daysBefore = Streak.daysTrained(before, zone: zone)
        if !daysBefore.contains(day) {
            let after = Streak.current(Streak.daysTrained(attempts, zone: zone), today: day)
            if Streak.isMilestone(after, Streak.dailyMilestones) {
                out.append(Celebration(.daily, "\(after) days in a row."))
            } else if after >= 2 && after > Streak.longest(daysBefore) {
                out.append(Celebration(.daily, "Longest streak yet: \(after) days."))
            }
        }
        let weeksBefore = Streak.weeksTrained(daysBefore, firstDayOfWeek: firstDayOfWeek)
        if !weeksBefore.contains(Streak.weekStart(day, firstDayOfWeek: firstDayOfWeek)) {
            let weeksAfter = Streak.weeksTrained(Streak.daysTrained(attempts, zone: zone), firstDayOfWeek: firstDayOfWeek)
            let wAfter = Streak.currentWeeks(weeksAfter, today: day, firstDayOfWeek: firstDayOfWeek)
            if Streak.isMilestone(wAfter, Streak.weeklyMilestones) {
                out.append(Celebration(.weekly, "\(wAfter) weeks in a row."))
            }
        }
        return Array(out.prefix(2))
    }
}
