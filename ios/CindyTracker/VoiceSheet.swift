import SwiftUI
import CindyCore

/// Holds the language list's model for SwiftUI: the model decides, this republishes.
@MainActor
final class LanguageSheetModel: ObservableObject {

    @Published private(set) var rows: [LanguageGroupModel.Row] = []
    @Published private(set) var toast: String?
    @Published var explainingVoices = false

    private(set) var model: LanguageGroupModel!
    private var toastClear: DispatchWorkItem?

    init(speaker: Speaker, initial: String) {
        model = LanguageGroupModel(
            speaker: speaker,
            initial: initial,
            toast: { [weak self] text in Task { @MainActor in self?.show(text) } },
            openEngineScreen: { [weak self] in Task { @MainActor in self?.explainingVoices = true } },
            schedule: { ms, work in
                let item = DispatchWorkItem(block: work)
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(ms)), execute: item)
                return { item.cancel() }
            })
        rows = model.rows
        model.onChange = { [weak self] in self?.rows = self?.model.rows ?? [] }
    }

    var chosen: String { model.chosen }

    func choose(_ tag: String) { model.choose(tag); objectWillChange.send() }
    func preview(_ tag: String) { model.preview(tag) }
    func previewChosen() { model.previewChosen() }
    func start() { model.start() }
    func stop() { model.stop() }

    private func show(_ text: String) {
        toast = text
        toastClear?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastClear = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
    }
}

/// The voice sheet (`chooseVoice`): whether it counts, how loud, and in which language. The language
/// list is one row each, saying where that language stands on this phone, with a button to hear it
/// and a tap to choose it. What each row says and what a tap does is `LanguageGroupModel`'s, which the
/// Kotlin `LanguageGroup` decided in the same way; what is kept, and when, is `VoiceForm`'s.
///
/// SAVE keeps it all. Closing any other way, CANCEL's way, puts the speaker back as it was.
struct VoiceSheet: View {

    @StateObject private var sheet: LanguageSheetModel
    private let speaker: Speaker
    private let save: (VoiceForm) -> Void
    private let cancel: () -> Void
    @State private var form: VoiceForm
    /// Saving puts the form on the profile; leaving any other way puts the speaker back.
    @State private var saved = false

    init(speaker: Speaker, profile: Profile, save: @escaping (VoiceForm) -> Void, cancel: @escaping () -> Void) {
        let form = VoiceForm(profile)
        _form = State(initialValue: form)
        _sheet = StateObject(wrappedValue: LanguageSheetModel(speaker: speaker, initial: form.language))
        self.speaker = speaker
        self.save = save
        self.cancel = cancel
        speaker.volume = form.volume
    }

    var body: some View {
        // One container, so swapping the panels is not this sheet appearing or leaving.
        ZStack {
            if sheet.explainingVoices { manageVoices } else { voice }
        }
        .onChange(of: sheet.explainingVoices) { _, _ in SheetVoiceOver.panelChanged() }
        .onAppear { sheet.start() }
        .onDisappear {
            sheet.stop()
            if !saved { cancel() }
        }
    }

    private var voice: some View {
        CindyPanel(title: VoiceForm.title, subtitle: VoiceForm.subtitle,
                   primary: SheetButton(title: SheetWords.save) {
                       saved = true
                       form.language = sheet.chosen
                       save(form)
                   },
                   // The sample is heard against the sliders that are still on screen.
                   secondary: SheetButton(title: SheetWords.hearIt) { sheet.previewChosen() },
                   secondaryDismisses: false) {
            VStack(alignment: .leading, spacing: 0) {
                SheetToggle(VoiceForm.toggleTitle, isOn: $form.on)
                // Spoken only once the grip is let go: restarting the utterance on every pixel of
                // the drag would stutter rather than demonstrate.
                SheetSlider(SheetWords.volume,
                            value: Binding(get: { Double(form.volume) }, set: {
                                form.volume = Float($0)
                                speaker.volume = form.volume
                            }),
                            onSettled: { _ in speaker.preview(.volumeCheck) })
                SheetNote(VoiceForm.note)
                languages
            }
        }
        .overlay(alignment: .top) {
            if let text = sheet.toast {
                CindyToast(text: text).offset(y: -64).accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    /// One entry of the language list: a language, or the way to the engine's own voices.
    private enum Entry: Identifiable {
        case language(LanguageGroupModel.Row), manage

        var id: String {
            switch self {
            case .language(let row): return row.tag
            case .manage: return "manage"
            }
        }
    }

    private var languages: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(SheetWords.language).cindy(.eyebrow)
                .padding(.leading, 4).padding(.top, 18).padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            InsetGroup(sheet.rows.map(Entry.language) + [.manage], id: \.id) { entry in
                switch entry {
                case .language(let row): languageRow(row)
                case .manage:
                    NavRow(title: "Manage voices", value: "Add or remove voices in Settings") { sheet.model.manageVoices() }
                }
            }
            SheetNote("Counting uses a voice stored on the phone, so it works offline. "
                + "A language that isn't ready is counted in English until it is.")
        }
    }

    /// Two targets, so a screen reader gets two stops it can name and a thumb aiming for one cannot
    /// hit the other: the row chooses, the play button previews.
    private func languageRow(_ row: LanguageGroupModel.Row) -> some View {
        HStack(spacing: 0) {
            Button { sheet.choose(row.tag) } label: {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.nativeName).cindy(.headline)
                        Text(row.caption).cindy(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(CindyIcon.check)
                        .resizable()
                        .frame(width: 19, height: 19)
                        .foregroundStyle(Palette.label)
                        .opacity(row.chosen ? 1 : 0)
                        .padding(.leading, 12)
                        .accessibilityHidden(true)
                }
                .padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.description)
            .accessibilityAddTraits(.isButton)

            Button { sheet.preview(row.tag) } label: {
                Image(CindyIcon.play)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Palette.labelSecondary)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .accessibilityLabel(row.previewDescription)
        }
        .frame(minHeight: 56)
        .opacity(row.dimmed ? 0.45 : 1)
    }

    /// iOS cannot be asked to fetch a voice, so the way to them is said, with Settings to open.
    private var manageVoices: some View {
        CindyPanel(title: "Manage voices",
                   subtitle: "iOS can't be asked to download a voice for the app. Most languages ship a compact voice. "
                       + "For a better one, go to Settings → Accessibility → Spoken Content → Voices, download it there, "
                       + "and it appears here the next time this list refreshes.",
                   primary: SheetButton(title: SheetWords.openSettings) {
                       if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                       sheet.explainingVoices = false
                   }.keepingOpen { true },
                   secondary: SheetButton(title: SheetWords.notNow) { sheet.explainingVoices = false }
                       .keepingOpen { true })
    }
}
