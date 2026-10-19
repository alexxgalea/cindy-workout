import UIKit
import UserNotifications
import CindyCore

/// The daily reminder, handed to the system. `ReminderPlan` decides what is scheduled and what each
/// says; this asks for permission, holds the requests, and keeps them in line with the records.
///
/// iOS runs no code when a notification fires, so a day's words cannot be worked out then. The next
/// week is scheduled beforehand as separate one-off requests, and planned again on launch, whenever
/// the app comes forward, after each saved session, when the time zone or the clock changes, and when
/// the setting does.
@MainActor
final class ReminderCenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = ReminderCenter()

    /// Kept apart from the week's requests, so that planning again cannot take it away.
    private static let tryID = "try-reminder"

    private let center = UNUserNotificationCenter.current()
    /// What iOS last said, refreshed whenever the app comes forward: the athlete can change it in
    /// Settings at any time.
    private(set) var access: NotificationAccess = .undecided
    /// Planning runs one at a time, each on the state of its own moment, so two of them close
    /// together cannot leave a request the later one dropped.
    private var planning: Task<Void, Never>?

    func start() {
        center.delegate = self
        let notifications = NotificationCenter.default
        for name in [UIApplication.willEnterForegroundNotification, UIApplication.significantTimeChangeNotification,
                     .NSSystemTimeZoneDidChange] {
            notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refresh(); self?.replan() }
            }
        }
        Task { await refresh(); replan() }
    }

    // MARK: - permission

    func refresh() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: access = .allowed
        case .notDetermined: access = .undecided
        default: access = .refused
        }
    }

    /// Asks iOS, if it has not been asked, and calls `done` with the answer.
    func request(_ done: @escaping (NotificationAccess) -> Void) {
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            await refresh()
            replan()
            done(access)
        }
    }

    // MARK: - the plan

    /// Brings the requests in line with the setting and the records. Cheap to call too often.
    func replan() {
        let before = planning
        planning = Task { [weak self] in
            await before?.value
            await self?.run()
        }
    }

    private func run() async {
        let profile = Profile()
        let zone = Zone(TimeZone.current.identifier)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let planned = ReminderPlan.plan(
            now: ZonedDateTime(epochMs: nowMs, zone: zone), minuteOfDay: profile.reminderMinute,
            on: profile.reminderOn, access: access, attempts: RecordStore().all(),
            firstDayOfWeek: Self.firstDayOfWeek)
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(ReminderPlan.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        for reminder in planned {
            let when = DateComponents(year: reminder.day.year, month: reminder.day.month, day: reminder.day.day,
                                      hour: reminder.minuteOfDay / 60, minute: reminder.minuteOfDay % 60)
            try? await center.add(UNNotificationRequest(
                identifier: reminder.id, content: Self.content(reminder.message),
                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
        }
    }

    /// Sends today's reminder now, as if today had not been trained, so the athlete can see it.
    func tryIt() {
        let zone = Zone(TimeZone.current.identifier)
        let today = zone.localDate(epochMs: Int64(Date().timeIntervalSince1970 * 1000))
        let message = Reminder.preview(RecordStore().all(), today: today, zone: zone,
                                       firstDayOfWeek: Self.firstDayOfWeek)
        center.add(UNNotificationRequest(
            identifier: Self.tryID, content: Self.content(message),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    private static func content(_ message: Reminder.Message) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.threadIdentifier = "daily-reminder"
        return content
    }

    private static var firstDayOfWeek: DayOfWeek {
        DayOfWeek(rawValue: (Calendar.current.firstWeekday + 5) % 7 + 1) ?? .monday
    }

    // MARK: - while the app is open

    /// Not during a live workout: the reminder is meant to prompt a session, not interrupt the one
    /// that is running. TRY IT is the athlete asking, so it always shows.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        let asked = notification.request.identifier == Self.tryID
        done(asked || ReminderPlan.showsInApp(liveWorkout: LiveWorkout.active) ? [.banner, .sound] : [])
    }
}
