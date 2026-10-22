import SwiftUI
import CindyCore

/// Everything music (`chooseMusic`): what is chosen, whether it plays, and how to change either.
///
/// A sheet rather than a straight jump to the picker, because there are two settings, and the
/// second, off for now while keeping the track, would otherwise have nowhere to be. Changes take
/// effect as they are made, as on Android: there is nothing to save. CHOOSE A TRACK closes the sheet
/// and asks the screen that opened it for the system's file picker, which outlives the sheet.
struct MusicSheet: View {
    let profile: Profile
    /// Opens the file picker, on the screen that holds it.
    let choose: () -> Void
    /// Said on the screen once a track has been heard to have lapsed.
    let show: (String) -> Void
    let onChanged: () -> Void
    @State private var on: Bool
    @State private var volume: Float
    /// The preview player, which is not the one the workout uses: that one belongs to the camera
    /// screen, and two players on one file would both hold it open. It lives while this sheet does.
    @State private var audition = MusicPlayer()
    private let chosen: String?
    private let name: String?

    init(profile: Profile, choose: @escaping () -> Void, show: @escaping (String) -> Void,
         onChanged: @escaping () -> Void) {
        self.profile = profile
        self.choose = choose
        self.show = show
        self.onChanged = onChanged
        let track = profile.musicTrack
        chosen = track
        name = track.flatMap(MusicLibrary.displayName)
        _on = State(initialValue: profile.musicOn)
        _volume = State(initialValue: profile.musicVolume)
    }

    var body: some View {
        CindyPanel(title: MusicFlow.sheetTitle, subtitle: MusicFlow.sheetSubtitle,
                   primary: SheetButton(title: MusicFlow.primaryLabel(chosen: chosen)) { choose() },
                   secondary: SheetButton(title: MusicFlow.secondaryLabel(chosen: chosen)) {
                       if chosen != nil { listen() }
                   },
                   // LISTEN is heard against the controls that stay on screen; CANCEL leaves.
                   secondaryDismisses: chosen == nil) {
            VStack(alignment: .leading, spacing: 0) {
                Text(MusicFlow.trackLine(chosen: chosen, name: name))
                    .cindy(.headline)
                    .accessibilityIdentifier("musicTrack")
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                if chosen != nil {
                    SheetToggle(MusicFlow.playLabel, isOn: $on)
                        .onChange(of: on) { _, value in
                            profile.musicOn = value
                            onChanged()
                        }
                    // Heard only once the grip is let go, so a drag is not a series of seeks back to
                    // the first bar.
                    SheetSlider(MusicFlow.volumeLabel,
                                value: Binding(get: { Double(volume) }, set: {
                                    volume = Float($0)
                                    profile.musicVolume = volume
                                    audition.volume = volume
                                }),
                                onSettled: { _ in listen() })
                }
                SheetNote(MusicFlow.sheetNote)
            }
        }
        .onDisappear {
            audition.release()
            onChanged()
        }
    }

    /// Plays the chosen track at the volume set, so the mix can be heard being set.
    private func listen() {
        guard let chosen else { return }
        audition.volume = volume
        if audition.track != chosen, !audition.load(chosen) {
            show(MusicFlow.lapsedText)
            return
        }
        audition.play()
    }
}
