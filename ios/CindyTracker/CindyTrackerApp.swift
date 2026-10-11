import SwiftUI

@main
struct CindyTrackerApp: App {
    init() {
        // The daily reminder is planned on launch, and every time the app comes forward.
        MainActor.assumeIsolated {
            ReminderCenter.shared.start()
            // Does nothing in a build with no Strava credentials.
            StravaCenter.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
                // Strava's app sends the athlete back to this app's own scheme; the web sheet does not
                // come this way, it hands the answer to its own completion.
                .onOpenURL { url in
                    guard StravaBuild.available, url.scheme == StravaBuild.config.applicationId else { return }
                    Task { @MainActor in await StravaCenter.shared.handleRedirect(url.absoluteString) }
                }
        }
    }
}
