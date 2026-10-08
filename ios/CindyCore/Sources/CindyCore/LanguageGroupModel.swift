import Foundation

/// What a screen needs from a clock that can run work later: `schedule(afterMs, work)` runs `work`
/// on the main thread after `afterMs`, and returns a function that cancels it.
public typealias Scheduler = (Int64, @escaping () -> Void) -> () -> Void

extension PackStates {
    /// These states with `tag` now `state`, in the same order.
    public func replacing(_ tag: String, with state: PackState) -> PackStates {
        PackStates(entries: entries.map { $0.tag == tag ? (tag, state) : $0 })
    }
}

/// The voice sheet's list of languages, as a model: one row each, saying where that language stands
/// on this phone, with a way to hear it and a way to choose it. Port of `LanguageGroup.kt`, whose
/// views are the sheet in `CindyTracker`; everything it decides is here, so it is tested against a
/// real `Speaker` on a fake engine without a screen.
///
/// Each row is two separate targets rather than one (the row chooses, the play button previews)
/// so VoiceOver gets two stops it can name, and a thumb aiming for one cannot hit the other.
///
/// What the athlete sees is only ever what the phone can do. A language the phone can speak says
/// "Ready". One that needs its voice fetched says so and fetches it on the tap that chooses it,
/// and then says "Downloading…", and says something different if that goes on for two minutes,
/// because an engine reports no progress and a download waiting on Wi-Fi looks like a slow one;
/// tapping the row then asks again. One the engine does not speak cannot be chosen, and says why.
/// Choosing a language that is not ready yet is allowed, and the workout says it is counting in
/// English until it is.
///
/// The fetch belongs to the phone and the choice to the profile: a voice is asked for by the tap,
/// whether or not SAVE follows, so that it can be arriving while the sheet is still open.
///
/// A tap is answered from what the phone last said. One made before the engine has said anything
/// cannot be, so it is settled when the engine does: the voice is asked for if it turns out to
/// need one, and the tap is undone, with the reason, if the phone turns out not to speak the
/// language at all.
///
/// While the sheet is open the states are read again every couple of seconds. That is the only way
/// a download finishing while the athlete watches, or in the system's own settings, shows up.
public final class LanguageGroupModel {

    /// One row as it is drawn.
    public struct Row: Equatable, Sendable {
        public let tag: String
        public let nativeName: String
        public let englishName: String
        /// The line beneath the name: how the language stands.
        public let caption: String
        /// What VoiceOver reads for the row.
        public let description: String
        /// What VoiceOver reads for its play button.
        public let previewDescription: String
        public let chosen: Bool
        /// A language that cannot be chosen: plainly off, still plainly there.
        public let dimmed: Bool
    }

    /// Until the engine first answers. Short, since it usually does within a second.
    public static let firstPollMs: Int64 = 400

    /// After that. Often enough to see a download arrive, rarely enough not to matter.
    public static let pollMs: Int64 = 2_000

    private let speaker: Speaker
    private let toast: (String) -> Void
    private let openEngineScreen: () -> Void
    private let elapsedMs: () -> Int64
    private let schedule: Scheduler

    /// The tag of the language ticked. Saved by the sheet's SAVE, not by choosing it.
    public private(set) var chosen: String

    /// The last language chosen with the phone's answer about it in hand, or the one the sheet
    /// opened on: where an unsettled choice goes back to if the phone cannot speak it.
    private var settled: String

    /// The language tapped last, if that was before the engine had answered anything.
    private var unsettled: VoicePack?

    /// What the engine last said about each language, or nil until it first has.
    private var states: PackStates?

    private let openedAt: Int64
    private var running = false
    private var cancelPoll: (() -> Void)?

    /// The rows, in the picker's order. Redrawn through `onChange`.
    public private(set) var rows: [Row] = []

    /// Called on the main thread whenever `rows` or `chosen` have changed.
    public var onChange: (() -> Void)?

    public init(speaker: Speaker, initial: String, toast: @escaping (String) -> Void,
                openEngineScreen: @escaping () -> Void,
                elapsedMs: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1000) },
                schedule: @escaping Scheduler) {
        self.speaker = speaker
        self.toast = toast
        self.openEngineScreen = openEngineScreen
        self.elapsedMs = elapsedMs
        self.schedule = schedule
        chosen = VoicePacks.of(initial).tag
        settled = chosen
        openedAt = elapsedMs()
        render()
    }

    /// The row for `tag`.
    public func row(_ tag: String) -> Row? { rows.first { $0.tag == tag } }

    // MARK: choosing

    /// A tap on the row for `tag`.
    public func choose(_ tag: String) {
        let pack = VoicePacks.of(tag)
        let state = states?[pack.tag]
        if !VoiceLanguageText.selectable(state) {
            toast(VoiceLanguageText.unsupportedNotice(pack))
            return
        }
        chosen = pack.tag
        // The volume check and the sample are spoken in whatever is ticked, as far as the phone can.
        speaker.language = pack.tag
        if states == nil {
            unsettled = pack
        } else {
            unsettled = nil
            settled = pack.tag
        }
        render()
        if VoiceLanguageText.asksForDownload(state, downloadingMs: speaker.downloadingFor(pack.tag)) {
            download(pack)
        }
    }

    /// Deals with a choice made before the engine answered, now that it has: as if the tap had
    /// come a moment later. Nothing to do for a language that is ready, or already on its way.
    private func settle() {
        guard let pack = unsettled else { return }
        unsettled = nil
        let state = states?[pack.tag]
        if !VoiceLanguageText.selectable(state) {
            chosen = settled
            speaker.language = settled
            toast(VoiceLanguageText.unsupportedNotice(pack))
            return
        }
        settled = pack.tag
        if VoiceLanguageText.asksForDownload(state, downloadingMs: speaker.downloadingFor(pack.tag)) {
            download(pack)
        }
    }

    private func download(_ pack: VoicePack) {
        switch speaker.download(pack) {
        case .asked:
            toast("Downloading the \(pack.englishName) voice")
            // The engine will not say so for a while, and the row need not wait for it to.
            states = states?.replacing(pack.tag, with: .downloading)
            render()
        case .useEngineScreen:
            toast("Opening the voice engine to fetch \(pack.englishName)")
            openEngineScreen()
        case .notOffered:
            toast("This phone's voice engine doesn't offer \(pack.englishName)")
        }
    }

    /// The row that opens the engine's own screen for fetching or removing voice data.
    public func manageVoices() { openEngineScreen() }

    // MARK: hearing

    /// A tap on the play button of the row for `tag`.
    public func preview(_ tag: String) {
        let pack = VoicePacks.of(tag)
        guard let known = states else {
            toast(VoiceLanguageText.engineSilent(waitedMs: waited()))
            return
        }
        let state = known[pack.tag]
        if !VoiceLanguageText.selectable(state) {
            toast(VoiceLanguageText.unsupportedNotice(pack))
            return
        }
        let started = speaker.previewPack(pack) { [toast] failure in
            toast(VoiceLanguageText.previewFailure(failure, pack))
        }
        // Said once it is playing, not before: a preview that never starts has nothing to label.
        if started, let note = VoiceLanguageText.previewNote(state) { toast(note) }
    }

    /// Plays the sample of the ticked language: what the sheet's HEAR IT does.
    public func previewChosen() { preview(chosen) }

    // MARK: keeping up with the phone

    /// Starts reading the states, now and then every couple of seconds.
    public func start() {
        if running { return }
        running = true
        poll()
    }

    /// Stops. The sheet dismissed, or the screen no longer showing it.
    public func stop() {
        running = false
        cancelPoll?()
        cancelPoll = nil
    }

    private func poll() {
        if !running { return }
        speaker.packStates { [weak self] result in
            guard let self else { return }
            states = result
            if running {
                settle()
                render()
            }
        }
        // Quickly until the engine first answers, then at a pace a download can be watched at.
        cancelPoll?()
        cancelPoll = schedule(waitingForEngine ? Self.firstPollMs : Self.pollMs) { [weak self] in self?.poll() }
        // With no answer coming back to redraw the rows, time passing is what changes them:
        // "Checking…" turning into "isn't answering" by itself.
        if states == nil { render() }
    }

    private func waited() -> Int64 { elapsedMs() - openedAt }

    /// True while the engine may yet answer soon. After that it is asked at the ordinary pace.
    private var waitingForEngine: Bool { states == nil && waited() < VoiceLanguageText.noAnswerAfterMs }

    private func render() {
        let waited = waited()
        rows = VoicePacks.all.map { pack in
            let state = states?[pack.tag]
            let caption = VoiceLanguageText.caption(state, downloadingMs: speaker.downloadingFor(pack.tag), waitedMs: waited)
            let isChosen = pack.tag == chosen
            return Row(tag: pack.tag, nativeName: pack.nativeName, englishName: pack.englishName,
                       caption: caption,
                       description: VoiceLanguageText.description(pack, caption, chosen: isChosen),
                       previewDescription: VoiceLanguageText.previewDescription(pack, state),
                       chosen: isChosen, dimmed: !VoiceLanguageText.selectable(state))
        }
        onChange?()
    }
}
