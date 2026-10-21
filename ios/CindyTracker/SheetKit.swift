import SwiftUI
import UIKit

// The pieces the Cindy sheets share, from `Dialogs.kt` and `CindySheet.kt`: small print, a group of
// choices, and the glass field the body-weight, heart-rate and name sheets have in them.

/// Small print inside a sheet (`sheetNote`): a footnote, 8 above and 4 below.
struct SheetNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).cindy(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8).padding(.bottom, 4)
    }
}

/// One field's options as a grouped list rather than a column of radio buttons (`choiceGroup`).
///
/// An eyebrow over an `InsetGroup` of rows at least 52 high: the label in `.headline`, the note a
/// choice carries (which of the choices the camera cannot see, or which sex is the average of the
/// others) in `.footnote` under it, and a tick on the one chosen. A row is one element, spoken as
/// its label and its note, so the choice and its consequence arrive together. `selected` may be
/// nil: a sex that has never been chosen is how the heart-rate sheet opens.
struct SheetChoiceGroup<T: Hashable>: View {
    let title: String
    let options: [T]
    @Binding var selected: T?
    let label: (T) -> String
    let note: (T) -> String?
    let spoken: ((T) -> String?)?

    init(_ title: String, options: [T], selected: Binding<T?>, label: @escaping (T) -> String,
         note: @escaping (T) -> String?, spoken: ((T) -> String?)? = nil) {
        self.title = title
        self.options = options
        _selected = selected
        self.label = label
        self.note = note
        self.spoken = spoken
    }

    /// For a field that always has a choice, as every movement does.
    init(_ title: String, options: [T], selection: Binding<T>, label: @escaping (T) -> String,
         note: @escaping (T) -> String?, spoken: ((T) -> String?)? = nil) {
        self.init(title, options: options,
                  selected: Binding(get: { selection.wrappedValue }, set: { if let value = $0 { selection.wrappedValue = value } }),
                  label: label, note: note, spoken: spoken)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).cindy(.eyebrow)
                .padding(.leading, 4).padding(.top, 18).padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            InsetGroup(options, id: \.self) { option in row(option) }
        }
    }

    private func row(_ option: T) -> some View {
        let isSelected = selected == option
        let said = (spoken ?? note)(option)
        return Button { selected = option } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label(option)).cindy(.headline)
                    if let hint = note(option) { Text(hint).cindy(.footnote) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(CindyIcon.check)
                    .resizable()
                    .frame(width: 19, height: 19)
                    .foregroundStyle(Palette.label)
                    .opacity(isSelected ? 1 : 0)
                    .padding(.leading, 12)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 18).padding(.trailing, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(option) + (said.map { ", \($0)" } ?? ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The glass text field of `askBodyWeight`, `askHeartRateDetails` and `askName`: its text centred in
/// `style`, padding 20 and 16, the hint in the faintest label colour. The caller brings the focus,
/// because the athlete opened the sheet to type and the keyboard comes up with it.
struct SheetField: View {
    let hint: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    let style: CindyType
    let focused: FocusState<Bool>.Binding

    init(_ hint: String, text: Binding<String>, keyboard: UIKeyboardType = .default,
         style: CindyType = .metricM, focused: FocusState<Bool>.Binding) {
        self.hint = hint
        _text = text
        self.keyboard = keyboard
        self.style = style
        self.focused = focused
    }

    var body: some View {
        TextField("", text: $text, prompt: Text(hint).foregroundStyle(Palette.labelQuaternary))
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .cindy(style, colour: Palette.label)
            .focused(focused)
            .padding(.horizontal, 20).padding(.vertical, 16)
            .glassCard()
            .accessibilityIdentifier("sheetField")
    }
}

/// What a screen reader would otherwise miss on a sheet: that a save was refused, where Android's toast
/// is read out, and that the sheet now shows something else, where the element it was on has gone.
enum SheetVoiceOver {
    static func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    static func panelChanged() {
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }
}
