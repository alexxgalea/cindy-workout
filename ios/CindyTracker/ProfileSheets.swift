import SwiftUI
import CindyCore

// The sheets that change what the athlete has told the app. What each asks, refuses and keeps is
// decided in CindyCore (`ProfileForms.swift`); these are the fields and lists.

/// A sheet's Save and Cancel, in the toolbar where an iPhone athlete looks for them.
private struct SaveCancel: ViewModifier {
    let title: String
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

private extension View {
    func saveCancel(_ title: String, save: @escaping () -> Void) -> some View {
        modifier(SaveCancel(title: title, save: save))
    }
}

// MARK: - body weight

struct BodyWeightSheet: View {
    let profile: Profile
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var problem: String?
    @FocusState private var focused: Bool

    init(profile: Profile, onSaved: @escaping () -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _text = State(initialValue: BodyWeightForm.initialText(profile))
    }

    var body: some View {
        Form {
            Section {
                TextField(BodyWeightForm.hint, text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .focused($focused)
            } footer: {
                if let problem { Text(problem).foregroundStyle(Color.warn) } else { Text(BodyWeightForm.subtitle) }
            }
        }
        .saveCancel(BodyWeightForm.title) {
            switch BodyWeightForm.save(text, to: profile) {
            case .saved:
                onSaved()
                dismiss()
            case .refused(let message):
                problem = message
            }
        }
        // The athlete opened this to type, so the keyboard comes up with it.
        .onAppear { focused = true }
    }
}

// MARK: - heart-rate details

struct HeartRateDetailsSheet: View {
    let profile: Profile
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var year: String
    @State private var sex: Sex?
    @State private var problem: String?
    @FocusState private var focused: Bool

    init(profile: Profile, onSaved: @escaping () -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _year = State(initialValue: HeartRateDetailsForm.initialYear(profile))
        _sex = State(initialValue: profile.sex)
    }

    var body: some View {
        Form {
            Section {
                TextField(HeartRateDetailsForm.hint, text: $year)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .focused($focused)
            } footer: {
                if let problem { Text(problem).foregroundStyle(Color.warn) } else { Text(HeartRateDetailsForm.subtitle) }
            }
            Section(HeartRateDetailsForm.sexTitle) {
                ForEach(Sex.allCases, id: \.self) { option in
                    Button { sex = option } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                if let note = HeartRateDetailsForm.note(for: option) {
                                    Text(note).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "checkmark").opacity(sex == option ? 1 : 0).accessibilityHidden(true)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel(option.label + (HeartRateDetailsForm.note(for: option).map { ", \($0)" } ?? ""))
                    .accessibilityAddTraits(sex == option ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .saveCancel(HeartRateDetailsForm.title) {
            let nowYear = Calendar.current.component(.year, from: Date())
            switch HeartRateDetailsForm.save(year: year, sex: sex, nowYear: nowYear, to: profile) {
            case .saved:
                onSaved()
                dismiss()
            case .refused(let message):
                problem = message
            }
        }
        .onAppear { focused = true }
    }
}

// MARK: - movements

/// "Make Cindy yours": one choice per movement, taken before the clock starts.
struct MovementsSheet: View {
    let profile: Profile
    let onSaved: (CindyProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var form: MovementsForm

    init(profile: Profile, onSaved: @escaping (CindyProfile) -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _form = State(initialValue: MovementsForm(current: profile.movements, smartSquats: profile.smartSquats))
    }

    var body: some View {
        Form {
            Section { Text(MovementsForm.subtitle).font(.footnote).foregroundStyle(.secondary) }
            group("PULL", PullVariant.allCases, MovementsForm.pullOptions, form.pull) { form.pull = $0 }
            group("PUSH", PushVariant.allCases, MovementsForm.pushOptions, form.push) { form.push = $0 }
            group("SQUAT", SquatVariant.allCases, MovementsForm.squatOptions, form.squat) { form.squat = $0 }
            Section {
                Toggle(MovementsForm.spotTitle, isOn: $form.smart)
                    .accessibilityLabel(form.spotSpoken)
            } footer: {
                Text(MovementsForm.spotNote)
            }
        }
        .saveCancel(MovementsForm.title) {
            onSaved(form.save(to: profile))
            dismiss()
        }
    }

    private func group<T: Equatable>(_ title: String, _ all: [T], _ options: [MovementsForm.Option], _ selected: T,
                                     choose: @escaping (T) -> Void) -> some View {
        Section(title) {
            ForEach(Array(all.enumerated()), id: \.offset) { i, value in
                Button { choose(value) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(options[i].label)
                            if let note = options[i].note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Image(systemName: "checkmark").opacity(value == selected ? 1 : 0).accessibilityHidden(true)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityLabel(options[i].spoken)
                .accessibilityAddTraits(value == selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

// MARK: - the name

struct NameSheet: View {
    let profile: Profile
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    init(profile: Profile, onSaved: @escaping () -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _text = State(initialValue: profile.displayName ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField(NameForm.hint, text: $text)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 22, weight: .semibold))
                    .focused($focused)
                    .onChange(of: text) { _, new in
                        let limited = NameForm.limited(new)
                        if limited != new { text = limited }
                    }
            } footer: {
                Text(NameForm.subtitle)
            }
        }
        .saveCancel(NameForm.title) {
            NameForm.save(text, to: profile)
            onSaved()
            dismiss()
        }
        .onAppear { focused = true }
    }
}
