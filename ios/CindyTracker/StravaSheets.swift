import SwiftUI
import CindyCore

/// The sheet that comes before Strava's own page, from every road that starts OAuth: the menu row,
/// the results row's "Connect to upload", and its "Reconnect to upload". `StravaConsent` holds the
/// words; nothing is minted, stored or opened until Strava's own button is tapped, and NOT NOW, like
/// a swipe down, leaves having started nothing.
struct StravaConsentSheet: View {
    let origin: StravaOrigin
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(StravaConsent.title)
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.label)
                    .accessibilityAddTraits(.isHeader)
                Text(StravaConsent.subtitle).font(.system(size: 15)).foregroundStyle(Palette.labelBody)

                Text(StravaConsent.eyebrow)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.labelSecondary)
                    .padding(.top, 6)
                Text(StravaConsent.sends).font(.system(size: 15)).foregroundStyle(Palette.label)
                Text(StravaConsent.never).font(.system(size: 13)).foregroundStyle(Palette.labelSecondary)
                Text(StravaConsent.dataPermissions).font(.system(size: 13)).foregroundStyle(Palette.labelSecondary)

                // Strava's own button, as Strava supplies it; Strava's guidelines have apps start OAuth from it.
                Button(action: connect) {
                    Image("StravaConnect").resizable().scaledToFit().frame(width: 237, height: 48)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .accessibilityLabel(StravaConsent.connectLabel)
                .accessibilityAddTraits(.isButton)

                // The one filled button is the safe one, the way KEEP THEM is on the delete-all sheet.
                Button(StravaConsent.notNowLabel) { dismiss() }
                    .buttonStyle(CindyPrimaryButtonStyle())
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private func connect() {
        dismiss()
        let origin = self.origin
        // Strava's page opens over the app, which cannot happen while this sheet is still leaving.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            StravaCenter.shared.connect(origin)
        }
    }
}

/// What a connected athlete sees: the switch that makes "uploads on its own" true or not, the note
/// about heart rate, the mark that names the integration, DONE and DISCONNECT.
struct StravaConnectedSheet: View {
    /// Said on the menu once it is done.
    let show: (String) -> Void
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var center = StravaCenter.shared
    @State private var autoUpload: Bool

    init(show: @escaping (String) -> Void, onChanged: @escaping () -> Void) {
        self.show = show
        self.onChanged = onChanged
        _autoUpload = State(initialValue: StravaCenter.shared.tokens.autoUpload)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(StravaSheet.toggleLabel, isOn: $autoUpload)
                } header: {
                    Text(StravaSheet.title.uppercased())
                } footer: {
                    // The switch is what makes the line true, so the two are read together.
                    Text(StravaSheet.subtitle(athleteName: center.tokens.grant?.athleteName, autoUpload: autoUpload))
                }
                Section {
                    Text(StravaSheet.note).font(.system(size: 13)).foregroundStyle(Palette.labelSecondary)
                    Image("CompatibleWithStrava")
                        .resizable().scaledToFit()
                        .frame(width: 200, height: 17, alignment: .leading)
                        .accessibilityLabel(StravaSheet.compatibleLabel)
                }
                Section {
                    Button(StravaSheet.disconnectLabel, role: .destructive) {
                        center.disconnect()
                        show(StravaDisconnect.toast)
                        onChanged()
                        dismiss()
                    }
                    .accessibilityIdentifier("stravaDisconnect")
                }
            }
            .navigationTitle(StravaSheet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(StravaSheet.doneLabel.capitalized) {
                        center.tokens.autoUpload = autoUpload
                        onChanged()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
