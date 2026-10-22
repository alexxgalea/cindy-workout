import SwiftUI
import CindyCore

// The sheets that change what the athlete has told the app, as Cindy sheets: `Dialogs.kt`'s
// `chooseMovements`, `askBodyWeight` and `askHeartRateDetails`, and `AccountActivity.kt`'s `askName`
// and `choosePhoto`. What each asks, refuses and keeps is decided in CindyCore (`ProfileForms.swift`);
// these are the fields and lists. Each is a view whose body is one panel, presented by whichever
// screen opens it.

/// Brings the keyboard up with a sheet: the athlete opened it to type.
private extension View {
    func focusingOnAppear(_ focused: FocusState<Bool>.Binding) -> some View {
        onAppear { DispatchQueue.main.async { focused.wrappedValue = true } }
    }
}

/// What a refused entry says, under the field, in the colour for something that did not work.
private struct Refusal: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message).cindy(.footnote, colour: Palette.stateAlert)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }
}

// MARK: - body weight

struct BodyWeightSheet: View {
    let profile: Profile
    let onSaved: () -> Void
    @State private var text: String
    @State private var problem: String?
    @FocusState private var focused: Bool

    init(profile: Profile, onSaved: @escaping () -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _text = State(initialValue: BodyWeightForm.initialText(profile))
    }

    var body: some View {
        CindyPanel(title: BodyWeightForm.title, subtitle: BodyWeightForm.subtitle,
                   primary: SheetButton(title: SheetWords.save) { save() }.keepingOpen { problem != nil },
                   secondary: SheetButton(title: SheetWords.cancel) {}) {
            VStack(alignment: .leading, spacing: 0) {
                SheetField(BodyWeightForm.hint, text: $text, keyboard: .decimalPad, focused: $focused)
                Refusal(message: problem)
            }
        }
        .focusingOnAppear($focused)
    }

    /// A refusal keeps the sheet up with what was typed, where Android closes it and loses it.
    private func save() {
        switch BodyWeightForm.save(text, to: profile) {
        case .saved:
            problem = nil
            onSaved()
        case .refused(let message):
            problem = message
            SheetVoiceOver.announce(message)
        }
    }
}

// MARK: - heart-rate details

struct HeartRateDetailsSheet: View {
    let profile: Profile
    let onSaved: () -> Void
    /// Set when this panel is one step of a longer sheet: called in place of closing it.
    let onFinished: (() -> Void)?
    @State private var year: String
    @State private var sex: Sex?
    @State private var problem: String?
    @FocusState private var focused: Bool

    init(profile: Profile, onSaved: @escaping () -> Void, onFinished: (() -> Void)? = nil) {
        self.profile = profile
        self.onSaved = onSaved
        self.onFinished = onFinished
        _year = State(initialValue: HeartRateDetailsForm.initialYear(profile))
        _sex = State(initialValue: profile.sex)
    }

    var body: some View {
        CindyPanel(title: HeartRateDetailsForm.title, subtitle: HeartRateDetailsForm.subtitle,
                   primary: SheetButton(title: SheetWords.save) { save() }
                       .keepingOpen { problem != nil || onFinished != nil },
                   secondary: SheetButton(title: SheetWords.cancel) { onFinished?() }
                       .keepingOpen { onFinished != nil }) {
            VStack(alignment: .leading, spacing: 0) {
                SheetField(HeartRateDetailsForm.hint, text: $year, keyboard: .numberPad, focused: $focused)
                Refusal(message: problem)
                SheetChoiceGroup(HeartRateDetailsForm.sexTitle, options: Sex.allCases, selected: $sex,
                                 label: { $0.label }, note: { HeartRateDetailsForm.note(for: $0) })
            }
        }
        .focusingOnAppear($focused)
    }

    private func save() {
        let nowYear = Calendar.current.component(.year, from: Date())
        switch HeartRateDetailsForm.save(year: year, sex: sex, nowYear: nowYear, to: profile) {
        case .saved:
            problem = nil
            onSaved()
            onFinished?()
        case .refused(let message):
            problem = message
            SheetVoiceOver.announce(message)
        }
    }
}

// MARK: - movements

/// "Make Cindy yours": one choice per movement, taken before the clock starts.
struct MovementsSheet: View {
    let profile: Profile
    let onSaved: (CindyProfile) -> Void
    @State private var form: MovementsForm

    init(profile: Profile, onSaved: @escaping (CindyProfile) -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _form = State(initialValue: MovementsForm(current: profile.movements, smartSquats: profile.smartSquats))
    }

    var body: some View {
        CindyPanel(title: MovementsForm.title, subtitle: MovementsForm.subtitle,
                   primary: SheetButton(title: SheetWords.save) { onSaved(form.save(to: profile)) },
                   secondary: SheetButton(title: SheetWords.cancel) {}) {
            VStack(alignment: .leading, spacing: 0) {
                group("PULL", PullVariant.allCases, MovementsForm.pullOptions, $form.pull)
                group("PUSH", PushVariant.allCases, MovementsForm.pushOptions, $form.push)
                group("SQUAT", SquatVariant.allCases, MovementsForm.squatOptions, $form.squat)
                SheetToggle(MovementsForm.spotTitle, isOn: $form.smart)
                SheetNote(MovementsForm.spotNote)
            }
        }
    }

    private func group<T: Hashable>(_ title: String, _ all: [T], _ options: [MovementsForm.Option],
                                    _ selection: Binding<T>) -> some View {
        func option(_ value: T) -> MovementsForm.Option { options[all.firstIndex(of: value) ?? 0] }
        return SheetChoiceGroup(title, options: all, selection: selection,
                                label: { option($0).label }, note: { option($0).note },
                                spoken: { option($0).spokenNote })
    }
}

// MARK: - the name

struct NameSheet: View {
    let profile: Profile
    let onSaved: () -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(profile: Profile, onSaved: @escaping () -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _text = State(initialValue: profile.displayName ?? "")
    }

    var body: some View {
        CindyPanel(title: NameForm.title, subtitle: NameForm.subtitle,
                   primary: SheetButton(title: SheetWords.save) {
                       NameForm.save(text, to: profile)
                       onSaved()
                   },
                   secondary: SheetButton(title: SheetWords.cancel) {}) {
            SheetField(NameForm.hint, text: $text, style: .title2, focused: $focused)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .onChange(of: text) { _, new in
                    let limited = NameForm.limited(new)
                    if limited != new { text = limited }
                }
        }
        .focusingOnAppear($focused)
    }
}

// MARK: - the photo

/// "Your photo": choose one, and take it back where there is one. The picker itself is the system's.
struct PhotoChoiceSheet: View {
    let hasPhoto: Bool
    let choose: () -> Void
    let remove: () -> Void

    var body: some View {
        let actions = PhotoSheet.actions(hasPhoto: hasPhoto)
        let second = actions[1]
        CindyPanel(title: PhotoSheet.title, subtitle: PhotoSheet.subtitle,
                   primary: SheetButton(title: actions[0].title) { choose() },
                   secondary: SheetButton(title: second.title,
                                          tint: second.destructive ? Palette.stateAlert : Palette.label) {
                       if second.destructive { remove() }
                   })
    }
}
