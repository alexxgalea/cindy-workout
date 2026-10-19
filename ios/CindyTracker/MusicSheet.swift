import SwiftUI
import UniformTypeIdentifiers
import CindyCore

/// Everything music: what is chosen, whether it plays, and how to change either.
///
/// A sheet rather than a straight jump to the picker, because there are two settings, and the
/// second, off for now while keeping the track, would otherwise have nowhere to be. Changes take
/// effect as they are made, as on Android: there is nothing to save.
struct MusicSheet: View {
    let profile: Profile
    /// Said on the menu once a track has been taken.
    let show: (String) -> Void
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: String?
    @State private var name: String?
    @State private var on: Bool
    @State private var volume: Float
    @State private var picking = false
    /// The preview player, which is not the one the workout uses: that one belongs to the camera
    /// screen, and two players on one file would both hold it open. It lives while this sheet does.
    @State private var audition = MusicPlayer()

    init(profile: Profile, show: @escaping (String) -> Void, onChanged: @escaping () -> Void) {
        self.profile = profile
        self.show = show
        self.onChanged = onChanged
        let track = profile.musicTrack
        _chosen = State(initialValue: track)
        _name = State(initialValue: track.flatMap(MusicLibrary.displayName))
        _on = State(initialValue: profile.musicOn)
        _volume = State(initialValue: profile.musicVolume)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(MusicFlow.trackLine(chosen: chosen, name: name))
                        .font(.headline)
                        .accessibilityIdentifier("musicTrack")
                } footer: {
                    Text(MusicFlow.sheetSubtitle)
                }

                if chosen != nil {
                    Section {
                        Toggle(MusicFlow.playLabel, isOn: $on)
                            .onChange(of: on) { _, value in
                                profile.musicOn = value
                                onChanged()
                            }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(MusicFlow.volumeLabel).font(.subheadline)
                            // Heard only once the grip is let go, so a drag is not a series of seeks
                            // back to the first bar.
                            Slider(value: Binding(get: { Double(volume) }, set: {
                                volume = Float($0)
                                profile.musicVolume = volume
                                audition.volume = volume
                            }), in: 0...1) { editing in
                                if !editing { listen() }
                            }
                            .accessibilityLabel(MusicFlow.volumeLabel)
                            .accessibilityValue(MenuBuilder.percent(volume))
                        }
                    }
                }

                Section {
                    Button(MusicFlow.primaryLabel(chosen: chosen)) { picking = true }
                        .accessibilityIdentifier("musicChoose")
                    if chosen != nil {
                        Button(MusicFlow.secondaryLabel(chosen: chosen)) { listen() }
                    }
                } footer: {
                    Text(MusicFlow.sheetNote)
                }
            }
            .navigationTitle(MusicFlow.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { adopt(url) }
        }
        .onDisappear {
            audition.release()
            onChanged()
        }
    }

    /// Takes the long-lived grant that lets the track survive a restart, then remembers it. The
    /// track is not loaded here: the workout picks it up when the menu closes, and clears the choice
    /// itself if it turns out not to play.
    private func adopt(_ url: URL) {
        guard let stored = MusicLibrary.store(url) else {
            show(MusicFlow.lapsedText)
            return
        }
        audition.release()
        profile.musicTrack = stored
        profile.musicOn = true
        chosen = stored
        on = true
        name = MusicLibrary.displayName(stored)
        show(MusicFlow.adoptedText(name: name))
        onChanged()
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
