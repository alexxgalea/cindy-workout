import SwiftUI
import CindyCore

/// The sheet that comes before Strava's own page (`StravaConsent.show`), from every road that starts
/// OAuth: the menu row, the results row's "Connect to upload", and its "Reconnect to upload".
/// `StravaConsent` holds the words; nothing is minted, stored or opened until Strava's own button is
/// tapped, and NOT NOW, like the dim or a swipe down, leaves having started nothing.
struct StravaConsentSheet: View {
    let origin: StravaOrigin
    @Environment(\.closeCindySheet) private var close

    var body: some View {
        CindyPanel(title: StravaConsent.title, subtitle: StravaConsent.subtitle,
                   // The one filled button is the safe one, the way KEEP IT is on the discard sheet.
                   primary: SheetButton(title: StravaConsent.notNowLabel) {}) {
            VStack(alignment: .leading, spacing: 0) {
                Text(StravaConsent.eyebrow).cindy(.eyebrow)
                    .padding(.top, 14).padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                Text(StravaConsent.sends).cindy(.callout)
                SheetNote(StravaConsent.never)
                SheetNote(StravaConsent.dataPermissions)

                // Strava's own button, as Strava supplies it; Strava's guidelines have apps start OAuth from it.
                Button(action: connect) {
                    Image("StravaConnect").resizable().scaledToFit().frame(width: 237, height: 48)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .accessibilityLabel(StravaConsent.connectLabel)
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func connect() {
        close()
        let origin = self.origin
        // Strava's page opens over the app, which cannot happen while this sheet is still leaving.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            StravaCenter.shared.connect(origin)
        }
    }
}

/// What a connected athlete sees (`openStravaSheet`): the switch that makes "uploads on its own" true
/// or not, the note about heart rate, the mark that names the integration, DONE and DISCONNECT.
struct StravaConnectedSheet: View {
    /// Said on the menu once it is done.
    let show: (String) -> Void
    let onChanged: () -> Void
    @ObservedObject private var center = StravaCenter.shared
    @State private var autoUpload: Bool

    init(show: @escaping (String) -> Void, onChanged: @escaping () -> Void) {
        self.show = show
        self.onChanged = onChanged
        _autoUpload = State(initialValue: StravaCenter.shared.tokens.autoUpload)
    }

    var body: some View {
        CindyPanel(
            title: StravaSheet.title,
            // The switch is what makes the line true, so the two are read together.
            subtitle: StravaSheet.subtitle(athleteName: center.tokens.grant?.athleteName, autoUpload: autoUpload),
            primary: SheetButton(title: StravaSheet.doneLabel) {
                center.tokens.autoUpload = autoUpload
                onChanged()
            },
            secondary: SheetButton(title: StravaSheet.disconnectLabel, tint: Palette.stateAlert) {
                center.disconnect()
                show(StravaDisconnect.toast)
                onChanged()
            }) {
            VStack(alignment: .leading, spacing: 0) {
                SheetToggle(StravaSheet.toggleLabel, isOn: $autoUpload)
                SheetNote(StravaSheet.note)
                Image("CompatibleWithStrava")
                    .resizable().scaledToFit()
                    .frame(width: 200, height: 17, alignment: .leading)
                    .padding(.top, 14)
                    .accessibilityLabel(StravaSheet.compatibleLabel)
            }
        }
    }
}
