import SwiftUI
import CindyCore

/// Whether the daily reminder is on, and when. TRY IT sends one now, so the athlete can see it.
///
/// `ReminderPlan` decides what SAVE does about notification permission: turning it on asks iOS once,
/// and a refusal leaves it off and says why, so the switch never claims a reminder that cannot arrive.
struct ReminderSheet: View {
    let profile: Profile
    /// Said on the menu once it is set.
    let show: (String) -> Void
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
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
        NavigationStack {
            List {
                Section {
                    Toggle(ReminderPlan.toggleLabel, isOn: $on)
                    DatePicker(ReminderPlan.timeLabel, selection: $time, displayedComponents: .hourAndMinute)
                        .accessibilityLabel(ReminderPlan.timeDescription(Reminder.formatTime(minuteOfDay, is24Hour: is24Hour)))
                } header: {
                    Text(ReminderPlan.sheetTitle.uppercased())
                } footer: {
                    Text(ReminderPlan.sheetSubtitle + " " + ReminderPlan.sheetNote)
                }
                Section {
                    Button(ReminderPlan.tryItLabel) { tryIt() }
                        .accessibilityIdentifier("reminderTry")
                }
            }
            .navigationTitle(ReminderPlan.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ReminderPlan.saveLabel.capitalized) { save(asked: false) }
                }
            }
            .alert(ReminderPlan.offTitle, isPresented: $notificationsOff) {
                Button(ReminderPlan.openSettingsLabel) {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button(ReminderPlan.notNowLabel, role: .cancel) {}
            } message: {
                Text(ReminderPlan.offSubtitle)
            }
        }
        .presentationDetents([.medium, .large])
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
        dismiss()
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
