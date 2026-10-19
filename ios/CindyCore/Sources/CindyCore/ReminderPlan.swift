import Foundation

/// Whether the app may post a notification. Provisional and ephemeral grants post too, so they are
/// `allowed`.
public enum NotificationAccess: Equatable, Sendable {
    /// Not asked yet.
    case undecided
    case allowed
    /// Refused, or switched off for the app in Settings.
    case refused
}

/// One reminder, ready to hand to the system.
public struct PlannedReminder: Equatable, Sendable {
    /// Stable for a day, so planning again replaces the day's request and never doubles it.
    public let id: String
    public let fireAtMs: Int64
    /// The day it is for, in the zone it was planned in.
    public let day: LocalDate
    /// The wall-clock time to fire at, in that zone.
    public let minuteOfDay: Int
    public let message: Reminder.Message
}

/// What a tap on SAVE does about notification permission.
public enum ReminderSaveStep: Equatable, Sendable {
    /// Turned off: nothing to ask, and every request goes.
    case turnedOff
    /// Turning on, and iOS has not been asked yet.
    case ask
    /// Turned on, with the words to say.
    case set(toast: String)
    /// Turning on was refused: it stays off and says why, so the switch never claims a reminder that
    /// cannot arrive.
    case refused
}

/// What TRY IT does.
public enum ReminderTryStep: Equatable, Sendable {
    case ask
    case send
    case refused
}

/// The reminder as a plan.
///
/// iOS runs no code when a notification fires, so what Android works out at that moment, from the
/// records of the day, has to be worked out beforehand. The next seven days are scheduled as separate
/// one-off requests, each with the text `Reminder` gives for that day, and the plan is made again
/// whenever its premises change: on launch, after each session, when the time zone changes and when
/// the setting does. A session that is saved today has today's request removed by that last replan,
/// because today's message is then nil.
///
/// Delivery is on time, so Android's rule that drops a reminder delivered hours late has nothing to
/// do here.
public enum ReminderPlan {

    /// How many days ahead are scheduled. A week, which is as far as an athlete goes without opening
    /// the app before the reminders would be stale anyway.
    public static let days = 7

    public static let idPrefix = "reminder-"

    public static func id(for day: LocalDate) -> String { idPrefix + day.description }

    /// The requests to hold from `now`, and none at all when the reminder is off or the app may not
    /// post: asking again for permission later plans them then.
    ///
    /// Each day is worked out as if the athlete did not train between now and then, which is the
    /// only thing known; a session that is saved changes the premise, and the plan is made again.
    public static func plan(now: ZonedDateTime, minuteOfDay: Int, on: Bool, access: NotificationAccess,
                            attempts: [Attempt], firstDayOfWeek: DayOfWeek) -> [PlannedReminder] {
        guard on, access == .allowed else { return [] }
        var out: [PlannedReminder] = []
        var fire = Reminder.nextFire(now, minuteOfDay: minuteOfDay)
        for _ in 0..<days {
            let day = fire.localDate
            if let message = Reminder.message(attempts, today: day, zone: now.zone, firstDayOfWeek: firstDayOfWeek) {
                out.append(PlannedReminder(id: id(for: day), fireAtMs: fire.epochMs, day: day,
                                           minuteOfDay: fire.minuteOfDay, message: message))
            }
            // The next day's time, worked out afresh so a day with a clock change keeps its hour.
            fire = Reminder.nextFire(ZonedDateTime(epochMs: fire.epochMs, zone: now.zone), minuteOfDay: minuteOfDay)
        }
        return out
    }

    /// Whether a notification that arrives while the app is open is shown. Not during a live
    /// workout: the reminder is meant to prompt a session, not interrupt the one that is running.
    public static func showsInApp(liveWorkout: Bool) -> Bool { !liveWorkout }

    // MARK: - the sheet

    public static let sheetTitle = "Daily reminder"
    public static let sheetSubtitle =
        "One nudge at the time you choose, and none on days you've already trained."
    public static let sheetNote = "Nothing leaves the phone. The reminder is worked out and sent on this device."
    public static let toggleLabel = "Remind me"
    public static let timeLabel = "Time"
    public static let timePickerTitle = "Reminder time"

    /// What a screen reader says of the time row.
    public static func timeDescription(_ time: String) -> String { "Time, \(time), tap to change" }

    /// What SAVE does, given the answer iOS has on file.
    public static func save(on: Bool, minuteOfDay: Int, is24Hour: Bool, access: NotificationAccess) -> ReminderSaveStep {
        guard on else { return .turnedOff }
        switch access {
        case .undecided: return .ask
        case .refused: return .refused
        case .allowed: return .set(toast: "Reminder set for \(Reminder.formatTime(minuteOfDay, is24Hour: is24Hour))")
        }
    }

    public static func tryIt(access: NotificationAccess) -> ReminderTryStep {
        switch access {
        case .undecided: return .ask
        case .allowed: return .send
        case .refused: return .refused
        }
    }

    public static let tryItLabel = "TRY IT"
    public static let saveLabel = "SAVE"

    // MARK: - when notifications are off

    public static let offTitle = "Notifications are off"
    public static let offSubtitle = "Cindy can't remind you until notifications are allowed for it."
    public static let openSettingsLabel = "OPEN SETTINGS"
    public static let notNowLabel = "NOT NOW"

    /// The notification's words around what `Reminder` says: the channel on Android is described as
    /// this, and iOS has no channels, so it is only the Settings line.
    public static let settingsDescription = "One nudge a day, and none on days you have trained."
}
