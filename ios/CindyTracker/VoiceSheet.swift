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

/// The voice sheet: whether it counts, how loud, and in which language. The language list is one row
/// each, saying where that language stands on this phone, with a button to hear it and a tap to
/// choose it. What each row says and what a tap does is `LanguageGroupModel`'s, which the Kotlin
/// `LanguageGroup` decided in the same way; what is kept, and when, is `VoiceForm`'s.
struct VoiceSheet: View {

    @StateObject private var sheet: LanguageSheetModel
    @Environment(\.dismiss) private var dismiss
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
        NavigationStack {
            List {
                Section {
                    Toggle(VoiceForm.toggleTitle, isOn: $form.on)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Volume").font(.subheadline)
                        // Spoken only once the grip is let go: restarting the utterance on every
                        // pixel of the drag would stutter rather than demonstrate.
                        Slider(value: Binding(get: { Double(form.volume) }, set: {
                            form.volume = Float($0)
                            speaker.volume = form.volume
                        }), in: 0...1) { editing in
                            if !editing { speaker.preview(.volumeCheck) }
                        }
                        .accessibilityLabel("Volume")
                        .accessibilityValue(MenuBuilder.percent(form.volume))
                    }
                } header: {
                    Text(VoiceForm.title.uppercased())
                } footer: {
                    Text(VoiceForm.subtitle + " " + VoiceForm.note)
                }

                Section {
                    ForEach(sheet.rows, id: \.tag) { row in
                        HStack(spacing: 0) {
                            Button { sheet.choose(row.tag) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.nativeName).font(.headline)
                                        Text(row.caption).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .opacity(row.chosen ? 1 : 0)
                                        .accessibilityHidden(true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(row.description)
                            .accessibilityAddTraits(.isButton)

                            Button { sheet.preview(row.tag) } label: {
                                Image(systemName: "play.circle")
                                    .font(.title2)
                                    .frame(width: 48, height: 48)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(row.previewDescription)
                        }
                        .opacity(row.dimmed ? 0.45 : 1)
                    }
                } header: {
                    Text("LANGUAGE")
                } footer: {
                    Text("Counting uses a voice stored on the phone, so it works offline. "
                        + "A language that isn't ready is counted in English until it is.")
                }

                Section {
                    Button { sheet.model.manageVoices() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manage voices").font(.headline)
                            Text("Add or remove voices in Settings").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        saved = true
                        form.language = sheet.chosen
                        save(form)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("HEAR IT") { sheet.previewChosen() }
                }
            }
            .overlay(alignment: .bottom) {
                if let text = sheet.toast {
                    Text(text)
                        .font(.footnote)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 56)
                        .transition(.opacity)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .alert("Manage voices", isPresented: $sheet.explainingVoices) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("iOS can't be asked to download a voice for the app. Most languages ship a compact voice. "
                    + "For a better one, go to Settings → Accessibility → Spoken Content → Voices, download it there, "
                    + "and it appears here the next time this list refreshes.")
            }
        }
        .onAppear { sheet.start() }
        .onDisappear {
            sheet.stop()
            if !saved { cancel() }
        }
    }
}
