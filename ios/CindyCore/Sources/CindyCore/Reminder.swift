import Foundation

/// When the daily reminder fires and what it says.
///
/// Pure: the clock, the zone and the first day of the week are all parameters, so daylight-saving
/// changes and the "already trained today" rule can be tested without a phone. Port of `Reminder.kt`.
public enum Reminder {
    /// Six in the evening: late enough that a morning session has already cancelled it.
    public static let defaultMinuteOfDay = 18 * 60

    /// Delivered later than this, a reminder is about a moment that has passed.
    public static let lateLimitMs: Int64 = 2 * 60 * 60 * 1000

    /// How early an alarm may arrive and still count as on time.
    private static let earlyLimitMs: Int64 = 60_000

    public struct Message: Equatable, Sendable {
        public let title: String
        public let body: String

        public init(_ title: String, _ body: String) {
            self.title = title
            self.body = body
        }
    }

    /// The next time at `minuteOfDay` strictly after `now`, in `now`'s zone.
    ///
    /// A time inside a spring-forward gap is moved to the hour after it, and the earlier offset is
    /// taken when a fall-back hour happens twice (`Zone.epochMs`), so no special cases are needed.
    public static func nextFire(_ now: ZonedDateTime, minuteOfDay: Int) -> ZonedDateTime {
        func on(_ date: LocalDate) -> ZonedDateTime {
            ZonedDateTime.of(date, hour: minuteOfDay / 60, minute: minuteOfDay % 60, zone: now.zone)
        }
        let today = on(now.localDate)
        return today.isAfter(now) ? today : on(now.localDate.plusDays(1))
    }

    /// Whether an alarm meant for `targetMillis` is still worth posting at `nowMillis`.
    ///
    /// Only the gap matters, not the date: a 23:50 reminder that the system delivers at 00:05 is
    /// still fifteen minutes late, well inside `lateLimitMs`.
    public static func shouldPost(_ targetMillis: Int64, _ nowMillis: Int64) -> Bool {
        targetMillis > 0 && (-earlyLimitMs...lateLimitMs).contains(nowMillis - targetMillis)
    }

    /// What to say today, or nil when today is already trained.
    public static func message(_ attempts: [Attempt], today: LocalDate, zone: Zone, firstDayOfWeek: DayOfWeek) -> Message? {
        let days = Streak.daysTrained(attempts, zone: zone)
        // Rule 1: nothing to remind about.
        if days.contains(today) { return nil }
        // Rule 2: nothing recorded yet.
        var latestOrNil: Attempt?
        for a in attempts where latestOrNil == nil || a.atMillis > latestOrNil!.atMillis { latestOrNil = a }
        guard let latest = latestOrNil else {
            return Message("Time for your first Cindy",
                           "Twenty minutes: 5 pull-ups, 10 push-ups, 15 squats, as many rounds as you can.")
        }
        let current = Streak.current(days, today: today)
        let atRisk = Streak.atRisk(days, today: today)
        // Rule 3.
        if atRisk && current >= 2 {
            return Message("Keep your \(current)-day streak going", "Train today and it's \(current + 1).")
        }
        // Rule 4.
        if atRisk && current == 1 {
            return Message("Make it two days in a row", "You trained yesterday. Twenty minutes today starts a streak.")
        }
        // Rule 5: only on the last day of the week, so it never nags early in the week.
        let weeks = Streak.weeksTrained(days, firstDayOfWeek: firstDayOfWeek)
        if Streak.weekAtRisk(weeks, today: today, firstDayOfWeek: firstDayOfWeek)
            && today.plusDays(1).dayOfWeek == firstDayOfWeek {
            let w = Streak.currentWeeks(weeks, today: today, firstDayOfWeek: firstDayOfWeek)
            return Message("Last day to keep your \(w)-week streak", "One session today and it's \(w + 1) weeks.")
        }
        // Rule 6.
        let best = Records.bestIn(attempts, profile: latest.profile) ?? latest
        return Message("Cindy's ready when you are", "Your best is \(best.scoreLabel). Twenty minutes to chase it.")
    }

    /// What a reminder would say today, as if today had not been trained. For TRY IT.
    public static func preview(_ attempts: [Attempt], today: LocalDate, zone: Zone, firstDayOfWeek: DayOfWeek) -> Message {
        let untrainedToday = attempts.filter { Progress.localDate($0, zone: zone) != today }
        // Never nil in practice, but the type allows it; a fallback beats a crash in a demo.
        return message(untrainedToday, today: today, zone: zone, firstDayOfWeek: firstDayOfWeek)
            ?? Message("Cindy's ready when you are", "Twenty minutes, as many rounds as you can.")
    }

    /// "18:00", or "6:00 PM" on a 12-hour phone.
    public static func formatTime(_ minuteOfDay: Int, is24Hour: Bool) -> String {
        let h = minuteOfDay / 60
        let m = minuteOfDay % 60
        if is24Hour { return String(format: "%02ld:%02ld", h, m) }
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%ld:%02ld", hour12, m) + (h < 12 ? " AM" : " PM")
    }
}
