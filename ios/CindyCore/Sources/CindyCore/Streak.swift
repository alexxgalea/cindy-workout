import Foundation

/// Which days were trained, and how many of them ran back to back.
///
/// Days are local days, not 24-hour blocks: a workout at 23:50 and one at 00:10 are two days
/// apart by the calendar the athlete lives in, which is the one that matters for a streak.
///
/// Port of `Streak.kt`. The zone and the first day of the week are always passed in.
public enum Streak {

    /// The distinct local dates on which any attempt was recorded.
    public static func daysTrained(_ attempts: [Attempt], zone: Zone) -> Set<LocalDate> {
        Set(attempts.map { zone.localDate(epochMs: $0.atMillis) })
    }

    /// The run of consecutive days ending today, or yesterday.
    ///
    /// Yesterday counts because a streak should not be reported as broken by a day the athlete
    /// has not finished living yet: at nine in the morning, "3 days" is the truth and "0" is a lie
    /// that would also be undone by training that afternoon.
    public static func current(_ days: Set<LocalDate>, today: LocalDate) -> Int {
        let from: LocalDate
        if days.contains(today) { from = today }
        else if days.contains(today.minusDays(1)) { from = today.minusDays(1) }
        else { return 0 }
        var count = 0
        var day = from
        while days.contains(day) {
            count += 1
            day = day.minusDays(1)
        }
        return count
    }

    /// The longest run of consecutive days ever recorded.
    public static func longest(_ days: Set<LocalDate>) -> Int {
        if days.isEmpty { return 0 }
        var best = 0
        for day in days {
            // Count each run once, from the end that has no day before it.
            if days.contains(day.minusDays(1)) { continue }
            var length = 0
            var cursor = day
            while days.contains(cursor) {
                length += 1
                cursor = cursor.plusDays(1)
            }
            if length > best { best = length }
        }
        return best
    }

    /// True when training today would extend the current streak rather than start a new one.
    public static func atRisk(_ days: Set<LocalDate>, today: LocalDate) -> Bool {
        !days.contains(today) && days.contains(today.minusDays(1))
    }

    /// Streak lengths worth saying out loud, in days.
    public static let dailyMilestones = [3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 365]

    /// The same for the weekly streak, in weeks.
    public static let weeklyMilestones = [2, 4, 8, 12, 26, 52]

    /// The first day of the week `date` falls in, where the locale says weeks start.
    public static func weekStart(_ date: LocalDate, firstDayOfWeek: DayOfWeek) -> LocalDate {
        date.previousOrSame(firstDayOfWeek)
    }

    /// The start of every week in which any day was trained.
    public static func weeksTrained(_ days: Set<LocalDate>, firstDayOfWeek: DayOfWeek) -> Set<LocalDate> {
        Set(days.map { weekStart($0, firstDayOfWeek: firstDayOfWeek) })
    }

    /// The run of consecutive trained weeks ending this week, or last week.
    ///
    /// Last week counts for the same reason yesterday does in `current`: this week is not over, so a
    /// run that reached last week is not broken yet, merely not extended.
    public static func currentWeeks(_ weeks: Set<LocalDate>, today: LocalDate, firstDayOfWeek: DayOfWeek) -> Int {
        let thisWeek = weekStart(today, firstDayOfWeek: firstDayOfWeek)
        let from: LocalDate
        if weeks.contains(thisWeek) { from = thisWeek }
        else if weeks.contains(thisWeek.minusWeeks(1)) { from = thisWeek.minusWeeks(1) }
        else { return 0 }
        var count = 0
        var week = from
        while weeks.contains(week) {
            count += 1
            week = week.minusWeeks(1)
        }
        return count
    }

    /// The longest run of consecutive trained weeks ever recorded.
    public static func longestWeeks(_ weeks: Set<LocalDate>) -> Int {
        var best = 0
        for week in weeks {
            // Count each run once, from the end that has no week before it.
            if weeks.contains(week.minusWeeks(1)) { continue }
            var length = 0
            var cursor = week
            while weeks.contains(cursor) {
                length += 1
                cursor = cursor.plusWeeks(1)
            }
            if length > best { best = length }
        }
        return best
    }

    /// True when this week has no session yet but last week did.
    public static func weekAtRisk(_ weeks: Set<LocalDate>, today: LocalDate, firstDayOfWeek: DayOfWeek) -> Bool {
        let thisWeek = weekStart(today, firstDayOfWeek: firstDayOfWeek)
        return !weeks.contains(thisWeek) && weeks.contains(thisWeek.minusWeeks(1))
    }

    /// The days of the current daily streak (see `current`), for painting; empty if none.
    public static func currentRun(_ days: Set<LocalDate>, today: LocalDate) -> Set<LocalDate> {
        let from: LocalDate
        if days.contains(today) { from = today }
        else if days.contains(today.minusDays(1)) { from = today.minusDays(1) }
        else { return [] }
        var run = Set<LocalDate>()
        var day = from
        while days.contains(day) {
            run.insert(day)
            day = day.minusDays(1)
        }
        return run
    }

    /// First and last day of the longest daily run; the most recent one on a tie; nil if none.
    public static func longestRun(_ days: Set<LocalDate>) -> ClosedRange<LocalDate>? {
        var best: ClosedRange<LocalDate>?
        var bestLength = 0
        for day in days.sorted() {
            if days.contains(day.minusDays(1)) { continue }
            var end = day
            while days.contains(end.plusDays(1)) { end = end.plusDays(1) }
            let length = end.epochDay - day.epochDay + 1
            // Sorted oldest first, so >= lets a later run win a tie.
            if length >= bestLength {
                best = day...end
                bestLength = length
            }
        }
        return best
    }

    /// First and last week start of the longest weekly run; most recent on a tie; nil if none.
    public static func longestWeeksRun(_ weeks: Set<LocalDate>) -> ClosedRange<LocalDate>? {
        var best: ClosedRange<LocalDate>?
        var bestLength = 0
        for week in weeks.sorted() {
            if weeks.contains(week.minusWeeks(1)) { continue }
            var end = week
            while weeks.contains(end.plusWeeks(1)) { end = end.plusWeeks(1) }
            let length = (end.epochDay - week.epochDay) / 7 + 1
            if length >= bestLength {
                best = week...end
                bestLength = length
            }
        }
        return best
    }

    /// The first milestone above `current`, or nil past the last one.
    public static func nextMilestone(_ current: Int, _ milestones: [Int]) -> Int? {
        milestones.first { $0 > current }
    }

    /// Whether `current` lands exactly on a milestone.
    public static func isMilestone(_ current: Int, _ milestones: [Int]) -> Bool {
        milestones.contains(current)
    }
}
