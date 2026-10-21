import SwiftUI
import CindyCore

/// Whether the daily reminder is on, and when (`chooseReminder`). TRY IT sends one now, so the athlete
/// can see it.
///
/// `ReminderPlan` decides what SAVE does about notification permission: turning it on asks iOS once,
/// and a refusal leaves it off and says why, in the sheet's second panel (`notificationsOff`), so the
/// switch never claims a reminder that cannot arrive. SAVE closes the sheet itself, once it knows.
struct ReminderSheet: View {
    let profile: Profile
    /// Said on the menu once it is set.
    let show: (String) -> Void
    let onChanged: () -> Void
    @Environment(\.closeCindySheet) private var close
    @State private var on: Bool
    @State private var time: Date
    @State private var notificationsOff = false

    init(profile: Profile, show: @escaping (String) -> Void, onChanged: @escaping () -> Void) {
        self.profile = profile
        self.show = show
        self.onChanged = onChanged
        _on = State(initialValue: profile.reminderOn)
        let minute = profile.reminderMinute
        _time = State(initialValue: Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60,
                                                          second: 0, of: Date()) ?? Date())
    }

    private var minuteOfDay: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private var is24Hour: Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    var body: some View {
        if notificationsOff { off } else { reminder }
    }

    private var reminder: some View {
        CindyPanel(title: ReminderPlan.sheetTitle, subtitle: ReminderPlan.sheetSubtitle,
                   // Closes itself: asking iOS for notifications answers later than the tap.
                   primary: SheetButton(title: ReminderPlan.saveLabel) { save(asked: false) }.keepingOpen { true },
                   secondary: SheetButton(title: ReminderPlan.tryItLabel) { tryIt() },
                   secondaryDismisses: false) {
            VStack(alignment: .leading, spacing: 0) {
                SheetToggle(ReminderPlan.toggleLabel, isOn: $on)
                timeRow
                SheetNote(ReminderPlan.sheetNote)
            }
        }
    }

    /// A glass row, at least 52 high: `Time` and the time, which is the system's own picker.
    private var timeRow: some View {
        HStack(spacing: 0) {
            Text(ReminderPlan.timeLabel).cindy(.callout, colour: Palette.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .accessibilityLabel(ReminderPlan.timeDescription(Reminder.formatTime(minuteOfDay, is24Hour: is24Hour)))
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 8)
        .frame(minHeight: 52)
        .glassCard()
        .padding(.top, 12)
    }

    /// Why nothing was set, and the way to Settings, where a refused permission is changed.
    private var off: some View {
        CindyPanel(title: ReminderPlan.offTitle, subtitle: ReminderPlan.offSubtitle,
                   primary: SheetButton(title: ReminderPlan.openSettingsLabel) {
                       if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                           UIApplication.shared.open(url)
                       }
                   },
                   secondary: SheetButton(title: ReminderPlan.notNowLabel) {})
    }

    private func save(asked: Bool) {
        let center = ReminderCenter.shared
        profile.reminderMinute = minuteOfDay
        switch ReminderPlan.save(on: on, minuteOfDay: minuteOfDay, is24Hour: is24Hour, access: center.access) {
        case .turnedOff:
            profile.reminderOn = false
            finish()
        case .ask where !asked:
            center.request { _ in save(asked: true) }
        case .ask, .refused:
            // Asked, and still not answered, is as good as refused.
            profile.reminderOn = false
            center.replan()
            onChanged()
            notificationsOff = true
        case .set(let toast):
            profile.reminderOn = true
            show(toast)
            finish()
        }
    }

    private func finish() {
        ReminderCenter.shared.replan()
        onChanged()
        close()
    }

    private func tryIt() {
        let center = ReminderCenter.shared
        switch ReminderPlan.tryIt(access: center.access) {
        case .send: center.tryIt()
        case .ask: center.request { access in if access == .allowed { center.tryIt() } else { notificationsOff = true } }
        case .refused: notificationsOff = true
        }
    }
}
